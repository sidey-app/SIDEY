#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
SIDEY_RELEASE_TAG=${1:-}

if ! printf '%s\n' "$SIDEY_RELEASE_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'; then
	echo "Usage: $0 vMAJOR.MINOR.PATCH[-PRERELEASE]" >&2
	exit 64
fi

SIDEY_BASE_VERSION=$(printf '%s\n' "$SIDEY_RELEASE_TAG" | sed -E 's/^v//; s/-.*$//')
SIDEY_CONFIGURED_VERSION=$(sed -n 's/^application\/short_version="\([^"]*\)"$/\1/p' "$SIDEY_REPO_ROOT/export_presets.cfg")
if [ "$SIDEY_BASE_VERSION" != "$SIDEY_CONFIGURED_VERSION" ]; then
	echo "Release tag base version $SIDEY_BASE_VERSION does not match app version $SIDEY_CONFIGURED_VERSION" >&2
	exit 65
fi

SIDEY_APP_PATH="$SIDEY_REPO_ROOT/build/macos/SIDEY.app"
SIDEY_RELEASE_DIR="$SIDEY_REPO_ROOT/build/releases/$SIDEY_RELEASE_TAG"
SIDEY_ARCHIVE_NAME="SIDEY-macOS-universal-$SIDEY_RELEASE_TAG.zip"
SIDEY_CHECKSUM_NAME="SIDEY-macOS-universal-$SIDEY_RELEASE_TAG.sha256"
SIDEY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-package.XXXXXX")
trap 'rm -rf "$SIDEY_TEMP_DIR"' EXIT HUP INT TERM

"$SIDEY_REPO_ROOT/scripts/export_macos.sh" "$SIDEY_APP_PATH"

SIDEY_INFO_PLIST="$SIDEY_APP_PATH/Contents/Info.plist"
SIDEY_MAIN_EXECUTABLE="$SIDEY_APP_PATH/Contents/MacOS/SIDEY"
SIDEY_ICON="$SIDEY_APP_PATH/Contents/Resources/icon.icns"

[ -x "$SIDEY_MAIN_EXECUTABLE" ] || {
	echo "Exported SIDEY executable is missing or not executable" >&2
	exit 66
}
[ -s "$SIDEY_ICON" ] || {
	echo "Exported SIDEY icon is missing" >&2
	exit 66
}
lipo "$SIDEY_MAIN_EXECUTABLE" -verify_arch arm64 x86_64
codesign --verify --deep --strict "$SIDEY_APP_PATH"
if ! codesign -dv --verbose=4 "$SIDEY_APP_PATH" 2>&1 | grep -q 'Signature=adhoc'; then
	echo "Expected an ad-hoc signed alpha build" >&2
	exit 66
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SIDEY_INFO_PLIST")" != "$SIDEY_BASE_VERSION" ]; then
	echo "Exported bundle version does not match release tag" >&2
	exit 66
fi

ditto -c -k --sequesterRsrc --keepParent "$SIDEY_APP_PATH" "$SIDEY_TEMP_DIR/$SIDEY_ARCHIVE_NAME"
unzip -t "$SIDEY_TEMP_DIR/$SIDEY_ARCHIVE_NAME" >/dev/null
mkdir -p "$SIDEY_TEMP_DIR/extracted"
ditto -x -k "$SIDEY_TEMP_DIR/$SIDEY_ARCHIVE_NAME" "$SIDEY_TEMP_DIR/extracted"
codesign --verify --deep --strict "$SIDEY_TEMP_DIR/extracted/SIDEY.app"
lipo "$SIDEY_TEMP_DIR/extracted/SIDEY.app/Contents/MacOS/SIDEY" -verify_arch arm64 x86_64

mkdir -p "$SIDEY_RELEASE_DIR"
mv -f "$SIDEY_TEMP_DIR/$SIDEY_ARCHIVE_NAME" "$SIDEY_RELEASE_DIR/$SIDEY_ARCHIVE_NAME"
(
	cd "$SIDEY_RELEASE_DIR"
	shasum -a 256 "$SIDEY_ARCHIVE_NAME" >"$SIDEY_CHECKSUM_NAME"
)

echo "Created macOS alpha release artifacts:"
echo "  $SIDEY_RELEASE_DIR/$SIDEY_ARCHIVE_NAME"
echo "  $SIDEY_RELEASE_DIR/$SIDEY_CHECKSUM_NAME"
