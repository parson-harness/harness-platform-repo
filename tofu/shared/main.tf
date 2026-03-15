################################################################################
# Shared Infrastructure - Run ONCE per AWS Account
# Creates shared ALB and Route 53 hosted zone for all sandboxes/POVs
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # This uses a separate state file - manually configure or use local state
  # backend "s3" {
  #   bucket         = "harness-demo-shared-tfstate"
  #   key            = "shared/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "harness-demo"
      ManagedBy = "tofu-shared"
      Purpose   = "shared-infrastructure"
    }
  }
}

################################################################################
# Variables
################################################################################

variable "aws_region" {
  description = "AWS region for shared resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use (for SSO)"
  type        = string
  default     = "default"
}

variable "domain_name" {
  description = "Base domain for demo apps (e.g., demo.harness.io)"
  type        = string
  default     = "demo.harness.io"
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional, creates HTTP-only if not provided)"
  type        = string
  default     = ""
}

################################################################################
# Security Group for Shared ALB
################################################################################

resource "aws_security_group" "shared_alb" {
  name        = "harness-demo-shared-alb-sg"
  description = "Security group for shared demo ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "harness-demo-shared-alb-sg"
  }
}

################################################################################
# Shared Application Load Balancer
################################################################################

resource "aws_lb" "shared" {
  name               = "harness-demo-shared-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.shared_alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true

  tags = {
    Name = "harness-demo-shared-alb"
  }
}

# Default target group (returns 404 for unmatched requests)
resource "aws_lb_target_group" "default" {
  name     = "harness-demo-default-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-404"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.shared.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Harness Demo - No matching sandbox found"
      status_code  = "404"
    }
  }
}

# HTTPS Listener (only if certificate provided)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.shared.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Harness Demo - No matching sandbox found"
      status_code  = "404"
    }
  }
}

################################################################################
# Route 53 Hosted Zone (optional - use existing if you have one)
################################################################################

# Uncomment if you want to create a new hosted zone
# resource "aws_route53_zone" "demo" {
#   name = var.domain_name
#
#   tags = {
#     Name = "harness-demo-zone"
#   }
# }

# Wildcard DNS record pointing to the shared ALB
# resource "aws_route53_record" "wildcard" {
#   zone_id = aws_route53_zone.demo.zone_id
#   name    = "*.${var.domain_name}"
#   type    = "A"
#
#   alias {
#     name                   = aws_lb.shared.dns_name
#     zone_id                = aws_lb.shared.zone_id
#     evaluate_target_health = true
#   }
# }

################################################################################
# Outputs
################################################################################

output "alb_arn" {
  description = "ARN of the shared ALB"
  value       = aws_lb.shared.arn
}

output "alb_dns_name" {
  description = "DNS name of the shared ALB"
  value       = aws_lb.shared.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the shared ALB (for Route 53 alias records)"
  value       = aws_lb.shared.zone_id
}

output "alb_security_group_id" {
  description = "Security group ID of the shared ALB"
  value       = aws_security_group.shared_alb.id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (empty if no certificate)"
  value       = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : ""
}

output "sandbox_registration_example" {
  description = "Example for registering a new sandbox"
  value       = <<-EOT
    # Each sandbox adds a listener rule to route traffic:
    
    resource "aws_lb_listener_rule" "sandbox" {
      listener_arn = "${aws_lb_listener.http.arn}"
      priority     = 100  # Unique per sandbox
    
      action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.my_sandbox.arn
      }
    
      condition {
        host_header {
          values = ["my-sandbox.${var.domain_name}"]
        }
      }
    }
  EOT
}
