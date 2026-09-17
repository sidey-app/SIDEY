#!/usr/bin/env python3
"""Validate SIDEY pull request bodies against repository templates."""

from __future__ import annotations

from pathlib import Path
import re

GENERAL_TEMPLATE = Path(".github/PULL_REQUEST_TEMPLATE/general.md")
GENERAL_MARKER = "<!-- SIDEY_GENERAL_PR_TEMPLATE: keep -->"


class PullRequestValidationError(ValueError):
    """Raised when a pull request body does not follow an allowed template."""


def _read_template(root: Path, path: Path, marker: str) -> str:
    try:
        template = (root / path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise PullRequestValidationError(
            f"Cannot read {path.as_posix()} as UTF-8: {error}"
        ) from error
    if template.count(marker) != 1:
        raise PullRequestValidationError(
            f"{path.as_posix()} must contain its hidden marker exactly once"
        )
    return template


def _headings(template: str, path: Path) -> list[str]:
    headings = re.findall(r"^## .+$", template, re.MULTILINE)
    if not headings:
        raise PullRequestValidationError(
            f"{path.as_posix()} has no required sections"
        )
    return headings


def _validate_sections(body: str, headings: list[str], label: str) -> None:
    lines = body.replace("\r\n", "\n").replace("\r", "\n").splitlines()
    positions = []
    for heading in headings:
        matching = [
            index for index, line in enumerate(lines) if line == heading
        ]
        if len(matching) != 1:
            raise PullRequestValidationError(
                f"{label} must contain one exact {heading!r} section"
            )
        positions.append(matching[0])
    if positions != sorted(positions):
        raise PullRequestValidationError(
            f"{label} must preserve the selected template section order"
        )


def validate_pr_body(
    root: Path,
    body: str,
    paths: list[str],
    *,
    label: str = "PR body",
) -> str:
    """Validate the general template for every changed-path set."""

    if "<!-- SIDEY_CHARACTER_ASSET_PR_TEMPLATE: keep -->" in body:
        raise PullRequestValidationError(
            f"{label} uses a retired asset template; use "
            f"{GENERAL_TEMPLATE.as_posix()}"
        )
    marker_count = body.count(GENERAL_MARKER)
    if marker_count > 1:
        raise PullRequestValidationError(
            f"{label} contains a duplicated pull request template marker"
        )
    if marker_count != 1:
        raise PullRequestValidationError(
            f"{label} must preserve exactly one SIDEY pull request template "
            "marker"
        )

    template = _read_template(root, GENERAL_TEMPLATE, GENERAL_MARKER)
    _validate_sections(body, _headings(template, GENERAL_TEMPLATE), label)
    return "general"
