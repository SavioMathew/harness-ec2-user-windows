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

# Generate a new RSA private key if requested
resource "tls_private_key" "this" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair using the generated public key
resource "aws_key_pair" "generated" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = "tf-win-key"
  public_key = tls_private_key.this[0].public_key_openssh
}

# Security group allowing RDP (3389)
resource "aws_security_group" "rdp" {
  name        = "tf-windows-rdp-sg"
  description = "Allow RDP access"
  vpc_id      = "vpc-0c59173db44beeca5"

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "RDP access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Lookup available subnets in your VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = ["vpc-0c59173db44beeca5"]
  }
}

locals {
  subnet_id = try(data.aws_subnets.default.ids[0], null)
}

# Get latest Windows Server 2019 or 2022 AMI
data "aws_ami" "windows" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [
      "Windows_Server-2019-English-Full-Base-*",
      "Windows_Server-2022-English-Full-Base-*"
    ]
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

# Create the S3 bucket to store private key (no encryption)
resource "aws_s3_bucket" "private_keys" {
  bucket = "my-tf-private-key-store-12345"   # <-- CHANGE this to a unique name
  acl    = "private"

  tags = {
    Name = "TerraformPrivateKeys"
  }
}

# Upload generated PEM private key to S3
resource "aws_s3_object" "private_key_pem" {
  count   = var.create_key_pair ? 1 : 0
  bucket  = aws_s3_bucket.private_keys.bucket
  key     = "keys/${aws_key_pair.generated[0].key_name}.pem"
  content = tls_private_key.this[0].private_key_pem
  acl     = "private"

  tags = {
    ManagedBy = "Terraform"
  }
}

# EC2 instance configuration
resource "aws_instance" "windows" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  key_name                    = var.create_key_pair ? aws_key_pair.generated[0].key_name : (var.key_name != "" ? var.key_name : null)
  vpc_security_group_ids      = [aws_security_group.rdp.id]
  subnet_id                   = local.subnet_id
  associate_public_ip_address = true

  # PowerShell script to create user
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

# ----------------------------
# Outputs
# ----------------------------

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
  description = "PEM private key (only when Terraform created a key pair)."
  value       = var.create_key_pair ? tls_private_key.this[0].private_key_pem : ""
  sensitive   = true
}

output "private_key_s3_path" {
  value       = var.create_key_pair ? "s3://${aws_s3_bucket.private_keys.bucket}/keys/${aws_key_pair.generated[0].key_name}.pem" : null
  description = "S3 path where the PEM private key is stored"
}
