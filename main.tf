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
resource "aws_ssm_parameter" "db_url" {
  name  = "SPRING_DATASOURCE_URL"
  type  = "SecureString"
  value = "jdbc:postgresql://${aws_db_instance.postgres_rds.address}:5432/${var.db_name}"
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
          "ssm:GetParametersByPath"
        ],
        "Resource": "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/SPRING_DATASOURCE_*"
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

  tags = {
    name = "Jenkins-Server"
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo yum update -y
              
                # Install Jenkins, Docker, Java
                sudo amazon-linux-extras enable corretto17
                sudo yum install -y java-17-amazon-corretto git docker
                sudo systemctl start docker
                sudo systemctl enable docker
                sudo usermod -aG docker ec2-user

                # Wait to avoid conflicts
                sleep 30  

                # Install Jenkins GPG key manually
                sudo rpm --import https://pkg.jenkins.io/redhat/jenkins.io.key || { echo "Failed to import Jenkins key"; exit 1; }
                
                # Install Jenkins
                echo "Installing Jenkins..."
                sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat/jenkins.repo || { echo "Failed to download Jenkins repo"; exit 1; }
                sudo rpm --import https://pkg.jenkins.io/redhat/jenkins.io.key || { echo "Failed to import Jenkins key"; exit 1; }
                sudo yum install -y jenkins || { echo "Failed to install Jenkins"; exit 1; }

                # Start Jenkins and enable it to start on boot
                echo "Starting Jenkins..."
                sudo systemctl start jenkins || { echo "Failed to start Jenkins"; exit 1; }
                sudo systemctl enable jenkins || { echo "Failed to enable Jenkins"; exit 1; }

                # Verify Jenkins installation and log status
                echo "Verifying Jenkins installation..."
                sudo systemctl status jenkins >> /var/log/user-data.log 2>&1

                # Fetch environment variables from AWS SSM Parameter Store
                SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name "SPRING_DATASOURCE_URL" --with-decryption --query "Parameter.Value" --output text)
                SPRING_DATASOURCE_USERNAME=$(aws ssm get-parameter --name "SPRING_DATASOURCE_USERNAME" --with-decryption --query "Parameter.Value" --output text)
                SPRING_DATASOURCE_PASSWORD=$(aws ssm get-parameter --name "SPRING_DATASOURCE_PASSWORD" --with-decryption --query "Parameter.Value" --output text)

                # Persist Environment Variables
                echo "SPRING_DATASOURCE_URL=$SPRING_DATASOURCE_URL" | sudo tee -a /etc/environment
                echo "SPRING_DATASOURCE_USERNAME=$SPRING_DATASOURCE_USERNAME" | sudo tee -a /etc/environment
                echo "SPRING_DATASOURCE_PASSWORD=$SPRING_DATASOURCE_PASSWORD" | sudo tee -a /etc/environment

                # Reload environment variables
                source /etc/environment

            EOF
}

output "public_ip" {
  value = aws_instance.jenkins_server.public_ip
}
