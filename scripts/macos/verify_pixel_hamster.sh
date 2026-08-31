#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPOSITORY_ROOT="${SCRIPT_DIR:h:h}"
CHARACTERS_ROOT="$REPOSITORY_ROOT/macos/SIDEY/Resources/Characters"

typeset -A EXPECTED_HASHES
EXPECTED_HASHES[pixel_hamster]="43171c1dd614629058b6d593c57ca0e5841b0be03a04a05181dfda67c53a7f45"
EXPECTED_HASHES[pixel_cat]="d8b370c03b5cf0ede6aa0d9fa6210030e164b015a920622e89ae86f835e018b2"
EXPECTED_HASHES[pixel_puppy]="8f56a5fda51a224802f41d6d1c359a138c83036b7da3e0a35777f9f4ed38d5f7"
EXPECTED_HASHES[pixel_rabbit]="f8e53749200a284f7729ea9baac3237a9fac0caf8efedf9102dcee065e521342"
EXPECTED_HASHES[pixel_penguin]="f171503f8ffb938732583a4b6f42443e7a69120bb17496f6e8d34372da2ea886"

typeset -A DIRECTORIES
DIRECTORIES[pixel_hamster]="PixelHamster"
DIRECTORIES[pixel_cat]="PixelCat"
DIRECTORIES[pixel_puppy]="PixelPuppy"
DIRECTORIES[pixel_rabbit]="PixelRabbit"
DIRECTORIES[pixel_penguin]="PixelPenguin"

for CHARACTER_ID in pixel_hamster pixel_cat pixel_puppy pixel_rabbit pixel_penguin; do
  ASSET="$CHARACTERS_ROOT/${DIRECTORIES[$CHARACTER_ID]}/$CHARACTER_ID.png"
  [[ -f "$ASSET" ]] || { print -u2 "Missing character sheet: $ASSET"; exit 1; }

  METADATA="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$ASSET")"
  WIDTH="$(print -r -- "$METADATA" | awk '/pixelWidth:/ { print $2 }')"
  HEIGHT="$(print -r -- "$METADATA" | awk '/pixelHeight:/ { print $2 }')"
  HAS_ALPHA="$(print -r -- "$METADATA" | awk '/hasAlpha:/ { print $2 }')"
  [[ "$WIDTH" == "240" && "$HEIGHT" == "24" ]] || {
    print -u2 "$CHARACTER_ID sheet must be 240x24, got ${WIDTH}x${HEIGHT}"
    exit 1
  }
  [[ "$HAS_ALPHA" == "yes" ]] || { print -u2 "$CHARACTER_ID sheet must include alpha"; exit 1; }

  ACTUAL_SHA256="$(shasum -a 256 "$ASSET" | awk '{ print $1 }')"
  [[ "$ACTUAL_SHA256" == "${EXPECTED_HASHES[$CHARACTER_ID]}" ]] || {
    print -u2 "$CHARACTER_ID sheet hash drifted; regenerate and review before updating the contract"
    exit 1
  }
  print "Verified $CHARACTER_ID: 10x 24x24 RGBA frames, deterministic hash $ACTUAL_SHA256"
done
