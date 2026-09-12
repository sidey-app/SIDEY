#!/bin/sh
set -eu
SIDEY_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && /bin/pwd -P)
exec /usr/bin/python3 "$SIDEY_SCRIPT_DIR/open_current.py" "$@"
