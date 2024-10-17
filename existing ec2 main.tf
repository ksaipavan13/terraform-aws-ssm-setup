provider "aws" {
  region = "us-east-1"  # Modify as per your region
}

# Create an S3 Bucket for logs
resource "aws_s3_bucket" "pavan_file_storage" {
  bucket = "pavan-file-storage-bucket-unique-id"
  acl    = "private"

  tags = {
    Name = "pavan-file-storage-bucket"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "pavan_ec2_log_group" {
  name              = "/aws/ec2/pavan-cloudwatch-logs"
  retention_in_days = 7
}

# IAM Role for EC2 with required policies
resource "aws_iam_role" "pavan_ec2_ssm_role" {
  name               = "Pavan-EC2-SSM-Role"
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

# IAM Role Policies
resource "aws_iam_role_policy_attachment" "pavan_s3_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "pavan_ssm_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "pavan_cw_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy_attach" {
  role       = aws_iam_role.pavan_ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile (If not already attached to the EC2 instance)
resource "aws_iam_instance_profile" "pavan_ec2_ssm_instance_profile" {
  name = "Pavan-EC2-SSM-InstanceProfile"
  role = aws_iam_role.pavan_ec2_ssm_role.name
}

# Security Group for EC2 (If not already configured)
resource "aws_security_group" "pavan_ec2_sg" {
  name        = "Pavan-EC2-SG"
  description = "Allow inbound SSH and HTTP access"
  vpc_id      = "vpc-xxxxxxxx" # Replace with your existing VPC ID

  ingress {
    from_port   = 22
    to_port     = 22
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

# Use an existing EC2 instance
data "aws_instance" "existing_ec2" {
  instance_id = "i-xxxxxxxxxxxxxx"  # Replace with the existing EC2 instance ID
}

# SSM Document for Downloading File from S3
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
          # Output logs to S3
          outputS3BucketName = aws_s3_bucket.pavan_file_storage.bucket
          outputS3KeyPrefix  = "ssm-logs/"
          
          # Output logs to CloudWatch
          cloudWatchOutputConfig = {
            cloudWatchLogGroupName = aws_cloudwatch_log_group.pavan_ec2_log_group.name
            cloudWatchOutputEnabled = true
          }
        }
      }
    ]
  })
}

# SSM Maintenance Window for running the task
resource "aws_ssm_maintenance_window" "pavan_maintenance_window" {
  name         = "Pavan-Maintenance-Window"
  schedule     = "rate(1 day)"
  duration     = 1
  cutoff       = 1
  allow_unassociated_targets = true
}

# SSM Maintenance Window Target
resource "aws_ssm_maintenance_window_target" "pavan_ssm_target" {
  window_id     = aws_ssm_maintenance_window.pavan_maintenance_window.id
  resource_type = "INSTANCE"
  targets {
    key    = "InstanceIds"
    values = [data.aws_instance.existing_ec2.id]
  }
}

# SSM Maintenance Window Task to run the SSM document
resource "aws_ssm_maintenance_window_task" "pavan_download_file_task" {
  window_id        = aws_ssm_maintenance_window.pavan_maintenance_window.id
  task_arn         = aws_ssm_document.pavan_ssm_document.arn
  task_type        = "RUN_COMMAND"
  targets {
    key    = "InstanceIds"
    values = [data.aws_instance.existing_ec2.id]
  }
  task_invocation_parameters {
    run_command_parameters {
      comment  = "Download file from S3 and log output"
      output_s3_bucket_name = aws_s3_bucket.pavan_file_storage.bucket
      output_s3_key_prefix  = "ssm-logs/"
    }
  }
}
