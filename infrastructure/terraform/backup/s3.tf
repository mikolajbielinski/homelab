resource "aws_s3_bucket" "homelab_backups" {
  bucket = "homelab-lynx-backups"
}

resource "aws_s3_bucket_versioning" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "homelab_backups" {
  bucket                  = aws_s3_bucket.homelab_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "homelab_backups" {
  bucket     = aws_s3_bucket.homelab_backups.id
  depends_on = [aws_s3_bucket_versioning.homelab_backups]

  rule {
    id     = "remove-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }

  rule {
    id     = "remove-old-backups"
    status = "Enabled"
    filter {
      prefix = "auto-backups/"
    }

    expiration {
      days = 14
    }
  }
}