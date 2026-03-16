resource "aws_iam_user" "zgrzyt" {
  name = "zgrzyt-ai"
}

resource "aws_iam_access_key" "zgrzyt" {
  user = aws_iam_user.zgrzyt.name
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
