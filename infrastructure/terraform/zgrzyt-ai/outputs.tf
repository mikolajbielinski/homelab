output "instance_id" {
  value = aws_instance.zgrzyt.id
}

output "huggingface_secret_arn" {
  description = "Populate this secret outside Terraform with the plain-text HF token."
  value       = aws_secretsmanager_secret.huggingface.arn
}
