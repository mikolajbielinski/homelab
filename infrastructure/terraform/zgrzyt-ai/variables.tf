variable "hf_token" {
  description = "HuggingFace token for pyannote diarization models"
  type        = string
  sensitive   = true
}

variable "ami_id" {
  description = "Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04) 20260825"
  type        = string
  default     = "ami-089d23ba15a274c07"
}

variable "root_volume_size" {
  type        = number
  default     = 100
}
