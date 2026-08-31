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

xcodebuild \
	-project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
	-scheme SIDEY \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "$SIDEY_TEST_DIR" \
	-disableAutomaticPackageResolution \
	test \
	"$@"
