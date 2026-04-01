################################################################################
# AWS ASG Infrastructure Module
#
# Creates everything needed for Harness Blue/Green and Canary ASG deployments:
#   - Self-contained VPC with public subnets (no NAT, cost-effective for demos)
#   - ALB: HTTPS/443 (prod), HTTP/8080 (stage validation), HTTP/80 → redirect
#   - Two target groups (prod/stage) for Harness B/G traffic swapping
#   - EC2 Launch Template (Packer-built AMI, JAR pre-installed, systemd service)
#   - Seed/base ASG (desired=0, Harness uses it as a configuration template)
#   - EC2 instance profile (SSM + CloudWatch, no ECR needed)
#   - Optional Route53 CNAME: <owner>.asg.harness-demo.dev → ALB
################################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

locals {
  effective_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023[0].id

  azs = length(var.availability_zones) > 0 ? var.availability_zones : [
    data.aws_availability_zones.available.names[0],
    data.aws_availability_zones.available.names[1]
  ]

  public_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 8, 1),
    cidrsubnet(var.vpc_cidr, 8, 2)
  ]
}

################################################################################
# VPC - Self-contained networking for ASG demo
# Using public subnets only (no NAT required) for cost efficiency
################################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-igw"
  })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# Security Groups
################################################################################

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-asg-alb-sg"
  description = "Allow HTTP/HTTPS and stage traffic to the ASG demo ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS production traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Stage traffic (B/G validation)"
    from_port   = var.stage_listener_port
    to_port     = var.stage_listener_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-alb-sg"
  })
}

resource "aws_security_group" "instance" {
  name        = "${var.name_prefix}-asg-instance-sg"
  description = "Allow app traffic from ALB only; allow outbound for SSM/updates"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound (SSM, updates, internet)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-instance-sg"
  })
}

################################################################################
# Application Load Balancer
################################################################################

resource "aws_lb" "main" {
  name               = "${var.name_prefix}-asg-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-alb"
  })
}

resource "aws_lb_target_group" "prod" {
  name        = "${var.name_prefix}-asg-prod-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    interval            = var.health_check_interval_seconds
    timeout             = 10
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-prod-tg"
    Role = "production"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "stage" {
  name        = "${var.name_prefix}-asg-stage-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    interval            = var.health_check_interval_seconds
    timeout             = 10
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-stage-tg"
    Role = "stage"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-http-redirect"
    Role = "redirect"
  })
}

resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-prod-listener"
    Role = "production"
  })
}

resource "aws_lb_listener" "stage" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.stage_listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stage.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-stage-listener"
    Role = "stage"
  })
}

################################################################################
# Listener Rules - Data sources to get default rule ARNs for B/G deployments
################################################################################

locals {
  prod_listener_rule_arn  = ""
  stage_listener_rule_arn = ""
}

################################################################################
# IAM - EC2 Instance Profile
# Allows instances to: use SSM Session Manager, write CloudWatch logs
# No ECR needed - JAR is baked into the AMI by Packer
################################################################################

data "aws_iam_policy_document" "instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-asg-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-instance-role"
  })
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "instance_cloudwatch" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-asg-instance-profile"
  role = aws_iam_role.instance.name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-instance-profile"
  })
}

################################################################################
# Route53 DNS - Optional CNAME: <owner>.asg.harness-demo.dev → ALB
################################################################################

data "aws_route53_zone" "harness_demo_dev" {
  count = var.create_dns_record ? 1 : 0
  name  = var.route53_zone_name
}

resource "aws_route53_record" "asg_app" {
  count   = var.create_dns_record ? 1 : 0
  zone_id = data.aws_route53_zone.harness_demo_dev[0].zone_id
  name    = "${var.owner}-asg.${var.route53_zone_name}"
  type    = "CNAME"
  ttl     = 60
  records = [aws_lb.main.dns_name]
}

################################################################################
# Launch Template
# Harness creates new versions of this LT on each deploy with rendered user data
################################################################################

resource "aws_launch_template" "main" {
  name        = "${var.name_prefix}-asg-lt"
  description = "Launch Template for Harness Demo App ASG deployments"

  image_id      = local.effective_ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.instance.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-asg-instance"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-asg-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-asg-lt"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Base / Seed ASG
# Desired=0 by default - Harness reads this ASG's config as a template for
# creating blue/green/canary ASGs. Harness manages the actual deployed ASGs.
################################################################################

resource "aws_autoscaling_group" "base" {
  name                = "${var.name_prefix}-asg-base"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = aws_subnet.public[*].id

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  health_check_type         = "ELB"
  health_check_grace_period = 120
  default_cooldown          = 60

  target_group_arns = [aws_lb_target_group.prod.arn]

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-asg-base"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "harness-managed"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [
      desired_capacity,
      target_group_arns
    ]
  }
}
