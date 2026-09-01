#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_DERIVED_DATA=${SIDEY_DERIVED_DATA:-$SIDEY_REPO_ROOT/build/native-derived}
SIDEY_EXPORT_DIR=${1:-$SIDEY_REPO_ROOT/build/macos-native}
SIDEY_ZIP_PATH=${2:-$SIDEY_EXPORT_DIR/SIDEY-macOS-arm64.zip}
SIDEY_PRODUCT_APP="$SIDEY_DERIVED_DATA/Build/Products/Release/SIDEY.app"
SIDEY_CODE_SIGN_IDENTITY=${SIDEY_CODE_SIGN_IDENTITY:--}
SIDEY_DEVELOPMENT_TEAM=${SIDEY_DEVELOPMENT_TEAM:-}
SIDEY_HARDENED_RUNTIME=${SIDEY_HARDENED_RUNTIME:-NO}
SIDEY_NOTARYTOOL_PROFILE=${SIDEY_NOTARYTOOL_PROFILE:-}
SIDEY_STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-native-export.XXXXXX")

cleanup() {
	rm -rf "$SIDEY_STAGE_DIR"
}
trap cleanup EXIT HUP INT TERM

"$SIDEY_REPO_ROOT/scripts/macos/verify_pixel_hamster.sh"

set -- xcodebuild \
	-project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
	-scheme SIDEY \
	-configuration Release \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "$SIDEY_DERIVED_DATA" \
	-disableAutomaticPackageResolution \
	ARCHS=arm64 \
	ONLY_ACTIVE_ARCH=YES \
	"CODE_SIGN_IDENTITY=$SIDEY_CODE_SIGN_IDENTITY" \
	"ENABLE_HARDENED_RUNTIME=$SIDEY_HARDENED_RUNTIME" \
	SIDEY_DISPLAY_NAME=SIDEY \
	SIDEY_RELEASE_CHANNEL=production
if [ "$SIDEY_CODE_SIGN_IDENTITY" != "-" ]; then
	if [ -z "$SIDEY_DEVELOPMENT_TEAM" ]; then
		echo "SIDEY_DEVELOPMENT_TEAM is required for Developer ID signing" >&2
		exit 64
	fi
	set -- "$@" \
		CODE_SIGN_STYLE=Manual \
		"DEVELOPMENT_TEAM=$SIDEY_DEVELOPMENT_TEAM" \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		OTHER_CODE_SIGN_FLAGS=--timestamp
fi
set -- "$@" build
"$@"

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
SIDEY_SPARKLE_FRAMEWORK="$SIDEY_STAGED_APP/Contents/Frameworks/Sparkle.framework"
SIDEY_SPARKLE_VERSION_ROOT="$SIDEY_SPARKLE_FRAMEWORK/Versions/B"

for SIDEY_REQUIRED_PATH in \
	"$SIDEY_MAIN_EXECUTABLE" \
	"$SIDEY_INFO_PLIST" \
	"$SIDEY_LOGIN_EXECUTABLE" \
	"$SIDEY_LOGIN_INFO_PLIST" \
	"$SIDEY_SPARKLE_FRAMEWORK"; do
	if [ ! -e "$SIDEY_REQUIRED_PATH" ]; then
		echo "Required release file missing: $SIDEY_REQUIRED_PATH" >&2
		exit 1
	fi
done

if [ "$SIDEY_CODE_SIGN_IDENTITY" != "-" ]; then
	codesign \
		--force \
		--sign "$SIDEY_CODE_SIGN_IDENTITY" \
		--options runtime \
		--timestamp \
		"$SIDEY_SPARKLE_VERSION_ROOT/XPCServices/Installer.xpc"
	codesign \
		--force \
		--sign "$SIDEY_CODE_SIGN_IDENTITY" \
		--options runtime \
		--timestamp \
		--preserve-metadata=entitlements \
		"$SIDEY_SPARKLE_VERSION_ROOT/XPCServices/Downloader.xpc"
	codesign \
		--force \
		--sign "$SIDEY_CODE_SIGN_IDENTITY" \
		--options runtime \
		--timestamp \
		"$SIDEY_SPARKLE_VERSION_ROOT/Autoupdate"
	codesign \
		--force \
		--sign "$SIDEY_CODE_SIGN_IDENTITY" \
		--options runtime \
		--timestamp \
		"$SIDEY_SPARKLE_VERSION_ROOT/Updater.app"
	codesign \
		--force \
		--sign "$SIDEY_CODE_SIGN_IDENTITY" \
		--options runtime \
		--timestamp \
		"$SIDEY_SPARKLE_FRAMEWORK"
	codesign \
		--force \
		--sign "$SIDEY_CODE_SIGN_IDENTITY" \
		--options runtime \
		--timestamp \
		--preserve-metadata=identifier,entitlements,requirements \
		"$SIDEY_STAGED_APP"
