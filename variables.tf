# Instance type for EC2
variable "instance_type" {
  description = "The type of instance to launch"
  type        = string
  default     = "t2.micro"
}

# AWS Region
variable "region" {
  description = "AWS region for resources"
  type        = string
}

# Database Password
variable "db_password" {
  description = "The password for the database"
  type        = string
  sensitive   = true
}

# Database Name
variable "db_name" {
  description = "The name for the database"
  type        = string
  sensitive   = true
}

# Database Username
variable "db_user" {
  description = "The username for the database"
  type        = string
  sensitive   = true
}

# SSH key for EC2 instance
variable "key_name" {
  description = "SSH key for EC2 instance"
  type        = string
}
