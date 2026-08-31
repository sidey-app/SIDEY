#!/bin/sh
set -eu

SIDEY_APP_PATH=${1:-}
SIDEY_DMG_PATH=${2:-}
SIDEY_CODE_SIGN_IDENTITY=${SIDEY_CODE_SIGN_IDENTITY:--}
SIDEY_NOTARYTOOL_PROFILE=${SIDEY_NOTARYTOOL_PROFILE:-}
SIDEY_DMG_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/sidey-dmg.XXXXXX")

cleanup() {
	rm -rf "$SIDEY_DMG_STAGE"
}
trap cleanup EXIT HUP INT TERM

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
if [ "$SIDEY_CODE_SIGN_IDENTITY" = "-" ]; then
	echo "Refusing to create a release DMG from an ad-hoc signed app" >&2
	exit 64
fi
if [ -z "$SIDEY_NOTARYTOOL_PROFILE" ]; then
	echo "SIDEY_NOTARYTOOL_PROFILE is required for a release DMG" >&2
	exit 64
fi

codesign --verify --deep --strict "$SIDEY_APP_PATH"
SIDEY_APP_SIGNATURE=$(codesign -dv --verbose=4 "$SIDEY_APP_PATH" 2>&1)
printf '%s\n' "$SIDEY_APP_SIGNATURE" | grep -Eq '^Authority=Developer ID Application:' || {
	echo "SIDEY.app is not signed with Developer ID Application" >&2
	exit 65
}
printf '%s\n' "$SIDEY_APP_SIGNATURE" | grep -Eq '^flags=.*runtime' || {
	echo "SIDEY.app is missing Hardened Runtime" >&2
	exit 65
}
xcrun stapler validate "$SIDEY_APP_PATH"
spctl --assess --type execute --verbose=2 "$SIDEY_APP_PATH"

SIDEY_DMG_ROOT="$SIDEY_DMG_STAGE/root"
SIDEY_UNSIGNED_DMG="$SIDEY_DMG_STAGE/SIDEY.dmg"
mkdir -p "$SIDEY_DMG_ROOT"
ditto "$SIDEY_APP_PATH" "$SIDEY_DMG_ROOT/SIDEY.app"
ln -s /Applications "$SIDEY_DMG_ROOT/Applications"

hdiutil create \
	-quiet \
	-volname SIDEY \
	-srcfolder "$SIDEY_DMG_ROOT" \
	-format UDZO \
	-ov \
	"$SIDEY_UNSIGNED_DMG"
hdiutil verify "$SIDEY_UNSIGNED_DMG" >/dev/null

codesign \
	--force \
	--sign "$SIDEY_CODE_SIGN_IDENTITY" \
	--timestamp \
	"$SIDEY_UNSIGNED_DMG"
codesign --verify --verbose=2 "$SIDEY_UNSIGNED_DMG"

SIDEY_DMG_NOTARY_RESULT="$SIDEY_DMG_STAGE/notary-result.json"
xcrun notarytool submit \
	"$SIDEY_UNSIGNED_DMG" \
	--keychain-profile "$SIDEY_NOTARYTOOL_PROFILE" \
	--wait \
	--output-format json > "$SIDEY_DMG_NOTARY_RESULT"
cat "$SIDEY_DMG_NOTARY_RESULT"
SIDEY_DMG_NOTARY_STATUS=$(/usr/bin/plutil -extract status raw -o - "$SIDEY_DMG_NOTARY_RESULT")
if [ "$SIDEY_DMG_NOTARY_STATUS" != "Accepted" ]; then
	SIDEY_DMG_NOTARY_ID=$(/usr/bin/plutil -extract id raw -o - "$SIDEY_DMG_NOTARY_RESULT")
	SIDEY_DMG_NOTARY_LOG="$SIDEY_DMG_STAGE/notary-log.json"
	if xcrun notarytool log \
		"$SIDEY_DMG_NOTARY_ID" \
		--keychain-profile "$SIDEY_NOTARYTOOL_PROFILE" \
		"$SIDEY_DMG_NOTARY_LOG"; then
		cat "$SIDEY_DMG_NOTARY_LOG" >&2
	fi
	echo "Apple DMG notarization failed with status: $SIDEY_DMG_NOTARY_STATUS" >&2
	exit 65
fi
xcrun stapler staple "$SIDEY_UNSIGNED_DMG"
xcrun stapler validate "$SIDEY_UNSIGNED_DMG"
codesign --verify --verbose=2 "$SIDEY_UNSIGNED_DMG"
hdiutil verify "$SIDEY_UNSIGNED_DMG" >/dev/null
spctl \
	--assess \
	--type open \
	--context context:primary-signature \
	--verbose=2 \
	"$SIDEY_UNSIGNED_DMG"

mkdir -p "$(dirname -- "$SIDEY_DMG_PATH")"
if [ -e "$SIDEY_DMG_PATH" ]; then
	mv "$SIDEY_DMG_PATH" "$SIDEY_DMG_STAGE/previous-SIDEY.dmg"
fi
mv "$SIDEY_UNSIGNED_DMG" "$SIDEY_DMG_PATH"

SIDEY_DMG_SHA_PATH="$SIDEY_DMG_PATH.sha256"
SIDEY_DMG_SHA_TEMP="$SIDEY_DMG_STAGE/$(basename -- "$SIDEY_DMG_SHA_PATH")"
(
	cd "$(dirname -- "$SIDEY_DMG_PATH")"
	shasum -a 256 "$(basename -- "$SIDEY_DMG_PATH")"
) > "$SIDEY_DMG_SHA_TEMP"
if [ -e "$SIDEY_DMG_SHA_PATH" ]; then
	mv "$SIDEY_DMG_SHA_PATH" "$SIDEY_DMG_STAGE/previous-SIDEY.dmg.sha256"
fi
mv "$SIDEY_DMG_SHA_TEMP" "$SIDEY_DMG_SHA_PATH"

echo "Created signed and notarized DMG: $SIDEY_DMG_PATH"
echo "DMG SHA-256: $SIDEY_DMG_SHA_PATH"
