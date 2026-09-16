#!/usr/bin/env python3
"""Validate SIDEY pull request bodies against repository templates."""

from __future__ import annotations

from pathlib import Path
import re

GENERAL_TEMPLATE = Path(".github/PULL_REQUEST_TEMPLATE/general.md")
GENERAL_MARKER = "<!-- SIDEY_GENERAL_PR_TEMPLATE: keep -->"
CHARACTER_ASSET_TEMPLATE = Path(
    ".github/PULL_REQUEST_TEMPLATE/character_asset.md"
)
CHARACTER_ASSET_MARKER = "<!-- SIDEY_CHARACTER_ASSET_PR_TEMPLATE: keep -->"


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


def is_character_asset_change(paths: list[str]) -> bool:
    """Return whether a diff must use the character asset template."""

    return any(
        path.startswith(("assets/v1/characters/", "assets/v1/throwables/"))
        for path in paths
    )


def required_template_for_paths(paths: list[str]) -> str:
    """Return the pull request template required by the changed paths."""

    return "character_asset" if is_character_asset_change(paths) else "general"


def validate_pr_body(
    root: Path,
    body: str,
    paths: list[str],
    *,
    label: str = "PR body",
) -> str:
    """Validate *body* and return the selected template name."""

    marker_counts = {
        "general": body.count(GENERAL_MARKER),
        "character_asset": body.count(CHARACTER_ASSET_MARKER),
    }
    if any(count > 1 for count in marker_counts.values()):
        raise PullRequestValidationError(
            f"{label} contains a duplicated pull request template marker"
        )
    selected = [name for name, count in marker_counts.items() if count == 1]
    if len(selected) != 1:
        raise PullRequestValidationError(
            f"{label} must preserve exactly one SIDEY pull request template "
            "marker"
        )

    template_name = selected[0]
    required_template = required_template_for_paths(paths)
    if template_name != required_template:
        required_path = (
            CHARACTER_ASSET_TEMPLATE
            if required_template == "character_asset"
            else GENERAL_TEMPLATE
        )
        raise PullRequestValidationError(f"{label} must use {
                required_path.as_posix()} for the changed paths")

    if template_name == "general":
        template_path = GENERAL_TEMPLATE
        marker = GENERAL_MARKER
    else:
        template_path = CHARACTER_ASSET_TEMPLATE
        marker = CHARACTER_ASSET_MARKER

    template = _read_template(root, template_path, marker)
    _validate_sections(body, _headings(template, template_path), label)
    return template_name
