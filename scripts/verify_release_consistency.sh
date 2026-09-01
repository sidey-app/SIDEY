#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
SIDEY_PROJECT="$SIDEY_REPO_ROOT/macos/SIDEY.xcodeproj/project.pbxproj"
SIDEY_APPCAST="$SIDEY_REPO_ROOT/updates/appcast.xml"

fail() {
	printf 'release consistency error: %s\n' "$1" >&2
	exit 1
}

unique_project_value() {
	SIDEY_SETTING=$1
	SIDEY_VALUES=$(sed -n "s/.*$SIDEY_SETTING = \([^;]*\);/\1/p" "$SIDEY_PROJECT" | sort -u)
	SIDEY_VALUE_COUNT=$(printf '%s\n' "$SIDEY_VALUES" | sed '/^$/d' | wc -l | tr -d ' ')
	[ "$SIDEY_VALUE_COUNT" -eq 1 ] || fail "$SIDEY_SETTING must have one value, found: $SIDEY_VALUES"
	printf '%s\n' "$SIDEY_VALUES"
}

SIDEY_VERSION=$(unique_project_value MARKETING_VERSION)
SIDEY_BUILD=$(unique_project_value CURRENT_PROJECT_VERSION)
SIDEY_TAG="v$SIDEY_VERSION"
SIDEY_DMG="SIDEY-macOS-arm64-$SIDEY_TAG.dmg"
SIDEY_ZIP="SIDEY-macOS-arm64-$SIDEY_TAG.zip"
SIDEY_RELEASE_ROOT="https://github.com/sidey-app/SIDEY/releases"

grep -Fq "<sparkle:shortVersionString>$SIDEY_VERSION</sparkle:shortVersionString>" "$SIDEY_APPCAST" \
	|| fail "appcast does not contain version $SIDEY_VERSION"
grep -Fq "<sparkle:version>$SIDEY_BUILD</sparkle:version>" "$SIDEY_APPCAST" \
	|| fail "appcast does not contain build $SIDEY_BUILD"
grep -Fq "$SIDEY_RELEASE_ROOT/download/$SIDEY_TAG/$SIDEY_ZIP" "$SIDEY_APPCAST" \
	|| fail "appcast ZIP URL does not match $SIDEY_TAG"

for SIDEY_PAGE in "$SIDEY_REPO_ROOT/website/index.html" "$SIDEY_REPO_ROOT/website/en/index.html"; do
	grep -Fq "$SIDEY_RELEASE_ROOT/download/$SIDEY_TAG/$SIDEY_DMG" "$SIDEY_PAGE" \
		|| fail "$(basename "$(dirname "$SIDEY_PAGE")") website DMG URL does not match $SIDEY_TAG"
	grep -Fq "$SIDEY_RELEASE_ROOT/tag/$SIDEY_TAG" "$SIDEY_PAGE" \
		|| fail "$(basename "$(dirname "$SIDEY_PAGE")") website release URL does not match $SIDEY_TAG"
done

grep -Fq "현재 공개 버전은 \`$SIDEY_TAG\`(build $SIDEY_BUILD)" "$SIDEY_REPO_ROOT/README.md" \
	|| fail "README public version does not match $SIDEY_TAG build $SIDEY_BUILD"
grep -Fq "현재 공개본은 버전 \`$SIDEY_VERSION\`, 빌드 \`$SIDEY_BUILD\`의 \`$SIDEY_TAG\`" "$SIDEY_REPO_ROOT/docs/DECISIONS.md" \
	|| fail "DECISIONS public version does not match $SIDEY_TAG build $SIDEY_BUILD"
grep -Fq "macOS \`$SIDEY_TAG\`(build $SIDEY_BUILD) 정식 공개" "$SIDEY_REPO_ROOT/docs/PRODUCT_SPEC.md" \
	|| fail "PRODUCT_SPEC public version does not match $SIDEY_TAG build $SIDEY_BUILD"

printf 'release metadata is consistent: %s (build %s)\n' "$SIDEY_TAG" "$SIDEY_BUILD"
