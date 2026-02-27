#!/usr/bin/env bash
set -euo pipefail

WORK_DIR="/work"
SPEED="${SPEED:-1.0}"
FFMPEG_THREADS="${FFMPEG_THREADS:-0}"
VIDEO_CRF="${VIDEO_CRF:-28}"
VIDEO_PRESET="${VIDEO_PRESET:-slow}"
AUDIO_BITRATE="${AUDIO_BITRATE:-96k}"
DISABLE_AUDIO="${DISABLE_AUDIO:-0}"

if [[ ! -d "$WORK_DIR" ]]; then
  echo "Work directory not found in container: $WORK_DIR"
  exit 1
fi

if ! awk "BEGIN { exit !($SPEED > 0) }"; then
  echo "Invalid SPEED: $SPEED (must be > 0)"
  exit 1
fi

if [[ ! "$FFMPEG_THREADS" =~ ^[0-9]+$ ]]; then
  echo "Invalid FFMPEG_THREADS: $FFMPEG_THREADS (must be integer >= 0)"
  exit 1
fi

if [[ ! "$VIDEO_CRF" =~ ^[0-9]+$ ]] || (( VIDEO_CRF < 0 || VIDEO_CRF > 51 )); then
  echo "Invalid VIDEO_CRF: $VIDEO_CRF (must be integer 0..51)"
  exit 1
fi

if [[ "$DISABLE_AUDIO" != "0" && "$DISABLE_AUDIO" != "1" ]]; then
  echo "Invalid DISABLE_AUDIO: $DISABLE_AUDIO (must be 0 or 1)"
  exit 1
fi

build_atempo_filter() {
  local speed="$1"
  local remaining="$speed"
  local filters=()

  while awk "BEGIN { exit !($remaining > 2.0) }"; do
    filters+=("atempo=2.0")
    remaining="$(awk "BEGIN { printf \"%.8f\", $remaining / 2.0 }")"
  done

  while awk "BEGIN { exit !($remaining < 0.5) }"; do
    filters+=("atempo=0.5")
    remaining="$(awk "BEGIN { printf \"%.8f\", $remaining * 2.0 }")"
  done

  filters+=("atempo=$remaining")

  local joined="${filters[0]}"
  local i
  for ((i = 1; i < ${#filters[@]}; i++)); do
    joined+=",${filters[i]}"
  done

  echo "$joined"
}

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

  has_audio=0
  audio_stream="$(ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$input_abs" || true)"
  if [[ -n "$audio_stream" ]]; then
    has_audio=1
  fi

  ffmpeg_cmd=(
    ffmpeg -y
    -threads "$FFMPEG_THREADS"
    -i "$input_abs"
    -map 0:v:0
  )

  if [[ "$DISABLE_AUDIO" == "0" ]]; then
    ffmpeg_cmd+=(
      -map 0:a?
    )
  fi

  if ! awk "BEGIN { exit !($SPEED == 1.0) }"; then
    ffmpeg_cmd+=(
      -filter:v "setpts=PTS/$SPEED"
    )

    if [[ "$DISABLE_AUDIO" == "0" && "$has_audio" -eq 1 ]]; then
      ffmpeg_cmd+=(
        -filter:a "$(build_atempo_filter "$SPEED")"
      )
    fi
  fi

  ffmpeg_cmd+=(
    -c:v libx264
    -preset "$VIDEO_PRESET"
    -crf "$VIDEO_CRF"
    -pix_fmt yuv420p
    -force_key_frames "expr:gte(t,n_forced*2)"
    -movflags +faststart
  )

  if [[ "$DISABLE_AUDIO" == "0" ]]; then
    ffmpeg_cmd+=(
      -c:a aac
      -b:a "$AUDIO_BITRATE"
      -ar 48000
    )
  else
    ffmpeg_cmd+=(
      -an
    )
  fi

  ffmpeg_cmd+=(
    "$output_abs"
  )

  "${ffmpeg_cmd[@]}"

  ((converted_count+=1))
done < <(find "$WORK_DIR" -type f -iname "*.webm" -print0)

echo "Completed. Converted: $converted_count, Skipped: $skipped_count"
