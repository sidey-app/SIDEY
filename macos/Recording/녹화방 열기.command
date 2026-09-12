#!/bin/sh
set -eu
SIDEY_RECORDING_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && /bin/pwd -P)
exec python3 "$SIDEY_RECORDING_ROOT/scripts/workflow.py" --repo "$SIDEY_RECORDING_ROOT" open --scheme sidey-reals
