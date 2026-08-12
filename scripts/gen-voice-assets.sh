#!/usr/bin/env bash
# Generate pre-recorded voice assets from the phrase list using macOS `say`.
# Run this ONCE (or whenever a phrase changes) to (re)produce assets/voice/*.mp3.
# Replace with your AI-TTS pipeline (ElevenLabs / OpenAI TTS) if you want a
# non-macOS voice.

set -euo pipefail

VOICE="${VOICE:-Samantha (Enhanced)}"   # override with VOICE="Ava (Premium)" etc.
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/voice"
mkdir -p "$OUT_DIR"

# format: filename|text
PHRASES=$(cat <<'EOF'
welcome|Welcome. Please select your destination.
search_destination|Search for your destination.
capture_photo|Please capture a photo to find your location.
tap_capture|Tap the capture button at the bottom to find your location.
capturing|Capturing photo...
relocalizing|Re-localizing...
location_updated|Location updated.
location_failed|Failed to update location.
navigation_started|Navigation started. You can tap the camera view to update your location anytime.
destination_selected|Destination selected. Proceeding to camera.
EOF
)

echo "Voice: $VOICE"
echo "Output: $OUT_DIR"
echo

while IFS='|' read -r name text; do
  [[ -z "$name" ]] && continue
  aiff="$OUT_DIR/$name.aiff"
  mp3="$OUT_DIR/$name.mp3"
  echo "-> $name.mp3"
  say -v "$VOICE" -o "$aiff" "$text"
  # ffmpeg to mp3 (small, universal). Falls back to leaving aiff if ffmpeg absent.
  if command -v ffmpeg >/dev/null; then
    ffmpeg -y -loglevel error -i "$aiff" -codec:a libmp3lame -qscale:a 2 "$mp3"
    rm "$aiff"
  else
    echo "   ffmpeg not installed — leaving as $name.aiff. Run: brew install ffmpeg"
    mv "$aiff" "$OUT_DIR/$name.aiff"
  fi
done <<< "$PHRASES"

echo
echo "✅ Done. Files in $OUT_DIR"
ls -la "$OUT_DIR"
