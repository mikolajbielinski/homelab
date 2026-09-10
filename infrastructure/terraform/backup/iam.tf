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
        Sid      = "ListPrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.homelab_backups.arn]
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.backup_prefix}/*"]
          }
        }
      },
      {
        Sid      = "ListMultipartUploads"
        Effect   = "Allow"
        Action   = ["s3:ListBucketMultipartUploads"]
        Resource = [aws_s3_bucket.homelab_backups.arn]
      },
      {
        Sid      = "WriteObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = ["${aws_s3_bucket.homelab_backups.arn}/${local.backup_prefix}/*"]
      }
    ]
  })
}
