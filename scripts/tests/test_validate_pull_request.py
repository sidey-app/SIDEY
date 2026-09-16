import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))

from validate_pull_request import (  # noqa: E402
    CHARACTER_ASSET_MARKER,
    GENERAL_MARKER,
    PullRequestValidationError,
    is_character_asset_change,
    validate_pr_body,
)


class PullRequestValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        templates = self.root / '.github/PULL_REQUEST_TEMPLATE'
        templates.mkdir(parents=True)
        (templates / 'general.md').write_text(
            f'{GENERAL_MARKER}\n\n'
            '## Type\n\n- [ ] Shared\n\n'
            '## Changes\n\nDescribe the change.\n\n'
            '## Validation\n\nList checks.\n',
            encoding='utf-8',
        )
        (templates / 'character_asset.md').write_text(
            f'{CHARACTER_ASSET_MARKER}\n\n'
            '# Character asset PR\n\n'
            '## Asset details\n\nDescribe the asset.\n\n'
            '## Checklist\n\n- [ ] Validated\n',
            encoding='utf-8',
        )

    def body(self, name):
        return (
            self.root / f'.github/PULL_REQUEST_TEMPLATE/{name}.md'
        ).read_text(encoding='utf-8')

    def test_general_template_is_valid_for_any_change(self):
        self.assertEqual(
            validate_pr_body(
                self.root,
                self.body('general'),
                ['windows/src/App.cs'],
            ),
            'general',
        )

    def test_character_template_is_valid_only_for_asset_only_change(self):
        paths = [
            'assets/v1/characters/capybara/idle.png',
            'assets/v1/manifest.json',
        ]
        self.assertTrue(is_character_asset_change(paths))
        self.assertEqual(
            validate_pr_body(
                self.root,
                self.body('character_asset'),
                paths,
            ),
            'character_asset',
        )

    def test_character_template_rejects_mixed_or_non_character_change(self):
        for paths in (
            ['assets/v1/manifest.json'],
            [
                'assets/v1/characters/capybara/idle.png',
                'scripts/validate_pixel_assets.py',
            ],
        ):
            with self.subTest(paths=paths), self.assertRaisesRegex(
                PullRequestValidationError,
                'allowed only',
            ):
                validate_pr_body(
                    self.root,
                    self.body('character_asset'),
                    paths,
                )

    def test_missing_or_multiple_markers_are_rejected(self):
        with self.assertRaisesRegex(
            PullRequestValidationError,
            'exactly one',
        ):
            validate_pr_body(self.root, '## Type\n', ['docs/guide.md'])
        with self.assertRaisesRegex(
            PullRequestValidationError,
            'exactly one',
        ):
            validate_pr_body(
                self.root,
                self.body('general') + self.body('character_asset'),
                ['assets/v1/characters/capybara/idle.png'],
            )

    def test_missing_or_reordered_sections_are_rejected(self):
        body = self.body('general')
        with self.assertRaisesRegex(
            PullRequestValidationError,
            'Changes',
        ):
            validate_pr_body(
                self.root,
                body.replace('## Changes', '## Change'),
                ['docs/guide.md'],
            )
        reordered = body.replace(
            '## Type\n\n- [ ] Shared\n\n## Changes',
            '## Changes\n\nDescribe the change.\n\n## Type',
        )
        with self.assertRaisesRegex(
            PullRequestValidationError,
            'section order',
        ):
            validate_pr_body(self.root, reordered, ['docs/guide.md'])


if __name__ == '__main__':
    unittest.main()
