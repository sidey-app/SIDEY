"""Load policy scripts that live in command-oriented directories."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType


def _load_skill_script(name: str, path: Path) -> ModuleType:
    """Load policy from a directory that is not a Python package."""

    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load skill script: {path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_SKILL_SCRIPTS = Path(__file__).resolve().parents[1]
_commit_policy = _load_skill_script(
    "sidey_validate_commit_message",
    _SKILL_SCRIPTS / "commit" / "validate_commit_message.py",
)
_pull_request_policy = _load_skill_script(
    "sidey_validate_pull_request",
    _SKILL_SCRIPTS / "create-pr" / "validate_pull_request.py",
)

PullRequestValidationError = (
    _pull_request_policy.PullRequestValidationError
)
GENERAL_MARKER = _pull_request_policy.GENERAL_MARKER
GENERAL_TEMPLATE = _pull_request_policy.GENERAL_TEMPLATE
validate_message = _commit_policy.validate_message
validate_subject = _commit_policy.validate_subject
validate_pr_body = _pull_request_policy.validate_pr_body

__all__ = [
    "GENERAL_MARKER",
    "GENERAL_TEMPLATE",
    "PullRequestValidationError",
    "validate_message",
    "validate_pr_body",
    "validate_subject",
]
