#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPOSITORY_ROOT="${SCRIPT_DIR:h:h}"
ASSET="$REPOSITORY_ROOT/macos/SIDEY/Resources/Characters/PixelHamster/pixel_hamster.png"
EXPECTED_SHA256="9b5de18254b57864ec485cd42d639a7b0730c4f60d117b0a3fc73aa9a9fec39d"

[[ -f "$ASSET" ]] || { print -u2 "Missing pixel hamster sheet: $ASSET"; exit 1; }

METADATA="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$ASSET")"
WIDTH="$(print -r -- "$METADATA" | awk '/pixelWidth:/ { print $2 }')"
HEIGHT="$(print -r -- "$METADATA" | awk '/pixelHeight:/ { print $2 }')"
HAS_ALPHA="$(print -r -- "$METADATA" | awk '/hasAlpha:/ { print $2 }')"
[[ "$WIDTH" == "192" && "$HEIGHT" == "24" ]] || {
  print -u2 "Pixel hamster sheet must be 192x24, got ${WIDTH}x${HEIGHT}"
  exit 1
}
[[ "$HAS_ALPHA" == "yes" ]] || { print -u2 "Pixel hamster sheet must include alpha"; exit 1; }

ACTUAL_SHA256="$(shasum -a 256 "$ASSET" | awk '{ print $1 }')"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || {
  print -u2 "Pixel hamster sheet hash drifted; regenerate and review before updating the contract"
  exit 1
}

print "Verified pixel_hamster: 8x 24x24 RGBA frames, deterministic hash $ACTUAL_SHA256"
