#!/bin/sh
set -eu
SIDEY_RECORDING_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_RECORDING_TEST_DIR="$SIDEY_RECORDING_ROOT/build/recording-tests"
xcodebuild -project "$SIDEY_RECORDING_ROOT/macos/Recording/SIDEYRecording.xcodeproj" \
    -scheme sidey-reals -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$SIDEY_RECORDING_TEST_DIR" test "$@"
