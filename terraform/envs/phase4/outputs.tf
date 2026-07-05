output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_url" {
  value = "http://${aws_lb.this.dns_name}"
}

output "asg_name" {
  value = aws_autoscaling_group.web.name
}
