terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Reference an existing EC2 instance
data "aws_instance" "existing_ec2" {
  instance_id = "i-xxxxxxxxxxxxxx"  # Replace with your actual EC2 instance ID
}

# Reference an existing security group
data "aws_security_group" "existing_sg" {
  id = "sg-xxxxxxxxxxxxxx"  # Replace with your existing security group ID
}

# IAM Role for EC2 Instance (if not already attached)
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

# IAM Role Policies - Attach policies to IAM Role
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

resource "aws_iam_role_policy_attachment" "pavan_ec2_full_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "pavan_ssm_invocation_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# IAM Instance Profile (if not already attached to the EC2 instance)
resource "aws_iam_instance_profile" "pavan_ec2_ssm_instance_profile" {
  name = "Pavan-EC2-SSM-InstanceProfile"
  role = aws_iam_role.pavan_ec2_ssm_role.name
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "pavan_ec2_log_group" {
  name              = "/aws/ec2/pavan-cloudwatch-logs"
  retention_in_days = 7
}

# S3 bucket for file storage
resource "aws_s3_bucket" "pavan_file_storage" {
  bucket = "pavan-file-storage-bucket-unique-id"
  acl    = "private"
}

# Upload example file to S3
resource "aws_s3_object" "pavan_example_file" {
  bucket                 = aws_s3_bucket.pavan_file_storage.bucket
  key                    = "example-file.txt"
  source                 = "/Users/saipavankarepe/Downloads/example-file.txt"
  server_side_encryption = "AES256"
}

# SSM Document for downloading a file from S3
resource "aws_ssm_document" "pavan_ssm_document" {
  name          = "Pavan-DownloadFileDocument"
  document_type = "Command"
  
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Download file from S3 and log output"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "downloadFile"
        inputs = {
          runCommand = [
            "aws s3 cp s3://pavan-file-storage-bucket-unique-id/example-file.txt /home/ubuntu/example-file.txt"
          ]
          outputS3BucketName = aws_s3_bucket.pavan_file_storage.bucket
          outputS3KeyPrefix  = "ssm-logs/"
        }
      }
    ]
  })
}

# SSM Maintenance Window Task for executing the SSM document
resource "aws_ssm_maintenance_window_task" "pavan_download_file_task" {
  window_id        = aws_ssm_maintenance_window.pavan_maintenance_window.id
  task_arn         = aws_ssm_document.pavan_ssm_document.arn
  task_type        = "RUN_COMMAND"
  service_role_arn = aws_iam_role.pavan_ec2_ssm_role.arn
  max_concurrency  = "1"
  max_errors       = "1"
  
  targets {
    key    = "InstanceIds"
    values = [data.aws_instance.existing_ec2.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment = "Download file from S3 and log output to S3"
    }
  }
}

# SSM Maintenance Window
resource "aws_ssm_maintenance_window" "pavan_maintenance_window" {
  name     = "Pavan-File-Update-Window"
  schedule = "cron(0/5 * * * ? *)"  # Every 5 minutes
  duration = 1
  cutoff   = 0
  enabled  = true
}

# Register Target for SSM Maintenance Window
resource "aws_ssm_maintenance_window_target" "pavan_ssm_target" {
  window_id     = aws_ssm_maintenance_window.pavan_maintenance_window.id
  resource_type = "INSTANCE"
  targets {
    key    = "InstanceIds"
    values = [data.aws_instance.existing_ec2.id]
  }
}
