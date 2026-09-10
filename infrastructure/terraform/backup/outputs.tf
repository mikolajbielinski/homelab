output "backups_bucket" {
  description = "Bucket the cluster uploads backups to."
  value       = aws_s3_bucket.homelab_backups.bucket
}

output "backups_prefix" {
  description = "Prefix the backup IAM user is allowed to write to."
  value       = local.backup_prefix
}
