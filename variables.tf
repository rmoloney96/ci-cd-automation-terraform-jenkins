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

variable "dockerhub_username" {
  description = "DockerHub username"
  type        = string
}

variable "dockerhub_password" {
  description = "DockerHub password"
  type        = string
}

variable "vm_ssh_user" {
  description = "SSH username for Jenkins EC2 instance"
  type        = string
}

variable "jenkins_admin_password" {
  description = "Password for Jenkins admin user"
  type        = string
  sensitive   = true
}
