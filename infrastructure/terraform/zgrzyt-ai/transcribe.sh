Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/cloud-config; charset="us-ascii"

#cloud-config
cloud_final_modules:
  - [scripts-user, always]

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash

shutdown -h +480 "dead-man switch - 8h" || true

exec > /var/log/transcribe.log 2>&1

export HF_SECRET_ARN="${hf_secret_arn}"
export AWS_DEFAULT_REGION="${aws_region}"

export PATH="/usr/local/bin:/usr/bin:$PATH"
BUCKET="s3://zgrzyt-ai"
WORKDIR="/opt/zgrzyt"
LOGTS="$(date -u +%Y%m%dT%H%M%SZ)"
PROCESSED=0
FAILED=0

set -euo pipefail

cleanup() {
  rc=$?
  set +e
  set +x
  echo "=== DONE. Exit code: $rc. Processed: $PROCESSED. Failed: $FAILED ==="
  aws s3 cp /var/log/transcribe.log "$BUCKET/logs/$LOGTS.log" || true
  shutdown -c || true
  shutdown -h now
}
trap cleanup EXIT

mkdir -p "$WORKDIR/mp3" "$WORKDIR/transcripts"

cat > "$WORKDIR/transcribe_worker.py" << 'EOFPY'
${transcribe_worker}
EOFPY

pip3 install 'boto3==1.42.49'
python3 "$WORKDIR/transcribe_worker.py" --check-secret

echo "=== Installing dependencies ==="
apt-get update -qq && apt-get install -y -qq ffmpeg
pip3 install 'whisperx==3.8.6'

echo "=== List of items already completed (by prefix) ==="
: > "$WORKDIR/done.txt"
for prefix in transcripts/raw transcripts/labeled failed; do
    aws s3 ls "$BUCKET/$prefix/" 2>/dev/null \
      | awk '{print $4}' | sed 's/\.json$//' | awk 'NF' >> "$WORKDIR/done.txt" || true
done
sort -u -o "$WORKDIR/done.txt" "$WORKDIR/done.txt"
echo "Already finished: $(wc -l < "$WORKDIR/done.txt")"

aws s3 ls "$BUCKET/mp3/" | awk '{print $4}' | grep '\.mp3$' > "$WORKDIR/all.txt"
TOTAL=$(wc -l < "$WORKDIR/all.txt")
COUNT=0
echo "MP3 in bucket: $TOTAL"

while IFS= read -r mp3_file; do
    video_id="$${mp3_file%.mp3}"
    COUNT=$((COUNT + 1))

    if grep -qxF -- "$video_id" "$WORKDIR/done.txt"; then
        echo "[$COUNT/$TOTAL] Skipping (already done): $video_id"
        continue
    fi

    echo "[$COUNT/$TOTAL] Processing: $video_id"
    aws s3 cp "$BUCKET/mp3/$mp3_file" "$WORKDIR/mp3/$mp3_file"

    if timeout 5400 python3 "$WORKDIR/transcribe_worker.py" \
            "$WORKDIR/mp3/$mp3_file" "$WORKDIR/transcripts/$video_id.json"; then
        aws s3 cp "$WORKDIR/transcripts/$video_id.json" \
                  "$BUCKET/transcripts/raw/$video_id.json"
        PROCESSED=$((PROCESSED + 1))
        echo "[$COUNT/$TOTAL] OK: $video_id"
    else
        rc=$?
        if [ "$rc" -eq 78 ]; then
            echo "Secret unavailable; stopping without marking $video_id as failed"
            exit "$rc"
        fi
        FAILED=$((FAILED + 1))
        echo "[$COUNT/$TOTAL] FAILED (rc=$rc): $video_id - marking as failed"
        printf '{"id":"%s","rc":%s,"when":"%s","log":"logs/%s.log"}\n' \
            "$video_id" "$rc" "$(date -u +%FT%TZ)" "$LOGTS" \
          | aws s3 cp - "$BUCKET/failed/$video_id.json" || true
    fi

    rm -f "$WORKDIR/mp3/$mp3_file"
done < "$WORKDIR/all.txt"

echo "=== Loop finished. Processed: $PROCESSED, failed: $FAILED ==="

--==BOUNDARY==--
