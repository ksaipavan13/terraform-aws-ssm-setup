terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"  # You can specify a particular version range here
    }
  }
}


provider "aws" {
  region = "us-east-1"
}

# Create VPC
resource "aws_vpc" "pavan_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Create Internet Gateway
resource "aws_internet_gateway" "pavan_igw" {
  vpc_id = aws_vpc.pavan_vpc.id
}

# Create Public Subnet
resource "aws_subnet" "pavan_public_subnet" {
  vpc_id            = aws_vpc.pavan_vpc.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Create Route Table for Public Subnet
resource "aws_route_table" "pavan_public_rt" {
  vpc_id = aws_vpc.pavan_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pavan_igw.id
  }
}

# Associate Route Table with Public Subnet
resource "aws_route_table_association" "pavan_public_rt_assoc" {
  subnet_id      = aws_subnet.pavan_public_subnet.id
  route_table_id = aws_route_table.pavan_public_rt.id
}

# Security Group for EC2 Instance (Allow SSH and HTTP)
resource "aws_security_group" "pavan_ec2_sg" {
  vpc_id = aws_vpc.pavan_vpc.id
  name   = "pavan-allow-ssh-http"
  description = "Allow SSH and HTTP access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

# IAM Role for EC2 Instance
resource "aws_iam_role" "pavan_ec2_ssm_role" {
  name = "Pavan-EC2-SSM-Role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach Policies to IAM Role
resource "aws_iam_role_policy_attachment" "pavan_ssm_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "pavan_cw_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "pavan_s3_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "pavan_ec2_ssm_instance_profile" {
  name = "Pavan-EC2-SSM-InstanceProfile"
  role = aws_iam_role.pavan_ec2_ssm_role.name
}

# Create CloudWatch Log Group
resource "aws_cloudwatch_log_group" "pavan_ec2_log_group" {
  name              = "/aws/ec2/pavan-cloudwatch-logs"
  retention_in_days = 7
}

# Launch EC2 Instance in Public Subnet
resource "aws_instance" "pavan_ssm_ec2" {
  ami                    = "ami-0866a3c8686eaeeba"  # Replace with a valid AMI ID in your region
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.pavan_ec2_ssm_instance_profile.name
  key_name               = "iam"  # Ensure this key exists in your AWS account
  subnet_id              = aws_subnet.pavan_public_subnet.id
  security_groups        = ["sg-0535860c1233f0d28"]
  associate_public_ip_address = true

  tags = {
    Name = "Pavan-SSM-EC2"
  }

  # User Data to install SSM agent and CloudWatch agent
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y amazon-ssm-agent
    systemctl start amazon-ssm-agent
    systemctl enable amazon-ssm-agent

    # Install CloudWatch Agent
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start
  EOF
}

# Create S3 Bucket
resource "aws_s3_bucket" "pavan_file_storage" {
  bucket = "pavan-file-storage-bucket-unique-id"
}

# Upload Example File to S3 Bucket
resource "aws_s3_object" "pavan_example_file" {
  bucket = aws_s3_bucket.pavan_file_storage.bucket
  key    = "example-file.txt"
  source = "/Users/saipavankarepe/Downloads/example-file.txt"  # Make sure this file exists
  server_side_encryption = "AES256"
}

# SSM Maintenance Window (optional)
resource "aws_ssm_maintenance_window" "pavan_maintenance_window" {
  name         = "Pavan-File-Update-Window"
  schedule     = "cron(0/5 * * * ? *)" # Executes every 2 minutes
  duration     = 1
  cutoff       = 0
  allow_unassociated_targets = false
  enabled                    = true
  
}

# Register Target for SSM Maintenance Window
resource "aws_ssm_maintenance_window_target" "pavan_ssm_target" {
  window_id    = aws_ssm_maintenance_window.pavan_maintenance_window.id
  name         = "Pavan-EC2-Target"
  description  = "Target for Pavan EC2 instance"
  resource_type = "INSTANCE"  # This specifies the target is an EC2 instance
  
  targets {
    key    = "InstanceIds"
    values = [aws_instance.pavan_ssm_ec2.id]  # Reference the EC2 instance ID
  }
}

# Create SSM Task to Download File from S3
resource "aws_ssm_maintenance_window_task" "pavan_download_file_task" {
  window_id = aws_ssm_maintenance_window.pavan_maintenance_window.id
  task_arn  = "AWS-RunShellScript"
  task_type = "RUN_COMMAND"
  service_role_arn = aws_iam_role.pavan_ec2_ssm_role.arn
  max_concurrency  = "1"
  max_errors       = "1"
  
  targets {
    key    = "InstanceIds"
    values = [aws_instance.pavan_ssm_ec2.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment = "Download file from S3 and save to EC2"
      parameter {
        name   = "commands"
        values = [
          "aws s3 cp s3://pavan-file-storage-bucket-unique-id/example-file.txt /home/ubuntu/example-file.txt"
        ]
      }
    }
  }
}

