import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(
    0,
    str(Path(__file__).parents[1] / 'skills' / 'create-pr'),
)

from validate_pull_request import (  # noqa: E402
    GENERAL_MARKER,
    PullRequestValidationError,
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

    def body(self, name):
        return (
            self.root / f'.github/PULL_REQUEST_TEMPLATE/{name}.md'
        ).read_text(encoding='utf-8')

    def test_general_template_accepts_code_and_maintainer_asset_changes(self):
        for paths in (
            ['windows/src/App.cs'],
            ['assets/v1/characters/capybara/idle.png', 'assets/v1/manifest.json'],
            ['assets/v1/throwables/ball/idle.png'],
            ['assets/v1/characters/capybara/idle.png',
             'scripts/validate_pixel_assets.py'],
        ):
            with self.subTest(paths=paths):
                self.assertEqual(
                    validate_pr_body(self.root, self.body('general'), paths),
                    'general',
                )

    def test_retired_asset_marker_is_rejected_alone_or_with_general_body(self):
        marker = '<!-- SIDEY_CHARACTER_ASSET_PR_TEMPLATE: keep -->'
        for body in (marker, self.body('general') + marker):
            with self.subTest(body=body):
                with self.assertRaisesRegex(
                    PullRequestValidationError, 'retired asset template',
                ):
                    validate_pr_body(
                        self.root, body,
                        ['assets/v1/characters/capybara/idle.png'],
                    )

    def test_missing_or_duplicate_markers_are_rejected(self):
        for body, message in (
            ('## Type\n', 'exactly one'),
            (self.body('general') + GENERAL_MARKER, 'duplicated'),
        ):
            with self.subTest(body=body):
                with self.assertRaisesRegex(PullRequestValidationError, message):
                    validate_pr_body(self.root, body, ['docs/guide.md'])

    def test_default_github_template_matches_validated_general_template(self):
        root = Path(__file__).parents[2]
        body = (root / '.github/pull_request_template.md').read_text(
            encoding='utf-8',
        )
        self.assertEqual(
            body,
            (root / '.github/PULL_REQUEST_TEMPLATE/general.md').read_text(
                encoding='utf-8',
            ),
        )
        self.assertEqual(validate_pr_body(root, body, ['docs/guide.md']), 'general')

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
