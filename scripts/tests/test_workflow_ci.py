import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / 'skills'))
from workflow import WorkflowError
from workflow_ci import (
    commit_messages,
    verify_commit_contract,
    verify_gate,
    verify_pr_contract,
    validate_pr_paths,
)


class GateTests(unittest.TestCase):
    def test_commit_messages_preserve_bodies_and_remove_record_newlines(self):
        output = (
            'fix: 첫 번째 변경\n\n변경 이유를 설명해요.\x00\n'
            "Merge branch 'main' into shared/task\x00\n"
        )
        with patch('workflow_ci.git', return_value=output):
            self.assertEqual(
                commit_messages(Path('.'), 'base', 'head'),
                [
                    'fix: 첫 번째 변경\n\n변경 이유를 설명해요.',
                    "Merge branch 'main' into shared/task",
                ],
            )

    def test_new_commit_range_and_pr_title_follow_policy(self):
        verify_commit_contract(
            [
                'chore(commit): 기여자 구조 정리',
                "Merge branch 'main' into shared/contributor-architecture",
            ],
            'chore(commit): AI 기여자 구조 최종화',
        )

    def test_invalid_new_commit_or_pr_title_fails_gate(self):
        with self.assertRaisesRegex(WorkflowError, 'commit subject'):
            verify_commit_contract(['Contributor architecture cleanup'])
        with self.assertRaisesRegex(WorkflowError, 'PR title'):
            verify_commit_contract(
                ['chore(commit): 기여자 구조 정리'],
                'Contributor architecture cleanup',
            )

    def test_long_new_commit_body_fails_gate(self):
        message = f"docs: 규칙 추가\n\n{'가' * 73}"
        with self.assertRaisesRegex(WorkflowError, 'commit message'):
            verify_commit_contract([message])

    def test_manual_pr_body_must_use_repository_template(self):
        root = Path(__file__).parents[2]
        body = (root / '.github/PULL_REQUEST_TEMPLATE/general.md').read_text(
            encoding='utf-8'
        )
        self.assertEqual(
            verify_pr_contract(root, body, ['docs/guide.md']),
            'general',
        )
        with self.assertRaisesRegex(WorkflowError, 'template validation'):
            verify_pr_contract(root, '## 변경 내용\n', ['docs/guide.md'])

    def test_character_asset_pr_must_use_character_template(self):
        root = Path(__file__).parents[2]
        template_directory = root / '.github/PULL_REQUEST_TEMPLATE'
        character_body = (template_directory / 'character_asset.md').read_text(
            encoding='utf-8'
        )
        general_body = (template_directory / 'general.md').read_text(
            encoding='utf-8'
        )
        paths = ['assets/v1/characters/capybara/idle.png']
        self.assertEqual(
            verify_pr_contract(root, character_body, paths),
            'character_asset',
        )
        with self.assertRaisesRegex(WorkflowError, 'character_asset.md'):
            verify_pr_contract(root, general_body, paths)

    def test_shared_branch_cannot_cross_platform_boundary(self):
        with self.assertRaisesRegex(WorkflowError, 'platform boundary'):
            validate_pr_paths(
                'shared/script-relocation',
                ['scripts/macos/release_macos.sh'],
                [],
            )

    def test_required_job_cannot_be_skipped_missing_cancelled_or_failed(self):
        for status in ('skipped', 'failure', 'cancelled', None):
            needs = {'scope': {'result': 'success'}, 'shared': {'result': 'success'}}
            if status:
                needs['macos'] = {'result': status}
            with self.assertRaises(WorkflowError):
                verify_gate(['shared', 'macos'], needs)

    def test_unaffected_platform_may_skip(self):
        verify_gate(['shared'], {'scope': {'result': 'success'}, 'shared': {'result': 'success'},
                                  'windows': {'result': 'skipped'}})

    def test_scope_failure_never_passes_empty_requirements(self):
        with self.assertRaises(WorkflowError):
            verify_gate([], {'scope': {'result': 'failure'}, 'shared': {'result': 'success'}})
