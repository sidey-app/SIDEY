#!/usr/bin/env python3
"""Validate structural invariants of SIDEY's local contributor instructions.

This validator deliberately checks only facts that can be established from the
repository tree.  It does not judge whether a skill is useful, whether prose is
good, or whether a referenced workflow is appropriate for a task.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys
from typing import Iterable, Sequence


ROOT = Path(__file__).resolve().parent.parent

# This is a user-installed, non-project skill referenced only as an optional
# follow-up.  Project-local skill references must otherwise resolve locally.
EXTERNAL_SKILL_REFERENCES = frozenset({"humanize-korean"})
RETIRED_SKILL_NAMES = frozenset(
    {
        "sidey-commit",
        "sidey-public-web",
        "sidey-release-docs",
        "sidey-versioning",
        "sidey-workflow",
        "windows-code-review",
        "windows-dev-docs",
        "windows-tests",
        "native-code-review",
        "native-dev-docs",
        "native-tests",
    }
)

IGNORED_DIRECTORIES = frozenset(
    {
        ".git",
        ".idea",
        ".swiftpm",
        ".vs",
        ".vscode",
        "DerivedData",
        "artifacts",
        "bin",
        "build",
        "node_modules",
        "obj",
    }
)

NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MARKDOWN_LINK_PATTERN = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
SCRIPT_REFERENCE_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_./-])((?:\./)?scripts/[A-Za-z0-9_./-]+\.(?:py|ps1|psd1|psm1|sh))"
)
SKILL_REFERENCE_PATTERN = re.compile(r"(?<![A-Za-z0-9_-])\$([a-z0-9]+(?:-[a-z0-9]+)+)\b")
SKILL_PATH_PATTERN = re.compile(
    r"\.agents[/\\]skills[/\\]([A-Za-z0-9_-]+)[/\\]SKILL\.md\b"
)
FRONTMATTER_FIELD_PATTERN = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$")


@dataclass(frozen=True, order=True)
class Violation:
    """One deterministic contributor-architecture violation."""

    code: str
    path: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}: [{self.code}] {self.message}"


@dataclass(frozen=True)
class Skill:
    path: Path
    relative_path: str
    relative_directory: str
    name: str | None
    description: str | None


def _is_ignored(path: Path, root: Path) -> bool:
    relative = path.relative_to(root)
    return any(part in IGNORED_DIRECTORIES for part in relative.parts)


def _repository_files(root: Path, filename: str) -> list[Path]:
    return sorted(
        path
        for path in root.rglob(filename)
        if path.is_file() and not _is_ignored(path, root)
    )


def _repository_tree_files(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and not _is_ignored(path, root)
    )


def _validate_nested_skill_paths(root: Path) -> list[Violation]:
    violations: list[Violation] = []
    for path in _repository_tree_files(root):
        relative = path.relative_to(root)
        parts = relative.parts
        nested = any(
            parts[index : index + 2] == (".agents", "skills")
            for index in range(1, len(parts) - 1)
        )
        if nested:
            violations.append(
                Violation(
                    "unexpected-nested-skills-path",
                    relative.as_posix(),
                    "repository-local skill files must live below the root .agents/skills directory",
                )
            )
    return violations


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def _frontmatter(path: Path) -> tuple[dict[str, str], str | None]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, "SKILL.md must begin with YAML frontmatter"

    try:
        end = next(index for index, line in enumerate(lines[1:], 1) if line.strip() == "---")
    except StopIteration:
        return {}, "SKILL.md frontmatter is missing its closing ---"

    fields: dict[str, str] = {}
    for line in lines[1:end]:
        match = FRONTMATTER_FIELD_PATTERN.match(line)
        if match:
            fields[match.group(1)] = _unquote(match.group(2))
    return fields, None


def _discover_skills(root: Path) -> tuple[list[Skill], list[Violation]]:
    skills: list[Skill] = []
    violations: list[Violation] = []

    for path in _repository_files(root, "SKILL.md"):
        relative_path = path.relative_to(root).as_posix()
        relative_directory = path.parent.relative_to(root).as_posix()
        fields, frontmatter_error = _frontmatter(path)
        if frontmatter_error:
            violations.append(Violation("invalid-frontmatter", relative_path, frontmatter_error))

        name = fields.get("name") or None
        description = fields.get("description") or None
        skill = Skill(path, relative_path, relative_directory, name, description)
        skills.append(skill)

        canonical_location = (
            len(path.relative_to(root).parts) == 4
            and path.relative_to(root).parts[:2] == (".agents", "skills")
            and path.name == "SKILL.md"
        )
        if not canonical_location:
            violations.append(
                Violation(
                    "unexpected-skill-location",
                    relative_path,
                    "repository-local skills must be direct children of .agents/skills",
                )
            )

        if not name:
            violations.append(Violation("missing-skill-name", relative_path, "frontmatter name is required"))
        elif not NAME_PATTERN.fullmatch(name):
            violations.append(
                Violation("invalid-skill-name", relative_path, f"frontmatter name is not kebab-case: {name!r}")
            )
        elif name != path.parent.name:
            violations.append(
                Violation(
                    "skill-directory-name-mismatch",
                    relative_path,
                    f"frontmatter name {name!r} must match directory {path.parent.name!r}",
                )
            )

        if not description:
            violations.append(
                Violation("missing-skill-description", relative_path, "frontmatter description is required")
            )

    names: dict[str, list[Skill]] = {}
    for skill in skills:
        if skill.name:
            names.setdefault(skill.name, []).append(skill)
    for name, matching in names.items():
        if len(matching) > 1:
            locations = ", ".join(skill.relative_path for skill in matching)
            for skill in matching:
                violations.append(
                    Violation(
                        "duplicate-skill-name",
                        skill.relative_path,
                        f"skill name {name!r} is also declared at: {locations}",
                    )
                )

    return skills, violations


def _yaml_scalar(source: str, key: str) -> str | None:
    match = re.search(rf"^\s*{re.escape(key)}:\s*(.*?)\s*$", source, re.MULTILINE)
    return _unquote(match.group(1)) if match else None


def _validate_openai_metadata(
    root: Path,
    skills: Iterable[Skill],
) -> list[Violation]:
    violations: list[Violation] = []
    for skill in skills:
        metadata = skill.path.parent / "agents" / "openai.yaml"
        if not metadata.is_file():
            violations.append(
                Violation(
                    "missing-openai-metadata",
                    metadata.relative_to(root).as_posix(),
                    "every repository-local skill must provide agents/openai.yaml",
                )
            )
            continue

        relative = metadata.relative_to(root).as_posix()
        source = metadata.read_text(encoding="utf-8")
        prompt = _yaml_scalar(source, "default_prompt")
        expected = f"${skill.name}" if skill.name else None
        if not prompt or not expected or re.search(
            rf"(?<![A-Za-z0-9_-]){re.escape(expected)}(?![A-Za-z0-9_-])", prompt
        ) is None:
            violations.append(
                Violation(
                    "openai-skill-name-mismatch",
                    relative,
                    f"default_prompt must invoke the owning skill as {expected or '$<skill-name>'}",
                )
            )

        policy = _yaml_scalar(source, "allow_implicit_invocation")
        if policy not in {"true", "false"}:
            violations.append(
                Violation(
                    "missing-implicit-invocation-policy",
                    relative,
                    "agents/openai.yaml must explicitly set allow_implicit_invocation to true or false",
                )
            )

    expected_metadata = {
        (skill.path.parent / "agents" / "openai.yaml").resolve()
        for skill in skills
    }
    canonical_root = root / ".agents" / "skills"
    if canonical_root.is_dir():
        for metadata in sorted(canonical_root.rglob("openai.yaml")):
            if (
                metadata.is_file()
                and not _is_ignored(metadata, root)
                and metadata.resolve() not in expected_metadata
            ):
                violations.append(
                    Violation(
                        "orphan-openai-metadata",
                        metadata.relative_to(root).as_posix(),
                        "agents/openai.yaml has no owning SKILL.md",
                    )
                )
    return violations


def _markdown_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        return target[1:target.index(">")]
    return target.split(maxsplit=1)[0] if target else ""


def _relative_link_violations(
    path: Path,
    root: Path,
) -> list[Violation]:
    relative_source = path.relative_to(root).as_posix()
    source = path.read_text(encoding="utf-8")
    violations: list[Violation] = []

    for match in MARKDOWN_LINK_PATTERN.finditer(source):
        target = _markdown_target(match.group(1))
        if not target or target.startswith("#") or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
            continue

        target_without_suffix = target.split("#", 1)[0].split("?", 1)[0]
        if not target_without_suffix:
            continue
        resolved = (path.parent / target_without_suffix).resolve()
        try:
            resolved.relative_to(root.resolve())
        except ValueError:
            violations.append(
                Violation(
                    "relative-link-outside-repository",
                    relative_source,
                    f"relative Markdown link leaves the repository: {target}",
                )
            )
            continue
        if not resolved.exists():
            violations.append(
                Violation(
                    "missing-relative-link",
                    relative_source,
                    f"relative Markdown link target does not exist: {target}",
                )
            )
    return violations


def _source_documents(root: Path, skills: Iterable[Skill]) -> list[Path]:
    documents = set(_repository_files(root, "AGENTS.md"))
    for skill in skills:
        documents.update(
            path
            for path in skill.path.parent.rglob("*.md")
            if path.is_file() and not _is_ignored(path, root)
        )
    return sorted(documents)


def _architecture_sources(root: Path, skills: Iterable[Skill]) -> list[Path]:
    sources = set(_source_documents(root, skills))
    for skill in skills:
        metadata = skill.path.parent / "agents" / "openai.yaml"
        if metadata.is_file():
            sources.add(metadata)
    return sorted(sources)


def _validate_references(
    root: Path,
    skills: Iterable[Skill],
) -> list[Violation]:
    violations: list[Violation] = []
    skill_names = {skill.name for skill in skills if skill.name}

    for path in _architecture_sources(root, skills):
        relative = path.relative_to(root).as_posix()
        source = path.read_text(encoding="utf-8")
        if path.suffix == ".md":
            violations.extend(_relative_link_violations(path, root))

        for retired_name in RETIRED_SKILL_NAMES:
            if re.search(
                rf"(?<![A-Za-z0-9_-]){re.escape(retired_name)}(?![A-Za-z0-9_-])",
                source,
            ):
                violations.append(
                    Violation(
                        "retired-skill-reference",
                        relative,
                        f"active contributor architecture references retired skill {retired_name!r}",
                    )
                )

        for referenced_name in sorted(set(SKILL_PATH_PATTERN.findall(source))):
            target = root / ".agents" / "skills" / referenced_name / "SKILL.md"
            if referenced_name not in skill_names or not target.is_file():
                violations.append(
                    Violation(
                        "missing-skill-path-reference",
                        relative,
                        "referenced canonical skill target does not exist: "
                        f".agents/skills/{referenced_name}/SKILL.md",
                    )
                )

        for script in sorted(set(SCRIPT_REFERENCE_PATTERN.findall(source))):
            normalized = script[2:] if script.startswith("./") else script
            candidates = [root / normalized]
            parts = path.relative_to(root).parts
            if len(parts) >= 3 and parts[:2] == (".agents", "skills"):
                candidates.insert(0, root.joinpath(*parts[:3], normalized))
            if not any(candidate.is_file() for candidate in candidates):
                violations.append(
                    Violation(
                        "missing-script-reference",
                        relative,
                        f"referenced repository script does not exist: {script}",
                    )
                )

        for reference in sorted(set(SKILL_REFERENCE_PATTERN.findall(source))):
            if reference not in skill_names and reference not in EXTERNAL_SKILL_REFERENCES:
                violations.append(
                    Violation(
                        "missing-skill-reference",
                        relative,
                        f"referenced skill is neither project-local nor an allowed external skill: ${reference}",
                    )
                )
    return violations


def validate_repository(
    root: Path | str = ROOT,
) -> list[Violation]:
    """Return every structural violation found below *root*."""

    repository_root = Path(root).resolve()
    skills, violations = _discover_skills(repository_root)
    violations.extend(_validate_nested_skill_paths(repository_root))
    violations.extend(_validate_openai_metadata(repository_root, skills))
    violations.extend(_validate_references(repository_root, skills))
    return sorted(set(violations))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help="repository root to audit (defaults to this script's repository)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    violations = validate_repository(arguments.root)
    if violations:
        for violation in violations:
            print(violation, file=sys.stderr)
        print(f"Contributor architecture validation failed ({len(violations)} violation(s)).", file=sys.stderr)
        return 1

    print("Contributor architecture validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
