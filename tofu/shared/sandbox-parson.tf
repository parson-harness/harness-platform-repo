################################################################################
# Parson Sandbox - EKS Target Group and Listener Rule
################################################################################

# Target group for EKS pods (IP-based)
resource "aws_lb_target_group" "parson_eks" {
  name        = "harness-demo-parson-eks"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name    = "harness-demo-parson-eks"
    Owner   = "parson"
    Service = "parsondemoapp"
  }
}

# Listener rule to route parson traffic
resource "aws_lb_listener_rule" "parson" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.parson_eks.arn
  }

  # Route by path prefix (no DNS needed)
  condition {
    path_pattern {
      values = ["/parson", "/parson/*"]
    }
  }
}

# Also route root path for direct ALB access
resource "aws_lb_listener_rule" "parson_root" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.parson_eks.arn
  }

  # Default route (lowest priority that matches)
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Output the target group ARN for manual target registration
output "parson_target_group_arn" {
  description = "Target group ARN for Parson EKS pods"
  value       = aws_lb_target_group.parson_eks.arn
}

output "parson_alb_url" {
  description = "URL to access Parson's demo app"
  value       = "http://${aws_lb.shared.dns_name}"
}
