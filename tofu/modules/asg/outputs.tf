################################################################################
# ASG Module Outputs
################################################################################

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_name" {
  description = "Name of the Application Load Balancer"
  value       = aws_lb.main.name
}

output "prod_listener_arn" {
  description = "ARN of the production ALB listener (HTTPS/443, live traffic)"
  value       = aws_lb_listener.prod.arn
}

output "stage_listener_arn" {
  description = "ARN of the stage ALB listener (port 8080, B/G validation)"
  value       = aws_lb_listener.stage.arn
}

output "prod_target_group_arn" {
  description = "ARN of the production target group (blue)"
  value       = aws_lb_target_group.prod.arn
}

output "stage_target_group_arn" {
  description = "ARN of the stage target group (green)"
  value       = aws_lb_target_group.stage.arn
}

output "base_asg_name" {
  description = "Name of the base/seed ASG that Harness uses as a configuration template"
  value       = aws_autoscaling_group.base.name
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.main.id
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.app.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile for EC2 instances"
  value       = aws_iam_instance_profile.app.arn
}

output "instance_security_group_id" {
  description = "ID of the EC2 instance security group"
  value       = aws_security_group.instance.id
}

output "launch_template_name" {
  description = "Name of the Launch Template"
  value       = aws_launch_template.main.name
}

output "app_fqdn" {
  description = "Fully qualified domain name if Route53 record was created, else ALB DNS name"
  value       = var.create_dns_record ? "${var.owner}-asg.${var.route53_zone_name}" : aws_lb.main.dns_name
}

output "vpc_id" {
  description = "ID of the ASG VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "app_url" {
  description = "Production app URL (HTTPS)"
  value       = var.create_dns_record ? "https://${var.owner}-asg.${var.route53_zone_name}" : "https://${aws_lb.main.dns_name}"
}

output "stage_url" {
  description = "Stage app URL (HTTP/8080) - for B/G validation before swap"
  value       = var.create_dns_record ? "http://${var.owner}-asg.${var.route53_zone_name}:8080" : "http://${aws_lb.main.dns_name}:8080"
}

output "prod_listener_rule_arn" {
  description = "ARN of the production listener default rule (for B/G deployments)"
  value       = aws_lb_listener_rule.prod.arn
}

output "stage_listener_rule_arn" {
  description = "ARN of the stage listener default rule (for B/G deployments)"
  value       = aws_lb_listener_rule.stage.arn
}
