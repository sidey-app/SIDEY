#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_APP_STORE_VERIFIER_URL=${SIDEY_APP_STORE_VERIFIER_URL:-}
SIDEY_DEVELOPMENT_TEAM=${SIDEY_DEVELOPMENT_TEAM:-}
SIDEY_ARCHIVE_PATH=${1:-$SIDEY_REPO_ROOT/build/app-store/SIDEYAppStore.xcarchive}
SIDEY_DERIVED_DATA=${SIDEY_DERIVED_DATA:-$SIDEY_REPO_ROOT/build/app-store-derived}

if [ -z "$SIDEY_APP_STORE_VERIFIER_URL" ]; then
	echo "SIDEY_APP_STORE_VERIFIER_URL is required" >&2
	exit 64
fi
case "$SIDEY_APP_STORE_VERIFIER_URL" in
	https://*) ;;
	*)
		echo "SIDEY_APP_STORE_VERIFIER_URL must use HTTPS" >&2
		exit 64
		;;
esac
case "$SIDEY_APP_STORE_VERIFIER_URL" in
	*"@"*|*"?"*|*"#"*)
		echo "SIDEY_APP_STORE_VERIFIER_URL must not contain credentials, a query, or a fragment" >&2
		exit 64
		;;
esac
if [ -z "$SIDEY_DEVELOPMENT_TEAM" ]; then
	echo "SIDEY_DEVELOPMENT_TEAM is required for App Store signing" >&2
	exit 64
fi

python3 "$SIDEY_REPO_ROOT/scripts/validate_pixel_assets.py"
mkdir -p "$(dirname -- "$SIDEY_ARCHIVE_PATH")" "$SIDEY_DERIVED_DATA"

xcodebuild \
	-project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
	-scheme SIDEYAppStore \
	-configuration Release \
	-destination 'generic/platform=macOS' \
	-derivedDataPath "$SIDEY_DERIVED_DATA" \
	-archivePath "$SIDEY_ARCHIVE_PATH" \
	-disableAutomaticPackageResolution \
	-allowProvisioningUpdates \
	"DEVELOPMENT_TEAM=$SIDEY_DEVELOPMENT_TEAM" \
	"SIDEY_APP_STORE_VERIFIER_URL=$SIDEY_APP_STORE_VERIFIER_URL" \
	archive

SIDEY_APP="$SIDEY_ARCHIVE_PATH/Products/Applications/SIDEYAppStore.app"
SIDEY_EXECUTABLE="$SIDEY_APP/Contents/MacOS/SIDEYAppStore"
SIDEY_INFO_PLIST="$SIDEY_APP/Contents/Info.plist"
SIDEY_PRIVACY_MANIFEST="$SIDEY_APP/Contents/Resources/PrivacyInfo.xcprivacy"

for SIDEY_REQUIRED_PATH in \
	"$SIDEY_EXECUTABLE" \
	"$SIDEY_INFO_PLIST" \
	"$SIDEY_PRIVACY_MANIFEST"; do
	if [ ! -e "$SIDEY_REQUIRED_PATH" ]; then
		echo "Required App Store archive file missing: $SIDEY_REQUIRED_PATH" >&2
		exit 1
	fi
done

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_INFO_PLIST")" != "app.sidey.desktop.appstore" ]; then
	echo "Unexpected App Store bundle identifier" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYReleaseChannel' "$SIDEY_INFO_PLIST")" != "app-store" ]; then
	echo "App Store archive must use the app-store release channel" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYAppStoreVerifierURL' "$SIDEY_INFO_PLIST")" != "$SIDEY_APP_STORE_VERIFIER_URL" ]; then
	echo "App Store verifier URL was not embedded correctly" >&2
	exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$SIDEY_INFO_PLIST" >/dev/null 2>&1; then
	echo "App Store archive must not declare the direct-distribution OAuth URL scheme" >&2
	exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$SIDEY_INFO_PLIST" >/dev/null 2>&1; then
	echo "App Store archive must not include Sparkle configuration" >&2
	exit 1
fi
if [ -e "$SIDEY_APP/Contents/Frameworks/Sparkle.framework" ]; then
	echo "App Store archive must not bundle Sparkle" >&2
	exit 1
fi
if [ -e "$SIDEY_APP/Contents/Library/LoginItems" ]; then
	echo "App Store archive must not bundle the direct-distribution login helper" >&2
	exit 1
fi

codesign --verify --deep --strict "$SIDEY_APP"
if otool -L "$SIDEY_EXECUTABLE" | grep -F 'Sparkle.framework' >/dev/null; then
	echo "App Store executable must not link Sparkle" >&2
	exit 1
fi

echo "Verified Mac App Store archive: $SIDEY_ARCHIVE_PATH"
