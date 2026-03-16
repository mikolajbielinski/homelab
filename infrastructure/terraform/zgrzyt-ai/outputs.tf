output "access_key_id" {
  value = aws_iam_access_key.zgrzyt.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.zgrzyt.secret
  sensitive = true
}

output "spot_instance_id" {
  value = aws_spot_instance_request.zgrzyt.spot_instance_id
}
