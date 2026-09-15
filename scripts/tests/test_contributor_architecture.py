"""Tests for deterministic contributor-architecture validation."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))

from validate_contributor_architecture import validate_repository


class ContributorArchitectureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sidey-contributor-architecture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative: str, source: str = "") -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")
        return path

    def add_skill(
        self,
        name: str,
        *,
        directory: str | None = None,
        description: str = "Perform a bounded specialist task and produce evidence.",
        metadata: bool = True,
        implicit_policy: str | None = "true",
        default_prompt_name: str | None = None,
        body: str = "# Skill\n",
    ) -> Path:
        directory = directory or f".agents/skills/{name}"
        skill = self.write(
            f"{directory}/SKILL.md",
            f"---\nname: {name}\ndescription: {description}\n---\n\n{body}",
        )
        if metadata:
            invoked_name = default_prompt_name or name
            policy = (
                f"\npolicy:\n  allow_implicit_invocation: {implicit_policy}\n"
                if implicit_policy is not None
                else "\n"
            )
            self.write(
                f"{directory}/agents/openai.yaml",
                "interface:\n"
                f"  display_name: \"{name}\"\n"
                f"  default_prompt: \"Use ${invoked_name} for this task.\"\n"
                f"{policy}",
            )
        return skill

    def codes(self) -> list[str]:
        return [violation.code for violation in validate_repository(self.root)]

    def test_valid_skill_metadata(self):
        self.add_skill("sample-skill")
        self.assertEqual(validate_repository(self.root), [])

    def test_required_frontmatter_fields_are_reported(self):
        self.write(".agents/skills/missing-fields/SKILL.md", "---\n---\n\n# Skill\n")
        codes = self.codes()
        self.assertIn("missing-skill-name", codes)
        self.assertIn("missing-skill-description", codes)

    def test_duplicate_skill_name(self):
        self.add_skill("same-name")
        self.add_skill("same-name", directory=".agents/skills/other-directory")
        self.assertIn("duplicate-skill-name", self.codes())

    def test_directory_and_frontmatter_name_must_match(self):
        self.add_skill("declared-name", directory=".agents/skills/directory-name")
        self.assertIn("skill-directory-name-mismatch", self.codes())

    def test_missing_relative_markdown_link_and_script_are_reported(self):
        self.add_skill(
            "broken-references",
            body=(
                "# Broken references\n\n"
                "Read [missing guidance](references/missing.md).\n"
                "Run `python3 scripts/missing_validator.py`.\n"
            ),
        )
        self.assertIn("missing-relative-link", self.codes())
        self.assertIn("missing-script-reference", self.codes())

    def test_legacy_nested_windows_skill_is_rejected(self):
        self.add_skill("code-review", directory="windows/.agents/skills/code-review")
        self.assertIn("unexpected-skill-location", self.codes())

    def test_new_nested_skill_is_rejected(self):
        self.add_skill("new-skill", directory="windows/.agents/skills/new-skill")
        self.assertIn("unexpected-skill-location", self.codes())

    def test_missing_windows_routing_targets_are_reported(self):
        self.write(
            "AGENTS.md",
            "Read [Windows instructions](windows/AGENTS.md) and "
            "[Windows docs instructions](windows/docs/AGENTS.md).\n",
        )
        self.assertIn("missing-relative-link", self.codes())

    def test_other_missing_agents_routing_target_is_always_reported(self):
        self.write("AGENTS.md", "Read [missing instructions](platform/AGENTS.md).\n")
        self.assertIn("missing-relative-link", self.codes())

    def test_openai_default_prompt_must_match_skill_name(self):
        self.add_skill("right-name", default_prompt_name="wrong-name")
        self.assertIn("openai-skill-name-mismatch", self.codes())

    def test_dangling_project_skill_reference_is_reported(self):
        self.add_skill("calling-skill", body="# Skill\n\nAlso use `$missing-skill`.\n")
        self.assertIn("missing-skill-reference", self.codes())

    def test_metadata_requires_explicit_implicit_invocation_policy(self):
        self.add_skill("missing-policy", implicit_policy=None)
        self.assertIn("missing-implicit-invocation-policy", self.codes())

    def test_legacy_write_docs_metadata_requires_invocation_policy(self):
        self.add_skill(
            "write-docs",
            directory="windows/.agents/skills/write-docs",
            implicit_policy=None,
        )
        self.assertIn("missing-implicit-invocation-policy", self.codes())

    def test_canonical_windows_skill_set_is_valid(self):
        for name in (
            "windows-code-review",
            "windows-dev-docs",
            "windows-powershell",
            "windows-tests",
        ):
            self.add_skill(name)
        self.assertEqual(validate_repository(self.root), [])


if __name__ == "__main__":
    unittest.main()
