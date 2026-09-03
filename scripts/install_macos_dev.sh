#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
SIDEY_DERIVED_DATA=${SIDEY_DEV_DERIVED_DATA:-$SIDEY_REPO_ROOT/build/macos-dev-derived}
SIDEY_PRODUCT_APP="$SIDEY_DERIVED_DATA/Build/Products/Release/SIDEY.app"
SIDEY_TARGET_APP=/Applications/Sidey-dev.app
SIDEY_TARGET_EXECUTABLE="$SIDEY_TARGET_APP/Contents/MacOS/SIDEY"
SIDEY_PRODUCTION_EXECUTABLE=/Applications/SIDEY.app/Contents/MacOS/SIDEY
SIDEY_PROJECT_FILE="$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj/project.pbxproj"
SIDEY_VERSION=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);$/\1/p' "$SIDEY_PROJECT_FILE" | sort -u)
SIDEY_BUILD_NUMBER=$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);$/\1/p' "$SIDEY_PROJECT_FILE" | sort -u)
SIDEY_INSTALL_DIR=
SIDEY_BACKUP_APP=
SIDEY_INSTALL_COMPLETE=0

if [ -z "${SIDEY_SUPABASE_URL:-}" ] || [ -z "${SIDEY_SUPABASE_PUBLISHABLE_KEY:-}" ]; then
	echo "Sidey-dev requires SIDEY-staging SIDEY_SUPABASE_URL and SIDEY_SUPABASE_PUBLISHABLE_KEY" >&2
	exit 64
fi
case "$SIDEY_SUPABASE_URL" in
	https://*) ;;
	http://localhost:*|http://127.0.0.1:*|http://\[::1\]:*) ;;
	*)
		echo "Sidey-dev Supabase URL must use HTTPS (or a loopback URL for local development)" >&2
		exit 64
		;;
esac
case "$SIDEY_SUPABASE_URL" in
	*whtejsviizgejauasqqt*)
		echo "Refusing to build Sidey-dev against the production Supabase project" >&2
		exit 64
		;;
esac
case "$SIDEY_SUPABASE_PUBLISHABLE_KEY" in
	sb_secret_*|service_role*)
		echo "Refusing to embed a Supabase secret/service-role key in Sidey-dev" >&2
		exit 64
		;;
esac

cleanup() {
	if [ "$SIDEY_INSTALL_COMPLETE" != 1 ] && [ -n "$SIDEY_INSTALL_DIR" ]; then
		if [ -d "$SIDEY_BACKUP_APP" ]; then
			if [ -e "$SIDEY_TARGET_APP" ]; then
				mv "$SIDEY_TARGET_APP" "$SIDEY_INSTALL_DIR/failed-Sidey-dev.app"
			fi
			mv "$SIDEY_BACKUP_APP" "$SIDEY_TARGET_APP"
		fi
	fi
	if [ -n "$SIDEY_INSTALL_DIR" ] && [ -d "$SIDEY_INSTALL_DIR" ]; then
		rm -rf "$SIDEY_INSTALL_DIR"
	fi
}
trap cleanup EXIT HUP INT TERM

if ! printf '%s\n' "$SIDEY_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
	echo "Xcode project must contain one semantic marketing version" >&2
	exit 65
fi
if ! printf '%s\n' "$SIDEY_BUILD_NUMBER" | grep -Eq '^[0-9]+$'; then
	echo "Xcode project must contain one numeric build number" >&2
	exit 65
fi

python3 "$SIDEY_REPO_ROOT/scripts/validate_pixel_assets.py"
xcodebuild \
	-project "$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj" \
	-scheme SIDEY \
	-configuration Release \
	-destination 'platform=macOS,arch=arm64' \
	-derivedDataPath "$SIDEY_DERIVED_DATA" \
	-disableAutomaticPackageResolution \
	ARCHS=arm64 \
	ONLY_ACTIVE_ARCH=YES \
	CODE_SIGN_IDENTITY=- \
	ENABLE_HARDENED_RUNTIME=NO \
	SIDEY_AUTH_URL_SCHEME=sidey-dev \
	SIDEY_APP_BUNDLE_IDENTIFIER=app.sidey.desktop.dev \
	SIDEY_DISPLAY_NAME=Sidey-dev \
	SIDEY_LOGIN_ITEM_BUNDLE_IDENTIFIER=app.sidey.desktop.dev.login-item \
	SIDEY_RELEASE_CHANNEL=development \
	SIDEY_SUPABASE_URL="$SIDEY_SUPABASE_URL" \
	SIDEY_SUPABASE_PUBLISHABLE_KEY="$SIDEY_SUPABASE_PUBLISHABLE_KEY" \
	build

