#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPOSITORY_ROOT="${SCRIPT_DIR:h:h}"
SOURCE="${1:-$SCRIPT_DIR/sources/pixel_chinchilla_approved_sheet.png}"
OUTPUT="${2:-$REPOSITORY_ROOT/macos/SIDEY/Resources/Characters/PixelChinchilla/pixel_chinchilla.png}"

command -v magick >/dev/null || {
  print -u2 "ImageMagick is required to import the approved chinchilla master"
  exit 1
}
[[ -f "$SOURCE" ]] || {
  print -u2 "Missing chinchilla master: $SOURCE"
  exit 1
}

TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/sidey-chinchilla.XXXXXX")"
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT

mkdir -p "${OUTPUT:h}"
SOURCE_METADATA="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$SOURCE")"
SOURCE_WIDTH="$(print -r -- "$SOURCE_METADATA" | awk '/pixelWidth:/ { print $2 }')"
SOURCE_HEIGHT="$(print -r -- "$SOURCE_METADATA" | awk '/pixelHeight:/ { print $2 }')"
SOURCE_HAS_ALPHA="$(print -r -- "$SOURCE_METADATA" | awk '/hasAlpha:/ { print $2 }')"

if [[ "$SOURCE_WIDTH" == "240" && "$SOURCE_HEIGHT" == "24" && "$SOURCE_HAS_ALPHA" == "yes" ]]; then
  # The approved source is already the exact runtime sheet. Preserve its bytes so
  # review hashes describe the same artifact that ships in the app.
  cp "$SOURCE" "$OUTPUT"
else
  # Backward-compatible import path for the original 1920x819 concept sheet.
  typeset -a CROPS=(
    "175x170+23+317"
    "174x165+213+322"
    "173x174+402+313"
    "169x171+589+296"
    "175x173+774+314"
    "172x171+965+296"
    "169x164+1154+323"
    "177x150+1337+337"
    "183x109+1529+378"
    "185x109+1727+378"
  )
  typeset -a FRAMES=()

  for INDEX in {1..10}; do
    FRAME_INDEX=$((INDEX - 1))
    FRAME="$TEMP_DIRECTORY/frame-$FRAME_INDEX.png"
    magick "$SOURCE" \
      -crop "${CROPS[$INDEX]}" +repage \
      -channel A -threshold 35% +channel \
      -trim +repage \
      -filter point -resize 11.5% \
      -gravity south -background none -extent 24x21 \
      -gravity northwest -extent 24x24 \
      "$FRAME"
    FRAMES+=("$FRAME")
  done

  magick "${FRAMES[@]}" +append -strip -define png:exclude-chunks=date,time "$OUTPUT"
fi

METADATA="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUTPUT")"
WIDTH="$(print -r -- "$METADATA" | awk '/pixelWidth:/ { print $2 }')"
HEIGHT="$(print -r -- "$METADATA" | awk '/pixelHeight:/ { print $2 }')"
HAS_ALPHA="$(print -r -- "$METADATA" | awk '/hasAlpha:/ { print $2 }')"
[[ "$WIDTH" == "240" && "$HEIGHT" == "24" && "$HAS_ALPHA" == "yes" ]] || {
  print -u2 "Imported chinchilla sheet must be 240x24 RGBA"
  exit 1
}

print "Imported approved chinchilla master to $OUTPUT"
shasum -a 256 "$OUTPUT"
