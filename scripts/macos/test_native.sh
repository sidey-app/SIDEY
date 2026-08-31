#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_CREATED_TEST_DIR=false

if [ -n "${SIDEY_TEST_DERIVED_DATA:-}" ]; then
	SIDEY_TEST_DIR=$SIDEY_TEST_DERIVED_DATA
else
	SIDEY_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-native-tests.XXXXXX")
	SIDEY_CREATED_TEST_DIR=true
fi

cleanup() {
	if [ "$SIDEY_CREATED_TEST_DIR" = true ]; then
		rm -rf "$SIDEY_TEST_DIR"
	fi
}
trap cleanup EXIT HUP INT TERM

SIDEY_DMG_BACKGROUND="$SIDEY_TEST_DIR/dmg-background.png"
xcrun swift \
	"$SIDEY_REPO_ROOT/scripts/macos/generate_dmg_background.swift" \
	"$SIDEY_REPO_ROOT" \
	"$SIDEY_DMG_BACKGROUND"
SIDEY_DMG_BACKGROUND_INFO=$(sips -g pixelWidth -g pixelHeight "$SIDEY_DMG_BACKGROUND")
printf '%s\n' "$SIDEY_DMG_BACKGROUND_INFO" | grep -Eq 'pixelWidth: 660$'
printf '%s\n' "$SIDEY_DMG_BACKGROUND_INFO" | grep -Eq 'pixelHeight: 420$'

xcodebuild \
	-project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
	-scheme SIDEY \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "$SIDEY_TEST_DIR" \
	-disableAutomaticPackageResolution \
	test \
	"$@"
