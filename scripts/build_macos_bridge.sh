#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SIDEY_NATIVE_DIR="$SIDEY_REPO_ROOT/native/macos"
SIDEY_API_DIR="$SIDEY_NATIVE_DIR/.generated"
SIDEY_API_FILE="$SIDEY_API_DIR/extension_api.json"
SIDEY_BUILD_TARGET=${1:-editor}
SIDEY_GODOT_EXECUTABLE=${SIDEY_GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}

if [ ! -x "$SIDEY_GODOT_EXECUTABLE" ]; then
	echo "Godot executable not found: $SIDEY_GODOT_EXECUTABLE" >&2
	exit 1
fi

mkdir -p "$SIDEY_API_DIR"
(
	cd "$SIDEY_API_DIR"
	"$SIDEY_GODOT_EXECUTABLE" --headless --log-file "$SIDEY_API_DIR/api-dump.log" --dump-extension-api
)

scons -C "$SIDEY_NATIVE_DIR" \
	platform=macos \
	arch=arm64 \
	target="$SIDEY_BUILD_TARGET" \
	custom_api_file="$SIDEY_API_FILE" \
	-j4
