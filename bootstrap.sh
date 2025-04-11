#!/bin/bash

# Exit on error
set -e

# Install required tools
yum update -y
yum install -y java-17-amazon-corretto git docker unzip awscli

# Start and enable Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

# Install Jenkins
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
yum upgrade -y
yum install -y jenkins

# Enable Jenkins service, but don't start yet
systemctl enable jenkins

# Create JCasC config directory
mkdir -p /var/lib/jenkins/casc_configs
chown -R jenkins:jenkins /var/lib/jenkins/casc_configs

# Pull jenkins.yaml from S3 (make sure the instance has S3 access via IAM role)
aws s3 cp s3://my-jenkins-config-bucket/jenkins.yaml /var/lib/jenkins/casc_configs/jenkins.yaml
chown jenkins:jenkins /var/lib/jenkins/casc_configs/jenkins.yaml

# Set environment variable so Jenkins picks up the JCasC file
echo "CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/jenkins.yaml" >> /etc/sysconfig/jenkins

# Restart Jenkins (initial start with config)
systemctl start jenkins
