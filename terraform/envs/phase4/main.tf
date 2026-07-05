provider "aws" {
  region = var.region
}

# Phase 4 reuses Phase 3's VPC, public subnets, and RDS/Secrets Manager setup —
# it only replaces the standalone web EC2 instance with an ALB + Auto Scaling
# Group. Phase 3 must stay applied while Phase 4 exists.
data "terraform_remote_state" "phase3" {
  backend = "local"

  config = {
    path = "${path.module}/../phase3/terraform.tfstate"
  }
}

locals {
  vpc_id            = data.terraform_remote_state.phase3.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.phase3.outputs.public_subnet_ids
  db_sg_id          = data.terraform_remote_state.phase3.outputs.db_sg_id
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

# --- Security groups ---

module "alb_sg" {
  source = "../../modules/security"

  name        = "capstone-phase4-alb-sg"
  description = "Allow HTTP from the internet to the load balancer"
  vpc_id      = local.vpc_id

  cidr_ingress_rules = [
    {
      description = "HTTP from the internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

module "asg_web_sg" {
  source = "../../modules/security"

  name        = "capstone-phase4-web-sg"
  description = "Allow HTTP only from the ALB and SSH from an admin CIDR"
  vpc_id      = local.vpc_id

  cidr_ingress_rules = [
    {
      description = "SSH for administration"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_ssh_cidr]
    }
  ]

  sg_ingress_rules = [
    {
      description              = "HTTP from the ALB only"
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]
}

# Attached to Phase 3's db-sg (tracked here, not in Phase 3's state) so the
# Auto Scaling web tier can reach RDS.
resource "aws_vpc_security_group_ingress_rule" "asg_to_db" {
  security_group_id            = local.db_sg_id
  description                  = "MySQL from the Phase 4 Auto Scaling web tier"
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.asg_web_sg.security_group_id
}

# --- Load balancer ---

resource "aws_lb" "this" {
  name               = "capstone-phase4-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.alb_sg.security_group_id]
  subnets            = local.public_subnet_ids
}

resource "aws_lb_target_group" "web" {
  name        = "capstone-phase4-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# --- Launch template + Auto Scaling Group ---

resource "aws_launch_template" "web" {
  name_prefix   = "capstone-phase4-web-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = base64encode(file("${path.module}/../../scripts/userdata-phase3.sh"))

  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [module.asg_web_sg.security_group_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "capstone-phase4-web"
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name                      = "capstone-phase4-asg"
  min_size                  = var.asg_min_size
  max_size                  = var.asg_max_size
  desired_capacity          = var.asg_desired_capacity
  vpc_zone_identifier       = local.public_subnet_ids
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "capstone-phase4-web"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "capstone-phase4-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.target_cpu_utilization
  }
}
