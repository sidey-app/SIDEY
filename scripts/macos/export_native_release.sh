#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_DERIVED_DATA=${SIDEY_DERIVED_DATA:-$SIDEY_REPO_ROOT/build/native-derived}
SIDEY_EXPORT_DIR=${1:-$SIDEY_REPO_ROOT/build/macos-native}
SIDEY_ZIP_PATH=${2:-$SIDEY_EXPORT_DIR/SIDEY-macOS-arm64.zip}
SIDEY_PRODUCT_APP="$SIDEY_DERIVED_DATA/Build/Products/Release/SIDEY.app"
SIDEY_STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-native-export.XXXXXX")

cleanup() {
	rm -rf "$SIDEY_STAGE_DIR"
}
trap cleanup EXIT HUP INT TERM

python3 "$SIDEY_REPO_ROOT/scripts/macos/verify_character_asset_lineage.py"

xcodebuild \
	-project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
	-scheme SIDEY \
	-configuration Release \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "$SIDEY_DERIVED_DATA" \
	-disableAutomaticPackageResolution \
	ARCHS=arm64 \
	ONLY_ACTIVE_ARCH=YES \
	build

if [ ! -d "$SIDEY_PRODUCT_APP" ]; then
	echo "Native SIDEY product not found: $SIDEY_PRODUCT_APP" >&2
	exit 1
fi

SIDEY_STAGED_APP="$SIDEY_STAGE_DIR/SIDEY.app"
ditto "$SIDEY_PRODUCT_APP" "$SIDEY_STAGED_APP"

SIDEY_MAIN_EXECUTABLE="$SIDEY_STAGED_APP/Contents/MacOS/SIDEY"
SIDEY_INFO_PLIST="$SIDEY_STAGED_APP/Contents/Info.plist"
SIDEY_LOGIN_APP="$SIDEY_STAGED_APP/Contents/Library/LoginItems/SIDEYLoginItem.app"
SIDEY_LOGIN_EXECUTABLE="$SIDEY_LOGIN_APP/Contents/MacOS/SIDEYLoginItem"
SIDEY_LOGIN_INFO_PLIST="$SIDEY_LOGIN_APP/Contents/Info.plist"

for SIDEY_REQUIRED_PATH in \
	"$SIDEY_MAIN_EXECUTABLE" \
	"$SIDEY_INFO_PLIST" \
	"$SIDEY_LOGIN_EXECUTABLE" \
	"$SIDEY_LOGIN_INFO_PLIST"; do
	if [ ! -e "$SIDEY_REQUIRED_PATH" ]; then
		echo "Required release file missing: $SIDEY_REQUIRED_PATH" >&2
		exit 1
	fi
done

if [ "$(lipo -archs "$SIDEY_MAIN_EXECUTABLE")" != "arm64" ]; then
	echo "SIDEY must contain only the arm64 architecture" >&2
	exit 1
fi
if [ "$(lipo -archs "$SIDEY_LOGIN_EXECUTABLE")" != "arm64" ]; then
	echo "SIDEYLoginItem must contain only the arm64 architecture" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_INFO_PLIST")" != "app.sidey.desktop" ]; then
	echo "Unexpected SIDEY bundle identifier" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$SIDEY_INFO_PLIST")" != "26.0" ]; then
	echo "SIDEY must require macOS 26.0" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$SIDEY_INFO_PLIST")" != "true" ]; then
	echo "SIDEY must run as an agent/menu bar application" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_LOGIN_INFO_PLIST")" != "app.sidey.desktop.login-item" ]; then
	echo "Unexpected login item bundle identifier" >&2
	exit 1
fi

codesign --verify --deep --strict "$SIDEY_STAGED_APP"

mkdir -p "$SIDEY_EXPORT_DIR"
SIDEY_EXPORT_APP="$SIDEY_EXPORT_DIR/SIDEY.app"
if [ -e "$SIDEY_EXPORT_APP" ]; then
	mv "$SIDEY_EXPORT_APP" "$SIDEY_STAGE_DIR/previous-SIDEY.app"
fi
mv "$SIDEY_STAGED_APP" "$SIDEY_EXPORT_APP"

SIDEY_STAGED_ZIP="$SIDEY_STAGE_DIR/$(basename -- "$SIDEY_ZIP_PATH")"
ditto -c -k --sequesterRsrc --keepParent "$SIDEY_EXPORT_APP" "$SIDEY_STAGED_ZIP"
mkdir -p "$(dirname -- "$SIDEY_ZIP_PATH")"
if [ -e "$SIDEY_ZIP_PATH" ]; then
	mv "$SIDEY_ZIP_PATH" "$SIDEY_STAGE_DIR/previous-SIDEY.zip"
fi
mv "$SIDEY_STAGED_ZIP" "$SIDEY_ZIP_PATH"

SIDEY_SHA_PATH="$SIDEY_ZIP_PATH.sha256"
SIDEY_SHA_TEMP="$SIDEY_STAGE_DIR/$(basename -- "$SIDEY_SHA_PATH")"
(
	cd "$(dirname -- "$SIDEY_ZIP_PATH")"
	shasum -a 256 "$(basename -- "$SIDEY_ZIP_PATH")"
) > "$SIDEY_SHA_TEMP"
if [ -e "$SIDEY_SHA_PATH" ]; then
	mv "$SIDEY_SHA_PATH" "$SIDEY_STAGE_DIR/previous-SIDEY.sha256"
fi
mv "$SIDEY_SHA_TEMP" "$SIDEY_SHA_PATH"

echo "Verified native arm64 macOS release: $SIDEY_EXPORT_APP"
echo "Release ZIP: $SIDEY_ZIP_PATH"
echo "SHA-256: $SIDEY_SHA_PATH"
