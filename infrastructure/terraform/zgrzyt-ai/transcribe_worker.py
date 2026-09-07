"""Transcribe one audio file, retrieving the HF token only inside this process."""

import gc
import json
import os
import sys


SECRET_ERROR = 78


def load_hf_token():
    import boto3
    from botocore.config import Config

    client = boto3.client(
        "secretsmanager",
        region_name=os.environ["AWS_DEFAULT_REGION"],
        config=Config(
            connect_timeout=5,
            read_timeout=5,
            retries={"mode": "standard", "total_max_attempts": 3},
        ),
    )
    response = client.get_secret_value(
        SecretId=os.environ["HF_SECRET_ARN"], VersionStage="AWSCURRENT"
    )
    token = response.get("SecretString")
    if not isinstance(token, str):
        raise ValueError("Expected a plain-text token")
    token = token.strip()
    if not token.startswith("hf_") or len(token) <= 3 or any(c.isspace() for c in token):
        raise ValueError("Expected a plain-text token")
    return token


def transcribe(audio_file, output_file, hf_token):
    import torch
    import whisperx
    from whisperx.diarize import DiarizationPipeline

    device = "cuda"
    model = whisperx.load_model("large-v3", device, compute_type="float16")
    audio = whisperx.load_audio(audio_file)
    result = model.transcribe(audio, batch_size=16, language="pl")

    model_a, metadata = whisperx.load_align_model(language_code="pl", device=device)
    result = whisperx.align(
        result["segments"], model_a, metadata, audio, device, return_char_alignments=False
    )
    del model_a
    gc.collect()
    torch.cuda.empty_cache()

    diarize_model = DiarizationPipeline(token=hf_token, device=device)
    diarize_segments = diarize_model(audio)
    result = whisperx.assign_word_speakers(diarize_segments, result)

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(result["segments"], f, ensure_ascii=False, indent=2)

    del model
    gc.collect()
    torch.cuda.empty_cache()
    print("Transcription complete")


def main(args=None):
    args = sys.argv[1:] if args is None else args
    check_only = args == ["--check-secret"]
    if not check_only and len(args) != 2:
        print("Usage: transcribe_worker.py AUDIO OUTPUT | --check-secret", file=sys.stderr)
        return 2

    try:
        hf_token = load_hf_token()
    except Exception:
        print(
            "Cannot load Hugging Face token. Check the EC2 role, network access, and "
            "the secret's AWSCURRENT value (plain-text hf_ token). Queue left for retry.",
            file=sys.stderr,
        )
        return SECRET_ERROR

    if check_only:
        print("Hugging Face secret is available")
        return 0

    transcribe(args[0], args[1], hf_token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
