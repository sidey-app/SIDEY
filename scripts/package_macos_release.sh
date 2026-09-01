#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
SIDEY_RELEASE_TAG=${1:-}
SIDEY_CODE_SIGN_IDENTITY=${SIDEY_CODE_SIGN_IDENTITY:--}
SIDEY_HARDENED_RUNTIME=${SIDEY_HARDENED_RUNTIME:-NO}
SIDEY_NOTARYTOOL_PROFILE=${SIDEY_NOTARYTOOL_PROFILE:-}

if ! printf '%s\n' "$SIDEY_RELEASE_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'; then
	echo "Usage: $0 vMAJOR.MINOR.PATCH[-PRERELEASE]" >&2
	exit 64
fi

SIDEY_BASE_VERSION=$(printf '%s\n' "$SIDEY_RELEASE_TAG" | sed -E 's/^v//; s/-.*$//')
SIDEY_PROJECT_FILE="$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj/project.pbxproj"
SIDEY_CONFIGURED_VERSION=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);$/\1/p' "$SIDEY_PROJECT_FILE" | sort -u)
SIDEY_BUILD_NUMBER=$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);$/\1/p' "$SIDEY_PROJECT_FILE" | sort -u)

if [ "$SIDEY_BASE_VERSION" != "$SIDEY_CONFIGURED_VERSION" ]; then
	echo "Release tag base version $SIDEY_BASE_VERSION does not match app version $SIDEY_CONFIGURED_VERSION" >&2
	exit 65
fi
if ! printf '%s\n' "$SIDEY_BUILD_NUMBER" | grep -Eq '^[0-9]+$'; then
	echo "Xcode project must contain one numeric build number" >&2
	exit 65
fi

SIDEY_RELEASE_DIR="$SIDEY_REPO_ROOT/build/releases/$SIDEY_RELEASE_TAG"
SIDEY_ARCHIVE_NAME="SIDEY-macOS-arm64-$SIDEY_RELEASE_TAG.zip"
SIDEY_CHECKSUM_NAME="$SIDEY_ARCHIVE_NAME.sha256"
SIDEY_DMG_NAME="SIDEY-macOS-arm64-$SIDEY_RELEASE_TAG.dmg"
SIDEY_DMG_CHECKSUM_NAME="$SIDEY_DMG_NAME.sha256"
SIDEY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-package.XXXXXX")
trap 'rm -rf "$SIDEY_TEMP_DIR"' EXIT HUP INT TERM

SIDEY_TEMP_EXPORT="$SIDEY_TEMP_DIR/export"
SIDEY_TEMP_ZIP="$SIDEY_TEMP_DIR/$SIDEY_ARCHIVE_NAME"
SIDEY_TEMP_DMG="$SIDEY_TEMP_DIR/$SIDEY_DMG_NAME"
"$SIDEY_REPO_ROOT/scripts/export_macos.sh" "$SIDEY_TEMP_EXPORT" "$SIDEY_TEMP_ZIP"

SIDEY_APP_PATH="$SIDEY_TEMP_EXPORT/SIDEY.app"
SIDEY_INFO_PLIST="$SIDEY_APP_PATH/Contents/Info.plist"
SIDEY_MAIN_EXECUTABLE="$SIDEY_APP_PATH/Contents/MacOS/SIDEY"
SIDEY_ICON="$SIDEY_APP_PATH/Contents/Resources/AppIcon.icns"

[ -x "$SIDEY_MAIN_EXECUTABLE" ] || {
	echo "Exported SIDEY executable is missing or not executable" >&2
	exit 66
}
[ -s "$SIDEY_ICON" ] || {
	echo "Exported SIDEY icon is missing" >&2
	exit 66
}
lipo "$SIDEY_MAIN_EXECUTABLE" -verify_arch arm64
codesign --verify --deep --strict "$SIDEY_APP_PATH"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SIDEY_INFO_PLIST")" != "$SIDEY_BASE_VERSION" ]; then
	echo "Exported bundle version does not match release tag" >&2
	exit 66
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SIDEY_INFO_PLIST")" != "$SIDEY_BUILD_NUMBER" ]; then
	echo "Exported bundle build number does not match Xcode project" >&2
	exit 66
fi
unzip -t "$SIDEY_TEMP_ZIP" >/dev/null

SIDEY_HAS_DMG=0
if [ -n "$SIDEY_NOTARYTOOL_PROFILE" ]; then
	if [ "$SIDEY_CODE_SIGN_IDENTITY" = "-" ] || [ "$SIDEY_HARDENED_RUNTIME" != "YES" ]; then
		echo "Release DMG requires Developer ID signing and SIDEY_HARDENED_RUNTIME=YES" >&2
		exit 64
	fi
	"$SIDEY_REPO_ROOT/scripts/macos/create_release_dmg.sh" \
		"$SIDEY_APP_PATH" \
		"$SIDEY_TEMP_DMG"
	SIDEY_HAS_DMG=1
fi

mkdir -p "$SIDEY_RELEASE_DIR"
mv -f "$SIDEY_TEMP_ZIP" "$SIDEY_RELEASE_DIR/$SIDEY_ARCHIVE_NAME"
mv -f "$SIDEY_TEMP_ZIP.sha256" "$SIDEY_RELEASE_DIR/$SIDEY_CHECKSUM_NAME"
if [ "$SIDEY_HAS_DMG" = 1 ]; then
	mv -f "$SIDEY_TEMP_DMG" "$SIDEY_RELEASE_DIR/$SIDEY_DMG_NAME"
	mv -f "$SIDEY_TEMP_DMG.sha256" "$SIDEY_RELEASE_DIR/$SIDEY_DMG_CHECKSUM_NAME"
fi

echo "Created native macOS release artifacts:"
echo "  $SIDEY_RELEASE_DIR/$SIDEY_ARCHIVE_NAME"
echo "  $SIDEY_RELEASE_DIR/$SIDEY_CHECKSUM_NAME"
if [ "$SIDEY_HAS_DMG" = 1 ]; then
	echo "  $SIDEY_RELEASE_DIR/$SIDEY_DMG_NAME"
	echo "  $SIDEY_RELEASE_DIR/$SIDEY_DMG_CHECKSUM_NAME"
fi
echo "  version $SIDEY_BASE_VERSION, build $SIDEY_BUILD_NUMBER, arm64"
