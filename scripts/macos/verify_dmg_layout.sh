#!/bin/sh
set -eu

SIDEY_DMG_PATH=${1:-}
SIDEY_VERIFY_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/sidey-dmg-verify.XXXXXX")
SIDEY_VERIFY_MOUNT="$SIDEY_VERIFY_STAGE/mount"
SIDEY_DMG_ATTACHED=0

cleanup() {
	if [ "$SIDEY_DMG_ATTACHED" = 1 ]; then
		hdiutil detach "$SIDEY_VERIFY_MOUNT" >/dev/null 2>&1 || \
			hdiutil detach -force "$SIDEY_VERIFY_MOUNT" >/dev/null 2>&1 || true
	fi
	rm -rf "$SIDEY_VERIFY_STAGE"
}

on_exit() {
	SIDEY_EXIT_STATUS=$?
	trap - EXIT HUP INT TERM
	cleanup
	exit "$SIDEY_EXIT_STATUS"
}
trap on_exit EXIT HUP INT TERM

if [ -z "$SIDEY_DMG_PATH" ] || [ ! -f "$SIDEY_DMG_PATH" ]; then
	echo "Usage: $0 /path/to/SIDEY.dmg" >&2
	exit 64
fi

mkdir -p "$SIDEY_VERIFY_MOUNT"
hdiutil attach \
	-readonly \
	-noverify \
	-noautoopen \
	-nobrowse \
	-mountpoint "$SIDEY_VERIFY_MOUNT" \
	"$SIDEY_DMG_PATH" >/dev/null
SIDEY_DMG_ATTACHED=1

if [ ! -d "$SIDEY_VERIFY_MOUNT/SIDEY.app" ]; then
	echo "DMG is missing SIDEY.app" >&2
	exit 65
fi
if [ ! -L "$SIDEY_VERIFY_MOUNT/Applications" ] || \
	[ "$(readlink "$SIDEY_VERIFY_MOUNT/Applications")" != "/Applications" ]; then
	echo "DMG Applications item must be a symbolic link to /Applications" >&2
	exit 65
fi
if [ ! -f "$SIDEY_VERIFY_MOUNT/.background/background.png" ]; then
	echo "DMG is missing .background/background.png" >&2
	exit 65
fi
if [ ! -f "$SIDEY_VERIFY_MOUNT/.DS_Store" ]; then
	echo "DMG is missing the Finder .DS_Store layout" >&2
	exit 65
fi

SIDEY_BACKGROUND_INFO=$(sips \
	-g pixelWidth \
	-g pixelHeight \
	"$SIDEY_VERIFY_MOUNT/.background/background.png")
printf '%s\n' "$SIDEY_BACKGROUND_INFO" | grep -Eq 'pixelWidth: 660$' || {
	echo "DMG background width must be 660 pixels" >&2
	exit 65
}
printf '%s\n' "$SIDEY_BACKGROUND_INFO" | grep -Eq 'pixelHeight: 420$' || {
	echo "DMG background height must be 420 pixels" >&2
	exit 65
}

hdiutil detach "$SIDEY_VERIFY_MOUNT" >/dev/null
SIDEY_DMG_ATTACHED=0
echo "Verified SIDEY DMG layout: $SIDEY_DMG_PATH"
