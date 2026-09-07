data "aws_region" "current" {}

resource "aws_secretsmanager_secret" "huggingface" {
  name                    = "zgrzyt-ai/huggingface"
  description             = "Hugging Face read token for zgrzyt-ai diarization models"
  recovery_window_in_days = 30
}

resource "aws_iam_role_policy" "zgrzyt_ec2_huggingface" {
  name = "zgrzyt-ai-huggingface-read"
  role = aws_iam_role.zgrzyt_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.huggingface.arn]
    }]
  })
}
