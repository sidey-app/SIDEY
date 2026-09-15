#!/usr/bin/env python3
"""Validate the deterministic part of SIDEY's commit-message contract.

This validator intentionally checks the subject only. Commit bodies require
contextual writing judgment, and contributor attribution remains owned by the
repository's prepare-commit-msg hook.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


ALLOWED_TYPES = frozenset(
    {"feat", "fix", "refactor", "perf", "docs", "test", "build", "ci", "chore", "revert"}
)
ALLOWED_SCOPES = frozenset(
    {"macOS-Direct", "AppStore", "macOS-Direct / AppStore", "Windows", "Shared"}
)

_CONVENTIONAL_SUBJECT = re.compile(
    r"(?P<type>[^\s():]+)\((?P<scope>[^)\r\n]+)\): (?P<summary>[^\r\n]+)"
)
_HANGUL = re.compile(r"[\u1100-\u11ff\u3130-\u318f\uac00-\ud7a3]")
_GENERATED_MERGE_SUBJECTS = (
    re.compile(r"Merge pull request #\d+ from \S+"),
    re.compile(r"Merge commit '[0-9a-fA-F]{7,40}' into \S+"),
    re.compile(r"Merge (?:branch|remote-tracking branch) '[^']+'(?: of \S+)?(?: into \S+)?"),
)


def is_generated_merge_subject(subject: str) -> bool:
    """Return whether *subject* has a known Git/GitHub generated merge form."""

    return any(pattern.fullmatch(subject) for pattern in _GENERATED_MERGE_SUBJECTS)


def validate_subject(subject: str) -> list[str]:
    """Return deterministic policy violations for one commit subject."""

    if not subject:
        return ["The commit subject is empty."]
    if "\n" in subject or "\r" in subject:
        return ["The commit subject must be a single line."]
    if is_generated_merge_subject(subject):
        return []

    match = _CONVENTIONAL_SUBJECT.fullmatch(subject)
    if not match:
        return ["The commit subject must use 'type(scope): Korean summary'."]

    violations = []
    commit_type = match.group("type")
    scope = match.group("scope")
    summary = match.group("summary")
    if commit_type not in ALLOWED_TYPES:
        violations.append(f"Unsupported commit type: {commit_type}")
    if scope not in ALLOWED_SCOPES:
        violations.append(f"Unsupported commit scope: {scope}")
    if summary != summary.strip():
        violations.append("The summary must not have leading or trailing whitespace.")
    if not _HANGUL.search(summary):
        violations.append("The summary must include Korean text.")
    return violations


def validate_message(message: str) -> list[str]:
    """Validate a full message without interpreting its body or trailers."""

    if not message:
        return ["The commit message is empty."]
    subject = message.splitlines()[0] if message.splitlines() else ""
    return validate_subject(subject)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--subject", help="commit subject to validate")
    source.add_argument("--message-file", type=Path, help="full commit-message file to validate")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.subject is not None:
        violations = validate_subject(args.subject)
    elif args.message_file is not None:
        try:
            message = args.message_file.read_text(encoding="utf-8")
        except OSError as error:
            print(f"Cannot read the commit message: {error}", file=sys.stderr)
            return 2
        violations = validate_message(message)
    else:
        violations = validate_message(sys.stdin.read())

    if violations:
        for violation in violations:
            print(violation, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
