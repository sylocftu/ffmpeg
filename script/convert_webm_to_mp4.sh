#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="/work"

if [[ ! -d "$WORK_DIR" ]]; then
  echo "Work directory not found in container: $WORK_DIR"
  exit 1
fi

converted_count=0
skipped_count=0

while IFS= read -r -d '' input_file; do
  rel_path="${input_file#"$WORK_DIR"/}"
  input_abs="$input_file"
  output_abs="${input_abs%.*}.mp4"
  output_rel="${rel_path%.*}.mp4"

  if [[ -f "$output_abs" ]]; then
    echo "Skip (exists): $output_rel"
    ((skipped_count+=1))
    continue
  fi

  echo "Convert: $rel_path -> $output_rel"

  ffmpeg -y \
    -i "$input_abs" \
    -map 0:v:0 -map 0:a? \
    -c:v libx264 \
    -preset medium \
    -crf 23 \
    -pix_fmt yuv420p \
    -force_key_frames "expr:gte(t,n_forced*2)" \
    -c:a aac \
    -b:a 128k \
    -ar 48000 \
    -movflags +faststart \
    "$output_abs"

  ((converted_count+=1))
done < <(find "$WORK_DIR" -type f -iname "*.webm" -print0)

echo "Completed. Converted: $converted_count, Skipped: $skipped_count"