if [ ! -d "$SIDEY_PRODUCT_APP" ]; then
	echo "Native SIDEY product not found: $SIDEY_PRODUCT_APP" >&2
	exit 66
fi

SIDEY_INFO_PLIST="$SIDEY_PRODUCT_APP/Contents/Info.plist"
SIDEY_MAIN_EXECUTABLE="$SIDEY_PRODUCT_APP/Contents/MacOS/SIDEY"
SIDEY_LOGIN_APP="$SIDEY_PRODUCT_APP/Contents/Library/LoginItems/SIDEYLoginItem.app"
SIDEY_LOGIN_EXECUTABLE="$SIDEY_LOGIN_APP/Contents/MacOS/SIDEYLoginItem"
SIDEY_LOGIN_INFO_PLIST="$SIDEY_LOGIN_APP/Contents/Info.plist"

for SIDEY_REQUIRED_PATH in \
	"$SIDEY_INFO_PLIST" \
	"$SIDEY_MAIN_EXECUTABLE" \
	"$SIDEY_LOGIN_INFO_PLIST" \
	"$SIDEY_LOGIN_EXECUTABLE"; do
	if [ ! -e "$SIDEY_REQUIRED_PATH" ]; then
		echo "Required development build file missing: $SIDEY_REQUIRED_PATH" >&2
		exit 66
	fi
done

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_INFO_PLIST")" != app.sidey.desktop.dev ]; then
	echo "Development app must use its isolated bundle identifier" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$SIDEY_INFO_PLIST")" != Sidey-dev ]; then
	echo "Development app display name must be Sidey-dev" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYReleaseChannel' "$SIDEY_INFO_PLIST")" != development ]; then
	echo "Development app must use the development release channel" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYAuthURLScheme' "$SIDEY_INFO_PLIST")" != sidey-dev ] \
	|| [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$SIDEY_INFO_PLIST")" != sidey-dev ]; then
	echo "Development app must use the sidey-dev OAuth callback scheme" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SIDEY_INFO_PLIST")" != "$SIDEY_VERSION" ]; then
	echo "Development app version does not match the Xcode project" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SIDEY_INFO_PLIST")" != "$SIDEY_BUILD_NUMBER" ]; then
	echo "Development app build number does not match the Xcode project" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SIDEY_LOGIN_INFO_PLIST")" != app.sidey.desktop.dev.login-item ]; then
	echo "Development login item must use its isolated bundle identifier" >&2
	exit 65
