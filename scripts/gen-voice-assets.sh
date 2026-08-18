#!/usr/bin/env bash
# Generate pre-recorded voice assets from the phrase list using edge-tts
# (Microsoft cloud voices via the Edge Read Aloud API — free, no key).
# Run this ONCE (or whenever a phrase changes) to (re)produce assets/voice/*.mp3.
#
# Install: `pipx install edge-tts` (or `pip install --user edge-tts`).
# Available voices: `edge-tts --list-voices | grep en-US`
# Override the voice with: VOICE="en-US-GuyNeural" ./scripts/gen-voice-assets.sh

set -euo pipefail

VOICE="${VOICE:-en-US-AriaNeural}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/voice"
mkdir -p "$OUT_DIR"

if ! command -v edge-tts >/dev/null; then
  echo "ERROR: edge-tts not found on PATH."
  echo "Install: pipx install edge-tts   (or: pip install --user edge-tts)"
  exit 1
fi

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
  echo "-> $name.mp3"
  edge-tts --voice "$VOICE" --text "$text" --write-media "$OUT_DIR/$name.mp3"
done <<< "$PHRASES"

echo
echo "✅ Done. Files in $OUT_DIR"
ls -la "$OUT_DIR"
