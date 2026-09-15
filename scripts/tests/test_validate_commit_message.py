import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "validate_commit_message", Path(__file__).parents[1] / "validate_commit_message.py"
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

ROOT = Path(__file__).parents[2]


class CommitMessageValidatorTests(unittest.TestCase):
    def test_accepts_each_supported_type_and_scope(self):
        for commit_type in validator.ALLOWED_TYPES:
            with self.subTest(commit_type=commit_type):
                self.assertEqual(
                    validator.validate_subject(f"{commit_type}(Shared): 기여자 계약 정리"), []
                )
        for scope in validator.ALLOWED_SCOPES:
            with self.subTest(scope=scope):
                self.assertEqual(
                    validator.validate_subject(f"chore({scope}): 검증 계약 정리"), []
                )

    def test_rejects_invalid_type(self):
        violations = validator.validate_subject("feature(Shared): 기여자 계약 정리")
        self.assertTrue(any("type" in violation for violation in violations))

    def test_rejects_invalid_scope(self):
        violations = validator.validate_subject("chore(shared): 기여자 계약 정리")
        self.assertTrue(any("scope" in violation for violation in violations))

    def test_rejects_malformed_or_non_korean_subject(self):
        self.assertTrue(validator.validate_subject("chore Shared: 기여자 계약 정리"))
        self.assertTrue(validator.validate_subject("chore(Shared): contributor contract"))
        self.assertTrue(validator.validate_subject("chore(Shared): 기여자 계약 정리 "))

    def test_full_message_ignores_body_and_attribution_trailers(self):
        message = (
            "chore(Shared): 커밋 검증기 추가\n\n"
            "Body prose is intentionally outside the deterministic validator.\n\n"
            "Co-authored-by: codex <codex@openai.com>\n"
        )
        self.assertEqual(validator.validate_message(message), [])

    def test_accepts_known_generated_merge_subjects(self):
        subjects = (
            "Merge pull request #115 from sidey-app/windows/ci-runtime-windows",
            "Merge commit 'e4458779167777e95cc2636047f241a595386c30' into windows/ci-runtime-windows",
            "Merge branch 'main' into shared/example",
            "Merge remote-tracking branch 'origin/main' into windows/example",
        )
        for subject in subjects:
            with self.subTest(subject=subject):
                self.assertEqual(validator.validate_subject(subject), [])

    def test_does_not_exempt_explicit_legacy_release_subject(self):
        self.assertTrue(
            validator.validate_subject("Publish Sparkle appcast for v1.2.3")
        )

    def test_macos_appcast_uses_a_valid_sidey_commit_and_pr_subject(self):
        script = (ROOT / "scripts/release_macos.sh").read_text(encoding="utf-8")
        subject = "build(Shared): macOS v1.2.3 Sparkle appcast 갱신"

        self.assertEqual(validator.validate_subject(subject), [])
        self.assertIn(
            'SIDEY_APPCAST_SUBJECT="build(Shared): macOS $SIDEY_TAG Sparkle appcast 갱신"',
            script,
        )
        self.assertIn('commit -m "$SIDEY_APPCAST_SUBJECT"', script)
        self.assertIn('--title "$SIDEY_APPCAST_SUBJECT"', script)

    def test_external_homebrew_release_subject_is_not_sidey_compliant(self):
        # The release script commits this in the separate Homebrew tap repository,
        # outside this repository validator's enforcement boundary.
        self.assertTrue(validator.validate_subject("Update SIDEY to 1.2.3"))


if __name__ == "__main__":
    unittest.main()
