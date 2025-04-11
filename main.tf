terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # You can bump to the latest major version
    }
  }

  required_version = ">= 1.3.0" # Optional: sets minimum Terraform CLI version
}

provider "aws" {
  region  = var.region
  profile = "myprofile"
}

// Built-in data source which fetches AWS account details currently being used e.g. account ID, user ID, ARN
data "aws_caller_identity" "current" {}

// SECURITY GROUPS
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins_sg"
  description = "Allow SSH, Jenkins Web UI, and App traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_postgres" {
  name        = "allow_postgres"
  description = "Allow PostgreSQL access from EC2"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// POSTGRES DB INSTANCE
resource "aws_db_instance" "postgres_rds" {
  identifier          = "spring-boot-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  storage_type        = "gp2"
  engine_version      = "15.12"
  username            = var.db_user
  password            = var.db_password
  db_name             = var.db_name
  publicly_accessible = false
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.allow_postgres.id]
}

// AWS SSM Parameter Store for env variables
resource "aws_ssm_parameter" "db_host" {
  name  = "SPRING_DATASOURCE_HOST"
  type  = "SecureString"
  value = aws_db_instance.postgres_rds.address
}

resource "aws_ssm_parameter" "db_username" {
  name  = "SPRING_DATASOURCE_USERNAME"
  type  = "SecureString"
  value = var.db_user
}

resource "aws_ssm_parameter" "db_password" {
  name  = "SPRING_DATASOURCE_PASSWORD"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "dockerhub_username" {
  name  = "DOCKERHUB_USERNAME"
  type  = "SecureString"
  value = var.dockerhub_username
}

resource "aws_ssm_parameter" "dockerhub_password" {
  name  = "DOCKERHUB_PASSWORD"
  type  = "SecureString"
  value = var.dockerhub_password
}

resource "aws_ssm_parameter" "vm_ssh_user" {
  name  = "VM_SSH_USER"
  type  = "SecureString"
  value = var.vm_ssh_user
}

resource "aws_ssm_parameter" "jenkins_admin_password" {
  name  = "JENKINS_ADMIN_PASSWORD"
  type  = "SecureString"
  value = var.jenkins_admin_password
}

// Creates an IAM Role for EC2 instance
resource "aws_iam_role" "jenkins_ssm_role" {
  name = "jenkins-ssm-role"

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }
  EOF
}

// Creates an IAM Policy to allow EC2 to read parameters from SSM
resource "aws_iam_policy" "ssm_read_policy" {
  name        = "SSMReadPolicy"
  description = "Allows EC2 to read parameters from AWS SSM"

  policy = <<EOF
  {
    "Version":  "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "s3:GetObject"
        ],
        "Resource": [
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/SPRING_DATASOURCE_*",
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/DOCKERHUB_*",
          "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/JENKINS_ADMIN_PASSWORD",
          "arn:aws:s3:::my-jenkins-config-bucket/jenkins.yaml"
          ]
      }
    ]
  }
  EOF
}

// Attaches a Policy to allow access to SSM Parameter Store
resource "aws_iam_role_policy_attachment" "jenkins_ssm_attach" {
  role       = aws_iam_role.jenkins_ssm_role.name
  policy_arn = aws_iam_policy.ssm_read_policy.arn
}

// Creates Instance Profile to assign the IAM Role to the EC2 instance
resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "jenkins-instance-profile"
  role = aws_iam_role.jenkins_ssm_role.name
}

// EC2 INSTANCE
resource "aws_instance" "jenkins_server" {
  ami                    = "ami-03f71e078efdce2c9"
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]

  iam_instance_profile = aws_iam_instance_profile.jenkins_instance_profile.name

  user_data = file("${path.module}/bootstrap.sh")

  tags = {
    name = "Jenkins-Server"
  }
}

output "public_ip" {
  value = aws_instance.jenkins_server.public_ip
}

// ===============================
# JCasC TEMPLATE FILE RENDERING
// ===============================
resource "null_resource" "render_jenkins_yaml" {
  depends_on = [aws_instance.jenkins_server]

  provisioner "local-exec" {
    command = "envsubst < ${path.module}/jenkins.yaml.tpl > ${path.module}/jenkins.yaml"
    environment = {
      admin_password             = var.jenkins_admin_password
      dockerhub_username         = var.dockerhub_username
      dockerhub_password         = var.dockerhub_password
      public_ip                  = aws_instance.jenkins_server.public_ip
      SPRING_DATASOURCE_HOST     = aws_db_instance.postgres_rds.address
      SPRING_DATASOURCE_USERNAME = var.db_user
      SPRING_DATASOURCE_PASSWORD = var.db_password
      SPRING_DATASOURCE_DBNAME   = var.db_name
    }

  }
}

// Create the final JCasC file after instance creation
resource "local_file" "jenkins_yaml" {
  depends_on = [null_resource.render_jenkins_yaml]
  content    = file("${path.module}/jenkins.yaml")
  filename   = "${path.module}/jenkins.yaml"
}

resource "aws_s3_bucket" "jenkins_bucket" {
  bucket = "my-jenkins-config-bucket"
}

resource "aws_s3_bucket_object" "jenkins_yaml" {
  bucket       = aws_s3_bucket.jenkins_bucket.id
  key          = "jenkins.yaml"
  source       = local_file.jenkins_yaml.filename
  content_type = "text/yaml"
  acl          = "private"
}

