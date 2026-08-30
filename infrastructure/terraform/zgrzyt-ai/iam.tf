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

resource "aws_iam_user" "reconciler" {
  name = "zgrzyt-reconciler"
}

resource "aws_iam_user_policy" "reconciler" {
  name = "zgrzyt-reconciler-access"
  user = aws_iam_user.reconciler.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.zgrzyt.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["mp3/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["${aws_s3_bucket.zgrzyt.arn}/mp3/*"]
      }
    ]
  })
}

resource "aws_iam_user" "embed" {
  name = "zgrzyt-embed"
}

resource "aws_iam_user_policy" "embed" {
  name = "zgrzyt-embed-access"
  user = aws_iam_user.embed.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.zgrzyt.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["transcripts/labeled/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.zgrzyt.arn}/transcripts/labeled/*"]
      }
    ]
  })
}

resource "aws_iam_user" "speakers" {
  name = "zgrzyt-speakers"
}

resource "aws_iam_user_policy" "speakers" {
  name = "zgrzyt-speakers-access"
  user = aws_iam_user.speakers.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.zgrzyt.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["transcripts/raw/*", "transcripts/labeled/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.zgrzyt.arn}/transcripts/raw/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.zgrzyt.arn}/transcripts/labeled/*"]
      }
    ]
  })
}
