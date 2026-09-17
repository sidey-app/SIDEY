"""Run repository commands with consistent output and errors."""

from __future__ import annotations

import locale
import subprocess
from pathlib import Path

from .errors import WorkflowError


def decode_output(value: bytes | None) -> str:
    """Decode subprocess output and normalize its line endings."""

    if value is None:
        return ""

    encodings = ("utf-8", locale.getencoding())
    for encoding in dict.fromkeys(encodings):
        try:
            decoded = value.decode(encoding)
            return _normalize_line_endings(decoded)
        except UnicodeDecodeError:
            continue

    decoded = value.decode("utf-8", errors="replace")
    return _normalize_line_endings(decoded)


def _normalize_line_endings(value: str) -> str:
    return value.replace("\r\n", "\n").replace("\r", "\n")


def run(
    root: str | Path,
    *args: str,
    capture: bool = True,
) -> str:
    """Run a command from *root* or raise a workflow error."""

    result = subprocess.run(
        args,
        cwd=root,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        check=False,
    )
    stdout = decode_output(result.stdout)
    stderr = decode_output(result.stderr)
    if result.returncode:
        command = " ".join(args[:4])
        raise WorkflowError(f"{command} failed: {stderr.strip()}")
    return stdout.rstrip("\n")
