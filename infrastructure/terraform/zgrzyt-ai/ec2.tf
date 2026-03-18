data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_key_pair" "zgrzyt" {
  key_name   = "zgrzyt-ai"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO2uL9Odn/V4wF+ZWpWcXeWAuJyWPNlyAlBM98kDaKMX mikolaj.bielinski10@gmail.com"
}

resource "aws_security_group" "zgrzyt" {
  name        = "zgrzyt-ai"
  description = "SSH + outbound for zgrzyt-ai EC2"

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

resource "aws_iam_role" "zgrzyt_ec2" {
  name = "zgrzyt-ai-ec2"

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

resource "aws_iam_role_policy" "zgrzyt_ec2_s3" {
  name = "zgrzyt-ai-s3-access"
  role = aws_iam_role.zgrzyt_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.zgrzyt.arn,
          "${aws_s3_bucket.zgrzyt.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "zgrzyt_ec2" {
  name = "zgrzyt-ai-ec2"
  role = aws_iam_role.zgrzyt_ec2.name
}

resource "aws_spot_instance_request" "zgrzyt" {
  ami                         = data.aws_ami.deep_learning.id
  instance_type               = "g4dn.xlarge"
  key_name                    = aws_key_pair.zgrzyt.key_name
  security_groups             = [aws_security_group.zgrzyt.name]
  iam_instance_profile        = aws_iam_instance_profile.zgrzyt_ec2.name
  spot_type                      = "persistent"
  wait_for_fulfillment           = true
  instance_interruption_behavior = "stop"

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/transcribe.sh", {
    hf_token = var.hf_token
  })

  tags = {
    Name = "zgrzyt-ai"
  }
}
