resource "aws_iam_user" "homelab_backups_auto" {
  name = "homelab-backups-auto"
}

resource "aws_iam_user_policy" "homelab_backups_auto" {
  name = "homelab-backups-auto-access"
  user = aws_iam_user.homelab_backups_auto.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.homelab_backups.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["auto-backups/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["${aws_s3_bucket.homelab_backups.arn}/auto-backups/*"]
      }
    ]
  })
}