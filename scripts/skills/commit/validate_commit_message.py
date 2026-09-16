#!/usr/bin/env python3
"""Validate the deterministic parts of SIDEY's commit-message contract."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys

ALLOWED_TYPES = frozenset(
    {
        "build",
        "chore",
        "ci",
        "comment",
        "docs",
        "feat",
        "fix",
        "init",
        "perf",
        "refactor",
        "revert",
        "style",
        "test",
    }
)
MAX_SUMMARY_LENGTH = 50
MAX_BODY_LINE_LENGTH = 72

_CONVENTIONAL_SUBJECT = re.compile(
    r"(?P<type>[^\s():]+)(?:\((?P<scope>[^()\r\n]+)\))?: "
    r"(?P<summary>[^\r\n]+)"
)
_SCOPE = re.compile(
    r"[A-Za-z0-9][A-Za-z0-9._-]*" r"(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*"
)
_PR_NUMBER_SUFFIX = re.compile(r" \(#\d+\)$")
_TRAILER = re.compile(r"(?P<token>[A-Za-z][A-Za-z0-9 -]*): (?P<value>\S.*)")
_ISSUE_REFERENCE = re.compile(r"(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#\d+")
_ISSUE_TRAILERS = frozenset(
    {"resolves", "closes", "fixes", "see also", "ref", "related to"}
)
_HANGUL = re.compile(r"[\u1100-\u11ff\u3130-\u318f\uac00-\ud7a3]")
_GENERATED_MERGE_SUBJECTS = (
    re.compile(r"Merge pull request #\d+ from \S+"),
    re.compile(r"Merge commit '[0-9a-fA-F]{7,40}' into \S+"),
    re.compile(
        r"Merge (?:branch|remote-tracking branch) '[^']+'"
        r"(?: of \S+)?(?: into \S+)?"
    ),
)


def is_generated_merge_subject(subject: str) -> bool:
    """Return whether *subject* has a known Git/GitHub generated merge form."""

    return any(
        pattern.fullmatch(subject) for pattern in _GENERATED_MERGE_SUBJECTS
    )


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
        return [
            "The commit subject must use "
            "'type(optional-scope): Korean summary'."
        ]

    violations = []
    commit_type = match.group("type")
    scope = match.group("scope")
    summary = match.group("summary")
    if commit_type not in ALLOWED_TYPES:
        violations.append(f"Unsupported commit type: {commit_type}")
    if scope is not None and not _SCOPE.fullmatch(scope):
        violations.append(
            "The optional scope must be a domain name such as "
            "'release' or 'test/release'."
        )
    if summary != summary.strip():
        violations.append(
            "The summary must not have leading or trailing whitespace."
        )
    suffix = _PR_NUMBER_SUFFIX.search(summary)
    description = summary[: suffix.start()] if suffix else summary
    if len(description) > MAX_SUMMARY_LENGTH:
        violations.append(
            f"The summary must be {MAX_SUMMARY_LENGTH} characters or fewer."
        )
    if description.endswith((".", "。", "．")):
        violations.append("The summary must not end with a period.")
    if not _HANGUL.search(description):
        violations.append("The summary must include Korean text.")
    return violations


def validate_message(message: str) -> list[str]:
    """Validate a full message, including deterministic body constraints."""

    if not message:
        return ["The commit message is empty."]
    normalized = message.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    subject = lines[0]
    violations = validate_subject(subject)
    if is_generated_merge_subject(subject):
        return violations

    payload = lines[1:]
    while payload and not payload[-1]:
        payload.pop()
    if not payload:
        return violations
    if payload[0]:
        violations.append(
            "The commit body or footers must be separated from the subject "
            "by one blank line."
        )
        body_and_footers = payload
    else:
        body_and_footers = payload[1:]

    footer_start = len(body_and_footers)
    while footer_start and _TRAILER.fullmatch(
        body_and_footers[footer_start - 1]
    ):
        footer_start -= 1
    has_footer_block = footer_start < len(body_and_footers) and (
        footer_start == 0 or not body_and_footers[footer_start - 1]
    )
    if not has_footer_block:
        footer_start = len(body_and_footers)

    for line in body_and_footers[:footer_start]:
        if len(line) > MAX_BODY_LINE_LENGTH:
            violations.append(
                "Each commit body line must be "
                f"{MAX_BODY_LINE_LENGTH} characters or fewer."
            )
            break

    for line in body_and_footers[footer_start:]:
        match = _TRAILER.fullmatch(line)
        if match is None:
            continue
        token = " ".join(match.group("token").casefold().split())
        if token in _ISSUE_TRAILERS and not _ISSUE_REFERENCE.fullmatch(
            match.group("value")
        ):
            violations.append(
                f"Issue footer {match.group('token')!r} must reference "
                "one issue such as '#123'."
            )
    return violations


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--subject", help="commit subject to validate")
    source.add_argument(
        "--message-file",
        type=Path,
        help="full commit-message file to validate",
    )
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
