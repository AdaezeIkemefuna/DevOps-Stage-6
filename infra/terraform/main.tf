terraform {
  required_version = ">= 1.0"
  
  backend "s3" {
    bucket = "hng-todo-app-terraform-state"
    key    = "hng-todo-app/terraform.tfstate"
    region = "us-east-1"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Route Table (FIXED TYPO)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "app_server" {
  name        = "${var.project_name}-server-sg"
  description = "Security group for TODO app server"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
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
    Name = "${var.project_name}-server-sg"
  }
}

# EC2 Key Pair (USE ONLY ONE - CHOOSE OPTION A OR B)

# OPTION A: Use your existing key (RECOMMENDED)
#resource "aws_key_pair" "this" {
 # key_name   = "${var.project_name}-key"
  #  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQGwlTWuGdDygRV92PyTlI8GUuWpdVzjkvoxBR5qPOJiLQRU0xti4tP3/FXa89fg3Gv5mLfjqTXJpImiVcB2CYMyjHODzr29MkH+retTADvm2Y5s370HnnQWP5Q8T6FnbzZh388WTYW7IoSMFdLuI4qH/2TlcAyWkfzXBCX0NXDkP13ZGAntID7aivhEzNZXe0hBL9hlSECDan4QpWPaiIq9OFWsON9pQhBCEyOG0vobQJfDt2LB1EBwOxZpKu0UC/Oegc89SlJI23UwX5k29nVaD1LbjA0OkKiGnRYc8SNrRp2s8G/BZP0DgwHP4fA/H8epnRAuM4TkshnQZ4nlVMQFsUhzh4CQzS691GtUIb21E93qK78dBHdLmtEaQVGeUtJdSf6ZkIxQQbjbsxhKH00l2Uu1e8rB6IeViGGQXWqnM1cTLfyJ8ca8YMgOqxesvxhMJeWs7LVzf53AYLcq2AtsepcNX9s9fRILElkXjeRxCE6h0mSuxDCSCv4yAR4OF18s4P2yNPRkNVUNxwX9pA8PAz0yj8T3Z0Ouu3jADYQYvbH//t3GQV5QZ4MtF8rPBopXucUAC+0gJVJpv47+TORzu9SArQ== hamsaikemefuna@gmail.com"
#}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.generated.public_key_openssh
}

# Data Sources
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

# EC2 Instance (FIXED KEY REFERENCE)
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app_server.id]
  key_name                    = aws_key_pair.this.key_name  # FIXED: was aws_key_pair.deployer
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20  # Reduced from 30GB to stay closer to free tier
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Remove any invalid characters from hostname
              hostnamectl set-hostname ${replace(var.project_name, "_", "-")}-server
              EOF

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    server_ip         = aws_instance.app_server.public_ip
    ssh_key_path      = var.ssh_private_key_path
    domain            = var.domain
    acme_email        = var.acme_email
    jwt_secret        = var.jwt_secret
    github_repo       = var.github_repo
  })
  filename = "${path.module}/../ansible/inventory.ini"

  depends_on = [aws_instance.app_server]
}

# Trigger Ansible