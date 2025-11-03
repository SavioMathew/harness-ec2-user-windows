terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

locals {
  windows_password = "Jake#25081997"
}

# Optional creation of an EC2 key pair (stores public key only)
resource "tls_private_key" "this" {
  count      = var.create_key_pair ? 1 : 0
  algorithm  = "RSA"
  rsa_bits   = 4096
}

resource "aws_key_pair" "generated" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = "tf-win-key"
  public_key = tls_private_key.this[0].public_key_openssh
}

# Security group allowing RDP only from allowed CIDR
resource "aws_security_group" "rdp" {
  name        = "tf-windows-rdp-sg"
  description = "Allow RDP"
  vpc_id      = "vpc-0c59173db44beeca5"

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "RDP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = ["vpc-0c59173db44beeca5"]
  }
}

# pick first subnet in default VPC
locals {
  subnet_id = try(data.aws_subnets.default.ids[0], null)
}

# Get latest Windows Server 2019 Core/2022 Base AMI (Amazon-owned)
data "aws_ami" "windows" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*","Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 instance
resource "aws_instance" "windows" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  key_name                    = var.create_key_pair ? aws_key_pair.generated[0].key_name : (var.key_name != "" ? var.key_name : null)
  vpc_security_group_ids      = [aws_security_group.rdp.id]
  subnet_id                   = local.subnet_id
  associate_public_ip_address = true

  # EC2 user data: PowerShell script to create user & set ACLs.
  user_data = base64encode(templatefile("${path.module}/user_data.ps1.tpl", {
    windows_username = var.windows_username
    windows_password = local.windows_password
    newUser          = var.windows_username
  }))

  tags = {
    Name = "tf-windows-instance"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow retrieving subnet if needed
output "instance_id" {
  value = aws_instance.windows.id
}

output "instance_public_ip" {
  value = aws_instance.windows.public_ip
}

output "windows_user" {
  value = var.windows_username
}

output "windows_user_password" {
  description = "Static Windows password"
  value       = local.windows_password
  sensitive   = true
}

output "generated_private_key_pem" {
  description = "PEM private key (only when Terraform created a key pair). Save this securely if created."
  value       = var.create_key_pair ? tls_private_key.this[0].private_key_pem : ""
  sensitive   = true
}
