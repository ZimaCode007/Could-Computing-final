provider "aws" {
  region = var.region
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

module "network" {
  source = "../../modules/network"

  name_prefix          = "capstone-phase2"
  vpc_cidr             = var.vpc_cidr
  azs                  = [var.az]
  public_subnet_cidrs  = [var.public_subnet_cidr]
  private_subnet_cidrs = []
}

module "web_sg" {
  source = "../../modules/security"

  name        = "capstone-phase2-web-sg"
  description = "Allow HTTP from the internet and SSH from an admin CIDR"
  vpc_id      = module.network.vpc_id

  cidr_ingress_rules = [
    {
      description = "HTTP to the Node app"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [var.allowed_http_cidr]
    },
    {
      description = "SSH for administration"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_ssh_cidr]
    },
    {
      description = "MySQL from within the VPC only (Phase 3 Cloud9 needs this for the one-time data migration)"
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  ]
}

module "web" {
  source = "../../modules/compute"

  name                = "capstone-phase2-web"
  ami_id              = data.aws_ami.ubuntu.id
  instance_type       = var.instance_type
  subnet_id           = module.network.public_subnet_ids[0]
  security_group_ids  = [module.web_sg.security_group_id]
  key_name            = var.key_name
  associate_public_ip = true
  user_data           = file("${path.module}/../../scripts/userdata-phase2.sh")
}
