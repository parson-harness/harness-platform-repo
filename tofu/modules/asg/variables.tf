################################################################################
# AWS ASG Infrastructure Module Variables
################################################################################

variable "name_prefix" {
  description = "Prefix for all resource names (e.g., harness-demo-owner)"
  type        = string
}

variable "owner" {
  description = "Owner name for tagging and naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# VPC Configuration
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for the ASG VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (defaults to first 2 in region)"
  type        = list(string)
  default     = []
}

################################################################################
# EC2 / Launch Template Configuration
################################################################################

variable "instance_type" {
  description = "EC2 instance type for ASG instances"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "AMI ID for EC2 instances. Leave empty to auto-select latest Amazon Linux 2023."
  type        = string
  default     = ""
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

################################################################################
# Auto Scaling Group Configuration
################################################################################

variable "asg_min_size" {
  description = "Minimum number of instances in the base ASG (seed ASG, Harness manages deployed ASGs)"
  type        = number
  default     = 0
}

variable "asg_max_size" {
  description = "Maximum number of instances per ASG (used by Harness for deployed ASGs)"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Desired capacity for the base ASG (0 = no running instances until first Harness deploy)"
  type        = number
  default     = 0
}

################################################################################
# Application Load Balancer Configuration
################################################################################

variable "prod_listener_port" {
  description = "ALB listener port for production traffic (HTTPS)"
  type        = number
  default     = 443
}

variable "stage_listener_port" {
  description = "ALB listener port for stage traffic (B/G validation before swap)"
  type        = number
  default     = 8080
}

variable "app_port" {
  description = "Port the application listens on inside the container"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "HTTP path for ALB target group health checks"
  type        = string
  default     = "/actuator/health"
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before marking healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before marking unhealthy"
  type        = number
  default     = 3
}

variable "health_check_interval_seconds" {
  description = "Time between ALB health checks (seconds)"
  type        = number
  default     = 30
}

################################################################################
# DNS / TLS Configuration
################################################################################

variable "create_dns_record" {
  description = "Create Route53 CNAME record pointing <owner>.asg.<zone> to the ALB"
  type        = bool
  default     = false
}

variable "route53_zone_name" {
  description = "Route53 hosted zone name (e.g., harness-demo.dev)"
  type        = string
  default     = "harness-demo.dev"
}

variable "acm_cert_arn" {
  description = "ACM certificate ARN for the HTTPS ALB listener (must cover <owner>.asg.<zone>)"
  type        = string
  default     = ""
}
