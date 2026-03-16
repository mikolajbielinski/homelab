#!/bin/bash
exec > /var/log/transcribe.log 2>&1
set -euxo pipefail

echo "=== Starting transcription pipeline ==="

export HF_TOKEN="${hf_token}"
export PATH="/usr/local/bin:/usr/bin:$PATH"
BUCKET="s3://zgrzyt-ai"
WORKDIR="/tmp/zgrzyt"
mkdir -p "$WORKDIR/mp3" "$WORKDIR/transcripts"

# Install dependencies
echo "=== Installing dependencies ==="
apt-get update -qq && apt-get install -y -qq ffmpeg
pip3 install whisperx

# Write Python transcription worker
cat > "$WORKDIR/transcribe_worker.py" << 'EOFPY'
import sys
import os
import whisperx
import json
import gc
import torch
from whisperx.diarize import DiarizationPipeline

audio_file = sys.argv[1]
output_file = sys.argv[2]
hf_token = os.environ["HF_TOKEN"]
device = "cuda"

# 1. Transcribe
model = whisperx.load_model("large-v3", device, compute_type="float16")
audio = whisperx.load_audio(audio_file)
result = model.transcribe(audio, batch_size=16, language="pl")

# 2. Align
model_a, metadata = whisperx.load_align_model(language_code="pl", device=device)
result = whisperx.align(result["segments"], model_a, metadata, audio, device, return_char_alignments=False)
del model_a
gc.collect()
torch.cuda.empty_cache()

# 3. Diarize
diarize_model = DiarizationPipeline(token=hf_token, device=device)
diarize_segments = diarize_model(audio)
result = whisperx.assign_word_speakers(diarize_segments, result)

# 4. Save
with open(output_file, "w", encoding="utf-8") as f:
    json.dump(result["segments"], f, ensure_ascii=False, indent=2)

del model
gc.collect()
torch.cuda.empty_cache()
print("Transcription complete")
EOFPY

# Get list of MP3s from S3
echo "=== Fetching MP3 list ==="
aws s3 ls "$BUCKET/mp3/" | awk '{print $4}' | grep '\.mp3$' > "$WORKDIR/all_mp3s.txt"
TOTAL=$(wc -l < "$WORKDIR/all_mp3s.txt")
echo "Found $TOTAL MP3 files"

# Get already processed transcripts
aws s3 ls "$BUCKET/transcripts/" 2>/dev/null | awk '{print $4}' | sed 's/\.json$//' > "$WORKDIR/done.txt" || true

COUNT=0
while IFS= read -r mp3_file; do
    video_id="$${mp3_file%.mp3}"
    COUNT=$((COUNT + 1))

    # Skip if already transcribed
    if grep -qxF -- "$video_id" "$WORKDIR/done.txt"; then
        echo "[$COUNT/$TOTAL] Skipping (already transcribed): $video_id"
        continue
    fi

    echo "[$COUNT/$TOTAL] Processing: $video_id"

    # Download MP3
    aws s3 cp "$BUCKET/mp3/$mp3_file" "$WORKDIR/mp3/$mp3_file"

    # Transcribe
    python3 "$WORKDIR/transcribe_worker.py" "$WORKDIR/mp3/$mp3_file" "$WORKDIR/transcripts/$video_id.json"

    # Upload transcript to S3
    aws s3 cp "$WORKDIR/transcripts/$video_id.json" "$BUCKET/transcripts/$video_id.json"

    # Cleanup local files
    rm "$WORKDIR/mp3/$mp3_file"

    echo "[$COUNT/$TOTAL] Done: $video_id"
done < "$WORKDIR/all_mp3s.txt"

echo "=== All done! Shutting down ==="
shutdown -h now