fi
if [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYSupabaseURL' "$SIDEY_INFO_PLIST")" != "$SIDEY_SUPABASE_URL" ] \
	|| [ "$(/usr/libexec/PlistBuddy -c 'Print :SIDEYSupabasePublishableKey' "$SIDEY_INFO_PLIST")" != "$SIDEY_SUPABASE_PUBLISHABLE_KEY" ]; then
	echo "Development app does not contain the requested SIDEY-staging configuration" >&2
	exit 65
fi
if [ "$(lipo -archs "$SIDEY_MAIN_EXECUTABLE")" != arm64 ] \
	|| [ "$(lipo -archs "$SIDEY_LOGIN_EXECUTABLE")" != arm64 ]; then
	echo "Development app and login item must contain only arm64" >&2
	exit 65
fi

codesign --verify --deep --strict "$SIDEY_PRODUCT_APP"
SIDEY_SIGNATURE=$(codesign -dv --verbose=4 "$SIDEY_PRODUCT_APP" 2>&1)
printf '%s\n' "$SIDEY_SIGNATURE" | grep -F 'Signature=adhoc' >/dev/null || {
	echo "Development app must use an ad-hoc signature" >&2
	exit 65
}

SIDEY_PRODUCTION_PIDS=$(
	ps -axo pid=,command= \
		| awk -v executable="$SIDEY_PRODUCTION_EXECUTABLE" '$2 == executable { print $1 }'
)
if [ -n "$SIDEY_PRODUCTION_PIDS" ]; then
	echo "The production SIDEY app is running; quit it before installing Sidey-dev" >&2
	exit 65
fi

SIDEY_RUNNING_PIDS=$(
	ps -axo pid=,command= \
		| awk -v executable="$SIDEY_TARGET_EXECUTABLE" '$2 == executable { print $1 }'
)
if [ -n "$SIDEY_RUNNING_PIDS" ]; then
	# shellcheck disable=SC2086
	kill $SIDEY_RUNNING_PIDS
	SIDEY_WAIT_COUNT=0
	while [ "$SIDEY_WAIT_COUNT" -lt 50 ]; do
		SIDEY_RUNNING_PIDS=$(
			ps -axo pid=,command= \
				| awk -v executable="$SIDEY_TARGET_EXECUTABLE" '$2 == executable { print $1 }'
		)
		[ -z "$SIDEY_RUNNING_PIDS" ] && break
		sleep 0.1
		SIDEY_WAIT_COUNT=$((SIDEY_WAIT_COUNT + 1))
	done
	if [ -n "$SIDEY_RUNNING_PIDS" ]; then
		echo "Sidey-dev is still running; quit it and run this script again" >&2
		exit 65
	fi
fi

SIDEY_INSTALL_DIR=$(mktemp -d /Applications/.sidey-dev-install.XXXXXX)
SIDEY_STAGED_APP="$SIDEY_INSTALL_DIR/Sidey-dev.app"
SIDEY_BACKUP_APP="$SIDEY_INSTALL_DIR/previous-Sidey-dev.app"
ditto "$SIDEY_PRODUCT_APP" "$SIDEY_STAGED_APP"
codesign --verify --deep --strict "$SIDEY_STAGED_APP"

if [ -e "$SIDEY_TARGET_APP" ]; then
	if [ ! -d "$SIDEY_TARGET_APP" ]; then
		echo "Refusing to replace non-app path: $SIDEY_TARGET_APP" >&2
		exit 65
	fi
	mv "$SIDEY_TARGET_APP" "$SIDEY_BACKUP_APP"
fi
mv "$SIDEY_STAGED_APP" "$SIDEY_TARGET_APP"
codesign --verify --deep --strict "$SIDEY_TARGET_APP"
SIDEY_INSTALL_COMPLETE=1

open -n "$SIDEY_TARGET_APP"
SIDEY_LAUNCH_WAIT_COUNT=0
SIDEY_RUNNING_PIDS=
while [ "$SIDEY_LAUNCH_WAIT_COUNT" -lt 50 ]; do
	SIDEY_RUNNING_PIDS=$(
		ps -axo pid=,command= \
			| awk -v executable="$SIDEY_TARGET_EXECUTABLE" '$2 == executable { print $1 }'
	)
	[ -n "$SIDEY_RUNNING_PIDS" ] && break
	sleep 0.1
	SIDEY_LAUNCH_WAIT_COUNT=$((SIDEY_LAUNCH_WAIT_COUNT + 1))
done
if [ -z "$SIDEY_RUNNING_PIDS" ]; then
	echo "Installed Sidey-dev but macOS did not launch its exact executable path" >&2
	exit 65
fi
SIDEY_PRODUCTION_PIDS=$(
	ps -axo pid=,command= \
		| awk -v executable="$SIDEY_PRODUCTION_EXECUTABLE" '$2 == executable { print $1 }'
)
if [ -n "$SIDEY_PRODUCTION_PIDS" ]; then
	echo "Production SIDEY launched while starting Sidey-dev; refusing a false-success result" >&2
	exit 65
fi
echo "Installed and launched $SIDEY_TARGET_APP"
echo "SIDEY $SIDEY_VERSION build $SIDEY_BUILD_NUMBER · development · ad-hoc · arm64"
