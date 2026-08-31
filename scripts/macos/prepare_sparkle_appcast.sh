#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_RELEASE_TAG=${1:-}
SIDEY_ARCHIVE_PATH=${2:-}
SIDEY_SPARKLE_ACCOUNT=${SIDEY_SPARKLE_ACCOUNT:-sidey-app}
SIDEY_APPCAST_OUTPUT=${SIDEY_APPCAST_OUTPUT:-$SIDEY_REPO_ROOT/updates/appcast.xml}
SIDEY_ALLOW_AD_HOC=${SIDEY_ALLOW_AD_HOC_SPARKLE:-0}
SIDEY_EXPECTED_FEED_URL=https://raw.githubusercontent.com/sidey-app/SIDEY/main/updates/appcast.xml
SIDEY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-appcast.XXXXXX")

cleanup() {
	rm -rf "$SIDEY_TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

if ! printf '%s\n' "$SIDEY_RELEASE_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'; then
	echo "Usage: $0 vMAJOR.MINOR.PATCH[-PRERELEASE] /path/to/SIDEY.zip" >&2
	exit 64
fi
if [ -z "$SIDEY_ARCHIVE_PATH" ] || [ ! -f "$SIDEY_ARCHIVE_PATH" ]; then
	echo "Release ZIP not found: $SIDEY_ARCHIVE_PATH" >&2
	exit 66
fi

SIDEY_SPARKLE_BIN_DIR=$(
	find "$SIDEY_REPO_ROOT/build/native-derived/SourcePackages/artifacts" \
		-type f -name generate_appcast -perm -111 -print -quit 2>/dev/null \
		| sed 's|/generate_appcast$||'
)
if [ -z "$SIDEY_SPARKLE_BIN_DIR" ] || [ ! -x "$SIDEY_SPARKLE_BIN_DIR/generate_keys" ]; then
	echo "Sparkle tools are missing. Resolve packages or run ./scripts/export_macos.sh first." >&2
	exit 69
fi

SIDEY_EXTRACTED_DIR="$SIDEY_TEMP_DIR/extracted"
mkdir -p "$SIDEY_EXTRACTED_DIR"
ditto -x -k "$SIDEY_ARCHIVE_PATH" "$SIDEY_EXTRACTED_DIR"
SIDEY_APP_PATH=$(find "$SIDEY_EXTRACTED_DIR" -maxdepth 2 -type d -name SIDEY.app -print -quit)
if [ -z "$SIDEY_APP_PATH" ]; then
	echo "SIDEY.app is missing from the release ZIP" >&2
	exit 65
fi

SIDEY_INFO_PLIST="$SIDEY_APP_PATH/Contents/Info.plist"
SIDEY_PUBLIC_KEY=$(
	"$SIDEY_SPARKLE_BIN_DIR/generate_keys" --account "$SIDEY_SPARKLE_ACCOUNT" -p \
		| sed -n '/[^[:space:]]/p' \
		| tail -n 1
)
SIDEY_BUNDLED_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$SIDEY_INFO_PLIST")
SIDEY_BUNDLED_FEED_URL=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$SIDEY_INFO_PLIST")
SIDEY_REQUIRES_SIGNED_FEED=$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$SIDEY_INFO_PLIST")
SIDEY_VERIFIES_BEFORE_EXTRACTION=$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$SIDEY_INFO_PLIST")

if [ "$SIDEY_PUBLIC_KEY" != "$SIDEY_BUNDLED_PUBLIC_KEY" ]; then
	echo "The release bundle public key does not match the '$SIDEY_SPARKLE_ACCOUNT' Keychain key" >&2
	exit 65
fi
if [ "$SIDEY_BUNDLED_FEED_URL" != "$SIDEY_EXPECTED_FEED_URL" ]; then
	echo "Unexpected Sparkle feed URL: $SIDEY_BUNDLED_FEED_URL" >&2
	exit 65
fi
if [ "$SIDEY_REQUIRES_SIGNED_FEED" != true ] || [ "$SIDEY_VERIFIES_BEFORE_EXTRACTION" != true ]; then
	echo "The release bundle must require signed feeds and pre-extraction verification" >&2
	exit 65
fi

codesign --verify --deep --strict "$SIDEY_APP_PATH"
SIDEY_SIGNATURE_INFO=$(codesign -dv --verbose=4 "$SIDEY_APP_PATH" 2>&1)
SIDEY_TEAM_ID=$(printf '%s\n' "$SIDEY_SIGNATURE_INFO" | sed -n 's/^TeamIdentifier=//p')
if [ -z "$SIDEY_TEAM_ID" ] || [ "$SIDEY_TEAM_ID" = "not set" ]; then
	if [ "$SIDEY_ALLOW_AD_HOC" != 1 ]; then
		echo "Refusing to publish an ad-hoc signed update. Use a notarized Developer ID build." >&2
		echo "For an isolated local pipeline test only, set SIDEY_ALLOW_AD_HOC_SPARKLE=1." >&2
		exit 65
	fi
	echo "WARNING: generating a local-only appcast from an ad-hoc signed build" >&2
else
	printf '%s\n' "$SIDEY_SIGNATURE_INFO" | grep -Eq '^flags=.*runtime' || {
		echo "Developer ID release is missing Hardened Runtime" >&2
		exit 65
	}
	xcrun stapler validate "$SIDEY_APP_PATH"
	spctl --assess --type execute --verbose=2 "$SIDEY_APP_PATH"
fi

SIDEY_ARCHIVE_NAME=$(basename -- "$SIDEY_ARCHIVE_PATH")
SIDEY_ARCHIVE_STEM=${SIDEY_ARCHIVE_NAME%.zip}
SIDEY_APPCAST_WORK_DIR="$SIDEY_TEMP_DIR/appcast"
mkdir -p "$SIDEY_APPCAST_WORK_DIR"
cp "$SIDEY_ARCHIVE_PATH" "$SIDEY_APPCAST_WORK_DIR/$SIDEY_ARCHIVE_NAME"
if [ -f "$SIDEY_APPCAST_OUTPUT" ]; then
	cp "$SIDEY_APPCAST_OUTPUT" "$SIDEY_APPCAST_WORK_DIR/appcast.xml"
fi
if [ -n "${SIDEY_RELEASE_NOTES:-}" ]; then
	[ -f "$SIDEY_RELEASE_NOTES" ] || {
		echo "Release notes file not found: $SIDEY_RELEASE_NOTES" >&2
		exit 66
	}
	cp "$SIDEY_RELEASE_NOTES" "$SIDEY_APPCAST_WORK_DIR/$SIDEY_ARCHIVE_STEM.md"
fi

"$SIDEY_SPARKLE_BIN_DIR/generate_appcast" \
	--account "$SIDEY_SPARKLE_ACCOUNT" \
	--download-url-prefix "https://github.com/sidey-app/SIDEY/releases/download/$SIDEY_RELEASE_TAG/" \
	--link "https://github.com/sidey-app/SIDEY/releases/tag/$SIDEY_RELEASE_TAG" \
	--maximum-versions 5 \
	--maximum-deltas 0 \
	--embed-release-notes \
	-o "$SIDEY_APPCAST_WORK_DIR/appcast.xml" \
	"$SIDEY_APPCAST_WORK_DIR"

xmllint --noout "$SIDEY_APPCAST_WORK_DIR/appcast.xml"
grep -F '<!-- sparkle-signatures:' "$SIDEY_APPCAST_WORK_DIR/appcast.xml" >/dev/null
grep -F "https://github.com/sidey-app/SIDEY/releases/download/$SIDEY_RELEASE_TAG/$SIDEY_ARCHIVE_NAME" \
	"$SIDEY_APPCAST_WORK_DIR/appcast.xml" >/dev/null

mkdir -p "$(dirname -- "$SIDEY_APPCAST_OUTPUT")"
cp "$SIDEY_APPCAST_WORK_DIR/appcast.xml" "$SIDEY_APPCAST_OUTPUT"

echo "Prepared signed Sparkle appcast: $SIDEY_APPCAST_OUTPUT"
echo "Upload this exact archive before publishing the appcast: $SIDEY_ARCHIVE_NAME"
