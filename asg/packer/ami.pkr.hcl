################################################################################
# Harness Demo App - Packer AMI Template
# Bakes the application JAR directly into an Amazon Linux 2023 AMI.
# The app runs as a systemd service; user data only writes runtime env vars.
################################################################################

packer {
  required_plugins {
    amazon = {
      version = "= 1.3.9"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ami_name_prefix" {
  type    = string
  default = "harness-demo-app"
}

variable "app_version" {
  type        = string
  description = "Version tag baked into the AMI name and tags (e.g., pipeline sequence ID)"
}

variable "jar_source" {
  type        = string
  description = "Path to the application JAR (relative to packer working directory)"
  default     = "../../target/harness-demo-app-1.0-SNAPSHOT.jar"
}

variable "owner" {
  type        = string
  description = "Owner tag for the AMI (e.g., SE username)"
  default     = "harness"
}

locals {
  ami_name = "${var.ami_name_prefix}-${var.app_version}"
}

source "amazon-ebs" "demo_app" {
  ami_name      = local.ami_name
  instance_type = var.instance_type
  region        = var.aws_region

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }

  ssh_username = "ec2-user"

  tags = {
    Name        = local.ami_name
    Application = var.ami_name_prefix
    Owner       = var.owner
    Version     = var.app_version
    ManagedBy   = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.demo_app"]

  provisioner "shell" {
    inline = [
      "sudo dnf install -y java-17-amazon-corretto awscli",
      "sudo mkdir -p /opt/app",
      "sudo useradd -r -s /bin/false harness-app || true"
    ]
  }

  provisioner "file" {
    source      = var.jar_source
    destination = "/tmp/app.jar"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/app.jar /opt/app/app.jar",
      "sudo chown harness-app:harness-app /opt/app/app.jar",
      "sudo chmod 644 /opt/app/app.jar",
      "sudo touch /etc/harness-demo-app.env",
      "sudo chown harness-app:harness-app /etc/harness-demo-app.env"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo tee /etc/systemd/system/harness-demo-app.service > /dev/null <<'SYSTEMD'\n[Unit]\nDescription=Harness Demo App\nAfter=network.target\n\n[Service]\nType=simple\nUser=harness-app\nEnvironmentFile=/etc/harness-demo-app.env\nWorkingDirectory=/opt/app\nExecStart=/usr/bin/java -jar /opt/app/app.jar --server.port=8080\nRestart=always\nRestartSec=10\nStandardOutput=journal\nStandardError=journal\n\n[Install]\nWantedBy=multi-user.target\nSYSTEMD",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable harness-demo-app"
    ]
  }
}
