variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "windows_username" {
  description = "The local Windows user to create on the instance"
  type        = string
  default     = "deployuser"
}

variable "create_key_pair" {
  description = "Create a new key pair (true) or use existing key by name (false)"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Existing key name to use if create_key_pair is false"
  type        = string
  default     = ""
}

variable "allowed_cidr" {
  description = "CIDR allowed to connect via RDP"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ami_owner" {
  description = "AMI owner to filter when looking up Windows AMI"
  type        = string
  default     = "amazon"
}
