#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && /bin/pwd -P)
python3 "$SIDEY_REPO_ROOT/scripts/macos/verify_content_assets.py"
SIDEY_CREATED_TEST_DIR=false

python3 -m unittest discover -s "$SIDEY_REPO_ROOT/scripts/macos/tests"

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
	SIDEY_RUN_BACKEND_INTEGRATION="${SIDEY_RUN_BACKEND_INTEGRATION:-0}" \
	SIDEY_API_BASE_URL="${SIDEY_API_BASE_URL:-}" \
	SIDEY_INTEGRATION_SESSION_ONE_FILE="${SIDEY_INTEGRATION_SESSION_ONE_FILE:-}" \
	SIDEY_INTEGRATION_SESSION_TWO_FILE="${SIDEY_INTEGRATION_SESSION_TWO_FILE:-}" \
	test \
	"$@"

# Each distribution owns separate products even though both executable names are SIDEY.
xcodebuild \
    -project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
    -scheme SIDEYAppStore \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$SIDEY_TEST_DIR/app-store" \
    -disableAutomaticPackageResolution \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= \
    test \
    "$@"

"$SIDEY_REPO_ROOT/scripts/macos/tests/test_recording.sh"
