provider "aws" {
  region = var.region
}

# Phase 3 extends the VPC that Phase 2 created rather than building a new one,
# so the two phases stay network-adjacent (Cloud9 can reach the Phase 2
# instance by private IP for the data migration). This means Phase 2 must stay
# applied while Phase 3 exists.
data "terraform_remote_state" "phase2" {
  backend = "local"

  config = {
    path = "${path.module}/../phase2/terraform.tfstate"
  }
}

locals {
  vpc_id = data.terraform_remote_state.phase2.outputs.vpc_id
  igw_id = data.terraform_remote_state.phase2.outputs.igw_id
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

# The lab account restricts IAM role creation; we attach the existing
# LabInstanceProfile (backed by LabRole) so the web instance can read the
# Secrets Manager secret.
data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

# --- Network: add a second public subnet + two private subnets to the existing VPC ---

resource "aws_subnet" "public_b" {
  vpc_id                  = local.vpc_id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = var.az_b
  map_public_ip_on_launch = true

  tags = {
    Name = "capstone-phase3-public-b"
  }
}

resource "aws_route_table" "public_b" {
  vpc_id = local.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = local.igw_id
  }

  tags = {
    Name = "capstone-phase3-public-b-rt"
  }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_b.id
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = local.vpc_id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = count.index == 0 ? var.az_a : var.az_b

  tags = {
    Name = "capstone-phase3-private-${count.index}"
  }
}

# Local-only route table (no NAT) — RDS doesn't need outbound internet access.
resource "aws_route_table" "private" {
  vpc_id = local.vpc_id

  tags = {
    Name = "capstone-phase3-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security groups ---

module "web_sg" {
  source = "../../modules/security"

  name        = "capstone-phase3-web-sg"
  description = "Allow HTTP from the internet and SSH from an admin CIDR"
  vpc_id      = local.vpc_id

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
    }
  ]
}

# Cloud9's EC2 instance manages its own security group; look it up by the
# environment tag AWS applies automatically so the migration step can reach RDS.
data "aws_security_group" "cloud9" {
  filter {
    name   = "tag:aws:cloud9:environment"
    values = [aws_cloud9_environment_ec2.migration.id]
  }
}

module "db_sg" {
  source = "../../modules/security"

  name        = "capstone-phase3-db-sg"
  description = "Allow MySQL only from the web tier"
  vpc_id      = local.vpc_id

  sg_ingress_rules = [
    {
      description              = "MySQL from the web app"
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      source_security_group_id = module.web_sg.security_group_id
    },
    {
      description              = "MySQL from Cloud9 for the one-time data migration"
      from_port                = 3306
      to_port                  = 3306
      protocol                 = "tcp"
      source_security_group_id = data.aws_security_group.cloud9.id
    }
  ]
}

# --- Secrets Manager ---

resource "random_password" "db" {
  length  = 20
  special = false # keep it JSON/shell safe for the secret string and userdata
}

module "db_secret" {
  source = "../../modules/secrets"

  name        = var.secret_name
  description = "Database credentials for the student records web app"
  secret_string = jsonencode({
    user     = var.db_username
    password = random_password.db.result
    host     = module.database.address
    db       = var.db_name
  })
}

# --- RDS ---

module "database" {
  source = "../../modules/database"

  name_prefix            = "capstone-phase3"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db.result
  instance_class         = var.db_instance_class
  subnet_ids             = aws_subnet.private[*].id
  vpc_security_group_ids = [module.db_sg.security_group_id]
}

# --- Web tier (new instance, connects to RDS via Secrets Manager) ---

module "web" {
  source = "../../modules/compute"

  name                 = "capstone-phase3-web"
  ami_id               = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.public_b.id
  security_group_ids   = [module.web_sg.security_group_id]
  key_name             = var.key_name
  associate_public_ip  = true
  iam_instance_profile = data.aws_iam_instance_profile.lab.name
  user_data            = file("${path.module}/../../scripts/userdata-phase3.sh")
}

# --- Cloud9, used to create the secret via CLI (already done via Terraform above)
# and to run the Script-3 data migration from the Phase 2 instance into RDS ---

resource "aws_cloud9_environment_ec2" "migration" {
  name                        = "capstone-phase3-cloud9"
  instance_type               = var.cloud9_instance_type
  image_id                    = "amazonlinux-2-x86_64"
  subnet_id                   = aws_subnet.public_b.id
  connection_type             = "CONNECT_SSH"
  automatic_stop_time_minutes = 30
}
