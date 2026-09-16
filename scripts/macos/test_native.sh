#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
exec "$SIDEY_REPO_ROOT/scripts/macos/tests/test_native.sh" "$@"
