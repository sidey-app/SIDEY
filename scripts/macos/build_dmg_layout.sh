#!/bin/sh
set -eu

SIDEY_APP_PATH=${1:-}
SIDEY_DMG_PATH=${2:-}
SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
SIDEY_DMG_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/sidey-dmg-layout.XXXXXX")
SIDEY_DMG_MOUNT="$SIDEY_DMG_STAGE/mount"
SIDEY_DMG_ATTACHED=0
SIDEY_FINDER_PID=

cleanup() {
	if [ -n "$SIDEY_FINDER_PID" ] && kill -0 "$SIDEY_FINDER_PID" >/dev/null 2>&1; then
		kill "$SIDEY_FINDER_PID" >/dev/null 2>&1 || true
		wait "$SIDEY_FINDER_PID" >/dev/null 2>&1 || true
	fi
	if [ "$SIDEY_DMG_ATTACHED" = 1 ]; then
		hdiutil detach "$SIDEY_DMG_MOUNT" >/dev/null 2>&1 || \
			hdiutil detach -force "$SIDEY_DMG_MOUNT" >/dev/null 2>&1 || true
	fi
	rm -rf "$SIDEY_DMG_STAGE"
}

on_exit() {
	SIDEY_EXIT_STATUS=$?
	trap - EXIT HUP INT TERM
	cleanup
	exit "$SIDEY_EXIT_STATUS"
}
trap on_exit EXIT HUP INT TERM

if [ -z "$SIDEY_APP_PATH" ] || [ ! -d "$SIDEY_APP_PATH" ]; then
	echo "Usage: $0 /path/to/SIDEY.app /path/to/SIDEY.dmg" >&2
	exit 64
fi
case "$SIDEY_DMG_PATH" in
	*.dmg) ;;
	*)
		echo "DMG output path must end in .dmg: $SIDEY_DMG_PATH" >&2
		exit 64
		;;
esac
if [ -e "$SIDEY_DMG_PATH" ]; then
	echo "Refusing to overwrite an existing DMG: $SIDEY_DMG_PATH" >&2
	exit 64
fi
if ! pgrep -x Finder >/dev/null; then
	echo "DMG layout requires a logged-in macOS session with Finder running" >&2
	exit 69
fi

SIDEY_DMG_ROOT="$SIDEY_DMG_STAGE/root"
SIDEY_DMG_BACKGROUND_DIR="$SIDEY_DMG_ROOT/.background"
SIDEY_WRITABLE_DMG="$SIDEY_DMG_STAGE/SIDEY-writable.dmg"
SIDEY_COMPRESSED_DMG="$SIDEY_DMG_STAGE/SIDEY-compressed.dmg"
mkdir -p "$SIDEY_DMG_BACKGROUND_DIR" "$SIDEY_DMG_MOUNT"
ditto "$SIDEY_APP_PATH" "$SIDEY_DMG_ROOT/SIDEY.app"
ln -s /Applications "$SIDEY_DMG_ROOT/Applications"

xcrun swift \
	"$SIDEY_REPO_ROOT/scripts/macos/generate_dmg_background.swift" \
	"$SIDEY_REPO_ROOT" \
	"$SIDEY_DMG_BACKGROUND_DIR/background.png"

hdiutil create \
	-quiet \
	-volname SIDEY \
	-srcfolder "$SIDEY_DMG_ROOT" \
	-fs HFS+ \
	-format UDRW \
	-ov \
	"$SIDEY_WRITABLE_DMG"
hdiutil attach \
	-readwrite \
	-noverify \
	-noautoopen \
	-nobrowse \
	-mountpoint "$SIDEY_DMG_MOUNT" \
	"$SIDEY_WRITABLE_DMG" >/dev/null
SIDEY_DMG_ATTACHED=1

osascript \
	"$SIDEY_REPO_ROOT/scripts/macos/configure_dmg_window.applescript" \
	"$SIDEY_DMG_MOUNT" &
SIDEY_FINDER_PID=$!

SIDEY_DS_STORE_ATTEMPTS=0
while [ ! -f "$SIDEY_DMG_MOUNT/.DS_Store" ] && \
	kill -0 "$SIDEY_FINDER_PID" >/dev/null 2>&1 && \
	[ "$SIDEY_DS_STORE_ATTEMPTS" -lt 40 ]; do
	sleep 0.25
	SIDEY_DS_STORE_ATTEMPTS=$((SIDEY_DS_STORE_ATTEMPTS + 1))
done
if [ -f "$SIDEY_DMG_MOUNT/.DS_Store" ]; then
	sleep 1
fi
if kill -0 "$SIDEY_FINDER_PID" >/dev/null 2>&1; then
	kill "$SIDEY_FINDER_PID" >/dev/null 2>&1 || true
fi
wait "$SIDEY_FINDER_PID" >/dev/null 2>&1 || true
SIDEY_FINDER_PID=

if [ ! -f "$SIDEY_DMG_MOUNT/.DS_Store" ]; then
	echo "Finder did not write the DMG .DS_Store layout" >&2
	exit 69
fi
sync

hdiutil detach "$SIDEY_DMG_MOUNT" >/dev/null
SIDEY_DMG_ATTACHED=0
hdiutil convert \
	"$SIDEY_WRITABLE_DMG" \
	-quiet \
	-format UDZO \
	-imagekey zlib-level=9 \
	-ov \
	-o "$SIDEY_COMPRESSED_DMG"
hdiutil verify "$SIDEY_COMPRESSED_DMG" >/dev/null
"$SIDEY_REPO_ROOT/scripts/macos/verify_dmg_layout.sh" "$SIDEY_COMPRESSED_DMG"

mkdir -p "$(dirname -- "$SIDEY_DMG_PATH")"
mv "$SIDEY_COMPRESSED_DMG" "$SIDEY_DMG_PATH"
