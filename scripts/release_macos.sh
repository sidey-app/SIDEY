#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
SIDEY_MANIFEST="$SIDEY_REPO_ROOT/release/macos.json"
SIDEY_TAP_REPOSITORY=${SIDEY_TAP_REPOSITORY:-sidey-app/homebrew-tap}
SIDEY_CODE_SIGN_IDENTITY=${SIDEY_CODE_SIGN_IDENTITY:-}
SIDEY_HARDENED_RUNTIME=${SIDEY_HARDENED_RUNTIME:-}
SIDEY_NOTARYTOOL_PROFILE=${SIDEY_NOTARYTOOL_PROFILE:-}

fail() {
	echo "$*" >&2
	exit 1
}

for SIDEY_COMMAND in brew git gh python3 shasum; do
	command -v "$SIDEY_COMMAND" >/dev/null 2>&1 || fail "Required command is missing: $SIDEY_COMMAND"
done
[ "$(uname -s)" = Darwin ] || fail "macOS releases must be prepared on macOS."
[ -n "$SIDEY_CODE_SIGN_IDENTITY" ] && [ "$SIDEY_CODE_SIGN_IDENTITY" != - ] || \
	fail "SIDEY_CODE_SIGN_IDENTITY must name a Developer ID Application certificate."
[ "$SIDEY_HARDENED_RUNTIME" = YES ] || fail "SIDEY_HARDENED_RUNTIME must be YES."
[ -n "$SIDEY_NOTARYTOOL_PROFILE" ] || fail "SIDEY_NOTARYTOOL_PROFILE is required."
gh auth status >/dev/null 2>&1 || fail "Authenticate GitHub CLI before releasing."

cd "$SIDEY_REPO_ROOT"
[ "$(git branch --show-current)" = main ] || fail "Run the macOS release from main."
[ -z "$(git status --porcelain)" ] || fail "The main worktree must be clean."
git fetch origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || \
	fail "Local main must exactly match origin/main."

SIDEY_VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$SIDEY_MANIFEST")
SIDEY_BUILD=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["build"])' "$SIDEY_MANIFEST")
SIDEY_TAG="v$SIDEY_VERSION"
SIDEY_RELEASE_NOTES="$SIDEY_REPO_ROOT/docs/releases/$SIDEY_TAG.md"
SIDEY_RELEASE_DIR="$SIDEY_REPO_ROOT/build/releases/$SIDEY_TAG"
SIDEY_ZIP_NAME="SIDEY-macOS-arm64-$SIDEY_TAG.zip"
SIDEY_DMG_NAME="SIDEY-macOS-arm64-$SIDEY_TAG.dmg"
SIDEY_ZIP="$SIDEY_RELEASE_DIR/$SIDEY_ZIP_NAME"
SIDEY_DMG="$SIDEY_RELEASE_DIR/$SIDEY_DMG_NAME"
SIDEY_ZIP_SHA="$SIDEY_ZIP.sha256"
SIDEY_DMG_SHA="$SIDEY_DMG.sha256"
SIDEY_COMMIT=$(git rev-parse HEAD)

python3 ./scripts/verify_release_consistency.py --platform macos --allow-pending-appcast
[ -f "$SIDEY_RELEASE_NOTES" ] || fail "Release notes are missing: $SIDEY_RELEASE_NOTES"
if [ "${SIDEY_ARCHIVE_APP_STORE:-0}" = 1 ]; then
	./scripts/macos/archive_app_store.sh
fi

export SIDEY_CODE_SIGN_IDENTITY SIDEY_HARDENED_RUNTIME SIDEY_NOTARYTOOL_PROFILE
./scripts/package_macos_release.sh "$SIDEY_TAG"
for SIDEY_ASSET in "$SIDEY_ZIP" "$SIDEY_ZIP_SHA" "$SIDEY_DMG" "$SIDEY_DMG_SHA"; do
	[ -f "$SIDEY_ASSET" ] || fail "Release asset is missing: $SIDEY_ASSET"
done

if ! gh release view "$SIDEY_TAG" >/dev/null 2>&1; then
	gh release create "$SIDEY_TAG" \
		"$SIDEY_DMG" "$SIDEY_DMG_SHA" "$SIDEY_ZIP" "$SIDEY_ZIP_SHA" \
		--target "$SIDEY_COMMIT" \
		--title "SIDEY macOS $SIDEY_TAG" \
		--notes-file "$SIDEY_RELEASE_NOTES" \
		--draft
fi

SIDEY_EXPECTED_ASSETS=$(printf '%s\n' \
	"$SIDEY_DMG_NAME" "$SIDEY_DMG_NAME.sha256" \
	"$SIDEY_ZIP_NAME" "$SIDEY_ZIP_NAME.sha256" | sort)
SIDEY_REMOTE_ASSETS=$(gh release view "$SIDEY_TAG" --json assets \
	--jq '.assets | map(.name) | sort | join("\n")')
[ "$SIDEY_REMOTE_ASSETS" = "$SIDEY_EXPECTED_ASSETS" ] || \
	fail "Release assets do not match the four expected files for $SIDEY_TAG."

