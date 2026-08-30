resource "aws_iam_user" "zgrzyt" {
  name = "zgrzyt-ai"
}

resource "aws_iam_user_policy" "zgrzyt_s3" {
  name = "zgrzyt-ai-s3-access"
  user = aws_iam_user.zgrzyt.name

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

resource "aws_iam_user" "orchestrator" {
  name = "zgrzyt-orchestrator"
}

resource "aws_iam_user_policy" "orchestrator" {
  name = "zgrzyt-orchestrator-access"
  user = aws_iam_user.orchestrator.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.zgrzyt.arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "${aws_s3_bucket.zgrzyt.arn}/notified/*",
          "${aws_s3_bucket.zgrzyt.arn}/alerted/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances"]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Name" = "zgrzyt-ai"
          }
        }
      }
    ]
  })
}
