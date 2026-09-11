#!/bin/sh
set -eu

SIDEY_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && /bin/pwd -P)
exec python3 "$SIDEY_REPO_ROOT/scripts/verify_release_consistency.py" "$@"