fi

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
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYAuthURLScheme' "$SIDEY_INFO_PLIST")" != "sidey" ] \
	|| [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$SIDEY_INFO_PLIST")" != "sidey" ]; then
	echo "Release app must use the sidey OAuth callback scheme" >&2
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
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$SIDEY_INFO_PLIST")" != "SIDEY" ]; then
	echo "Release display name must be SIDEY" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYReleaseChannel' "$SIDEY_INFO_PLIST")" != "production" ]; then
	echo "Release channel must be production" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$SIDEY_INFO_PLIST")" != "https://raw.githubusercontent.com/sidey-app/SIDEY/main/updates/appcast.xml" ]; then
	echo "Unexpected Sparkle feed URL" >&2
	exit 1
fi
if [ -z "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$SIDEY_INFO_PLIST")" ]; then
	echo "Sparkle public key is missing" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SURequireSignedFeed' "$SIDEY_INFO_PLIST")" != "true" ]; then
	echo "SIDEY must require a signed Sparkle feed" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SUVerifyUpdateBeforeExtraction' "$SIDEY_INFO_PLIST")" != "true" ]; then
	echo "SIDEY must verify Sparkle updates before extraction" >&2
	exit 1
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_LOGIN_INFO_PLIST")" != "app.sidey.desktop.login-item" ]; then
	echo "Unexpected login item bundle identifier" >&2
	exit 1
fi

codesign --verify --deep --strict "$SIDEY_STAGED_APP"
if [ -n "$SIDEY_NOTARYTOOL_PROFILE" ]; then
	if [ "$SIDEY_CODE_SIGN_IDENTITY" = "-" ] || [ "$SIDEY_HARDENED_RUNTIME" != "YES" ]; then
		echo "Notarization requires Developer ID signing and SIDEY_HARDENED_RUNTIME=YES" >&2
		exit 64
	fi
	SIDEY_NOTARY_ZIP="$SIDEY_STAGE_DIR/SIDEY-notary-submission.zip"
	SIDEY_NOTARY_RESULT="$SIDEY_STAGE_DIR/notary-result.json"
	ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$SIDEY_STAGED_APP" "$SIDEY_NOTARY_ZIP"
	xcrun notarytool submit \
		"$SIDEY_NOTARY_ZIP" \
		--keychain-profile "$SIDEY_NOTARYTOOL_PROFILE" \
		--wait \
		--output-format json > "$SIDEY_NOTARY_RESULT"
	cat "$SIDEY_NOTARY_RESULT"
	SIDEY_NOTARY_STATUS=$(/usr/bin/plutil -extract status raw -o - "$SIDEY_NOTARY_RESULT")
	if [ "$SIDEY_NOTARY_STATUS" != "Accepted" ]; then
		SIDEY_NOTARY_ID=$(/usr/bin/plutil -extract id raw -o - "$SIDEY_NOTARY_RESULT")
		SIDEY_NOTARY_LOG="$SIDEY_STAGE_DIR/notary-log.json"
		if xcrun notarytool log \
			"$SIDEY_NOTARY_ID" \
			--keychain-profile "$SIDEY_NOTARYTOOL_PROFILE" \
			"$SIDEY_NOTARY_LOG"; then
			cat "$SIDEY_NOTARY_LOG" >&2
		fi
		echo "Apple notarization failed with status: $SIDEY_NOTARY_STATUS" >&2
		exit 65
	fi
	xcrun stapler staple "$SIDEY_STAGED_APP"
	xcrun stapler validate "$SIDEY_STAGED_APP"
	codesign --verify --deep --strict "$SIDEY_STAGED_APP"
fi
codesign --verify --strict "$SIDEY_SPARKLE_FRAMEWORK"
otool -L "$SIDEY_MAIN_EXECUTABLE" | grep -F '@rpath/Sparkle.framework/Versions/B/Sparkle' >/dev/null || {
	echo "SIDEY executable is not linked to the bundled Sparkle framework" >&2
	exit 1
}

mkdir -p "$SIDEY_EXPORT_DIR"
SIDEY_EXPORT_APP="$SIDEY_EXPORT_DIR/SIDEY.app"
if [ -e "$SIDEY_EXPORT_APP" ]; then
	mv "$SIDEY_EXPORT_APP" "$SIDEY_STAGE_DIR/previous-SIDEY.app"
fi
mv "$SIDEY_STAGED_APP" "$SIDEY_EXPORT_APP"

SIDEY_STAGED_ZIP="$SIDEY_STAGE_DIR/$(basename -- "$SIDEY_ZIP_PATH")"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$SIDEY_EXPORT_APP" "$SIDEY_STAGED_ZIP"
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
