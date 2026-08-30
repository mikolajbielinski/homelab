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
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.zgrzyt.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.zgrzyt.arn}/mp3/*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.zgrzyt.arn}/transcripts/raw/*",
          "${aws_s3_bucket.zgrzyt.arn}/logs/*",
          "${aws_s3_bucket.zgrzyt.arn}/failed/*",
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "zgrzyt_ec2" {
  name = "zgrzyt-ai-ec2"
  role = aws_iam_role.zgrzyt_ec2.name
}

resource "aws_instance" "zgrzyt" {
  ami                    = var.ami_id
  instance_type          = "g4dn.xlarge"
  key_name               = aws_key_pair.zgrzyt.key_name
  vpc_security_group_ids = [aws_security_group.zgrzyt.id]
  iam_instance_profile   = aws_iam_instance_profile.zgrzyt_ec2.name

  # TEMPORARY: the account has a 0 vCPU quota for on-demand G instances, so we run on
  # spot for now. Spot cannot be stopped unless the request is persistent, and a
  # persistent request restarts the instance by itself after every shutdown - so the
  # machine terminates instead. Spot defaults to terminate and AWS rejects setting
  # instance_initiated_shutdown_behavior on it, so the attribute is omitted here.
  # Add it back as "stop" together with on-demand once the quota lands.
  instance_market_options {
    market_type = "spot"

    spot_options {
      spot_instance_type = "one-time"
    }
  }

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/transcribe.sh", {
    hf_token = var.hf_token
  })

  user_data_replace_on_change = false

  tags = {
    Name = "zgrzyt-ai"
  }
}

resource "aws_cloudwatch_metric_alarm" "zgrzyt_idle" {
  alarm_name          = "zgrzyt-ai-idle-stop"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 9
  threshold           = 5
  comparison_operator = "LessThanThreshold"
  dimensions          = { InstanceId = aws_instance.zgrzyt.id }
  treat_missing_data  = "notBreaching"
  # Must match instance_initiated_shutdown_behavior above: a one-time spot instance
  # cannot be stopped, so the alarm terminates it instead. Switch back to :stop when
  # the on-demand quota lands.
  alarm_actions = ["arn:aws:automate:eu-central-1:ec2:terminate"]
}