SIDEY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sidey-release.XXXXXX")
cleanup() {
	rm -rf "$SIDEY_TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

SIDEY_VERIFY_DIR="$SIDEY_TEMP_DIR/release-assets"
mkdir -p "$SIDEY_VERIFY_DIR"
for SIDEY_NAME in "$SIDEY_DMG_NAME" "$SIDEY_DMG_NAME.sha256" "$SIDEY_ZIP_NAME" "$SIDEY_ZIP_NAME.sha256"; do
	gh release download "$SIDEY_TAG" --pattern "$SIDEY_NAME" --dir "$SIDEY_VERIFY_DIR" --clobber
	cmp -s "$SIDEY_RELEASE_DIR/$SIDEY_NAME" "$SIDEY_VERIFY_DIR/$SIDEY_NAME" || \
		fail "Downloaded release asset differs from the local candidate: $SIDEY_NAME"
done

if [ "$(gh release view "$SIDEY_TAG" --json isDraft --jq .isDraft)" = true ]; then
	gh release edit "$SIDEY_TAG" --draft=false
fi
[ "$(gh release view "$SIDEY_TAG" --json isDraft,isPrerelease --jq '.isDraft or .isPrerelease')" = false ] || \
	fail "Release is not a published stable release: $SIDEY_TAG"
gh workflow run pages.yml --repo sidey-app/SIDEY --ref main

SIDEY_APPCAST_CLONE="$SIDEY_TEMP_DIR/sidey-appcast"
gh repo clone sidey-app/SIDEY "$SIDEY_APPCAST_CLONE" -- --branch main --single-branch
SIDEY_APPCAST_BRANCH="shared/macos-$SIDEY_VERSION-appcast"
git -C "$SIDEY_APPCAST_CLONE" switch -c "$SIDEY_APPCAST_BRANCH"
SIDEY_APPCAST_OUTPUT="$SIDEY_APPCAST_CLONE/updates/appcast.xml" \
SIDEY_RELEASE_NOTES="$SIDEY_RELEASE_NOTES" \
	./scripts/macos/prepare_sparkle_appcast.sh "$SIDEY_TAG" "$SIDEY_ZIP"
python3 "$SIDEY_APPCAST_CLONE/scripts/verify_release_consistency.py" --platform macos
git -C "$SIDEY_APPCAST_CLONE" add updates/appcast.xml
git -C "$SIDEY_APPCAST_CLONE" commit -m "Publish Sparkle appcast for $SIDEY_TAG"
git -C "$SIDEY_APPCAST_CLONE" push -u origin "$SIDEY_APPCAST_BRANCH"
gh pr create --repo sidey-app/SIDEY --base main --head "$SIDEY_APPCAST_BRANCH" \
	--title "Publish Sparkle appcast for $SIDEY_TAG" \
	--body "Publishes the signed Sparkle appcast generated from the verified $SIDEY_TAG release ZIP."

SIDEY_DMG_HASH=$(shasum -a 256 "$SIDEY_DMG" | awk '{print $1}')
SIDEY_TAP_CLONE="$SIDEY_TEMP_DIR/homebrew-tap"
gh repo clone "$SIDEY_TAP_REPOSITORY" "$SIDEY_TAP_CLONE" -- --branch main --single-branch
SIDEY_TAP_BRANCH="release/sidey-$SIDEY_VERSION"
git -C "$SIDEY_TAP_CLONE" switch -c "$SIDEY_TAP_BRANCH"
python3 - "$SIDEY_TAP_CLONE/Casks/sidey.rb" "$SIDEY_VERSION" "$SIDEY_DMG_HASH" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text, versions = re.subn(r'^  version "[^"]+"$', f'  version "{sys.argv[2]}"', text, flags=re.MULTILINE)
text, hashes = re.subn(r'^  sha256 "[0-9a-f]+"$', f'  sha256 "{sys.argv[3]}"', text, flags=re.MULTILINE)
if versions != 1 or hashes != 1:
    raise SystemExit("Expected one version and one sha256 field in Casks/sidey.rb")
path.write_text(text, encoding="utf-8")
PY
brew style "$SIDEY_TAP_CLONE/Casks/sidey.rb"
git -C "$SIDEY_TAP_CLONE" add Casks/sidey.rb
git -C "$SIDEY_TAP_CLONE" commit -m "Update SIDEY to $SIDEY_VERSION"
git -C "$SIDEY_TAP_CLONE" push -u origin "$SIDEY_TAP_BRANCH"
gh pr create --repo "$SIDEY_TAP_REPOSITORY" --base main --head "$SIDEY_TAP_BRANCH" \
	--title "Update SIDEY to $SIDEY_VERSION" \
	--body "Updates the Cask to the verified $SIDEY_TAG notarized DMG and SHA-256."

echo "Published and verified SIDEY macOS $SIDEY_TAG (build $SIDEY_BUILD)."
echo "Opened the Sparkle appcast and Homebrew Cask pull requests."
