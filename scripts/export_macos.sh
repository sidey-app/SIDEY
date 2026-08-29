#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
SIDEY_GODOT_EXECUTABLE=${SIDEY_GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}
SIDEY_EXPORT_PATH=${1:-$SIDEY_REPO_ROOT/build/macos/SIDEY.app}
SIDEY_EXPORT_DIR=$(dirname -- "$SIDEY_EXPORT_PATH")

if [ ! -x "$SIDEY_GODOT_EXECUTABLE" ]; then
	echo "Godot executable not found: $SIDEY_GODOT_EXECUTABLE" >&2
	exit 1
fi

for SIDEY_ARCH in arm64 x86_64; do
	"$SIDEY_REPO_ROOT/scripts/build_macos_bridge.sh" template_release "$SIDEY_ARCH"
done

mkdir -p "$SIDEY_EXPORT_DIR"
"$SIDEY_GODOT_EXECUTABLE" --headless --path "$SIDEY_REPO_ROOT" --import
"$SIDEY_GODOT_EXECUTABLE" --headless --path "$SIDEY_REPO_ROOT" \
	--export-release macOS "$SIDEY_EXPORT_PATH"

SIDEY_MAIN_EXECUTABLE="$SIDEY_EXPORT_PATH/Contents/MacOS/SIDEY"
SIDEY_INFO_PLIST="$SIDEY_EXPORT_PATH/Contents/Info.plist"
SIDEY_ARM_LIBRARY="$SIDEY_EXPORT_PATH/Contents/Frameworks/libsidey_macos.macos.template_release.arm64.dylib"
SIDEY_X86_LIBRARY="$SIDEY_EXPORT_PATH/Contents/Frameworks/libsidey_macos.macos.template_release.x86_64.dylib"
if [ ! -x "$SIDEY_MAIN_EXECUTABLE" ]; then
	echo "Exported executable not found: $SIDEY_MAIN_EXECUTABLE" >&2
	exit 1
fi

lipo "$SIDEY_MAIN_EXECUTABLE" -verify_arch arm64 x86_64
for SIDEY_LIBRARY_SPEC in "arm64:$SIDEY_ARM_LIBRARY" "x86_64:$SIDEY_X86_LIBRARY"; do
	SIDEY_LIBRARY_ARCH=${SIDEY_LIBRARY_SPEC%%:*}
	SIDEY_LIBRARY_PATH=${SIDEY_LIBRARY_SPEC#*:}
	if [ ! -f "$SIDEY_LIBRARY_PATH" ]; then
		echo "Exported native library not found: $SIDEY_LIBRARY_PATH" >&2
		exit 1
	fi
	lipo "$SIDEY_LIBRARY_PATH" -verify_arch "$SIDEY_LIBRARY_ARCH"
done

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_INFO_PLIST")" != "app.sidey.desktop" ]; then
	echo "Unexpected bundle identifier" >&2
	exit 1
fi
for SIDEY_ARCH in arm64 x86_64; do
	if [ "$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersionByArchitecture:$SIDEY_ARCH" "$SIDEY_INFO_PLIST")" != "13.0" ]; then
		echo "Unexpected minimum macOS version for $SIDEY_ARCH" >&2
		exit 1
	fi
done
if [ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$SIDEY_INFO_PLIST")" != "true" ]; then
	echo "SIDEY must export as a menu bar application" >&2
	exit 1
fi

codesign --verify --deep --strict "$SIDEY_EXPORT_PATH"

echo "Verified universal ad-hoc macOS export: $SIDEY_EXPORT_PATH"
