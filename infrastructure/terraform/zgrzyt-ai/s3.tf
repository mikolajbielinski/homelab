resource "aws_s3_bucket" "zgrzyt" {
  bucket = "zgrzyt-ai"
}

resource "aws_s3_bucket_versioning" "zgrzyt" {
  bucket = aws_s3_bucket.zgrzyt.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "zgrzyt" {
  bucket                  = aws_s3_bucket.zgrzyt.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "zgrzyt" {
  bucket = aws_s3_bucket.zgrzyt.id
  rule {
    id     = "kasuj-stare-wersje-mp3"
    status = "Enabled"
    filter { prefix = "mp3/" }
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}