#!/bin/sh
set -eu
SIDEY_RECORDING_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_RECORDING_ID=$(printf '%s' "$SIDEY_RECORDING_ROOT" | shasum -a 256 | cut -c 1-16)
SIDEY_RECORDING_DERIVED="$SIDEY_RECORDING_ROOT/build/review/$SIDEY_RECORDING_ID/sidey-reals/Release"
xcodebuild -project "$SIDEY_RECORDING_ROOT/macos/Recording/SIDEYRecording.xcodeproj" \
    -scheme sidey-reals -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$SIDEY_RECORDING_DERIVED" build
SIDEY_RECORDING_APP="$SIDEY_RECORDING_DERIVED/Build/Products/Release/sidey-reals.app"
python3 "$SIDEY_RECORDING_ROOT/scripts/macos/build_provenance.py" verify --app "$SIDEY_RECORDING_APP" --target sidey-reals
mkdir -p "$SIDEY_RECORDING_ROOT/macos/Recording/dist"
ditto "$SIDEY_RECORDING_APP" "$SIDEY_RECORDING_ROOT/macos/Recording/dist/sidey-reals.app"
codesign --verify --deep --strict "$SIDEY_RECORDING_ROOT/macos/Recording/dist/sidey-reals.app"
printf '완료: %s\n' "$SIDEY_RECORDING_ROOT/macos/Recording/dist/sidey-reals.app"
