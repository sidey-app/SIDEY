import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / 'skills'))
from workflow import WorkflowError
from validate_change import (
    commit_messages,
    resolve_change,
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
        with patch('validate_change.git', return_value=output):
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
                ['scripts/release_macos.sh'],
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

    def test_edited_pr_revalidates_policy_without_scheduling_heavy_jobs(self):
        event = {
            'action': 'edited',
            'pull_request': {
                'base': {'sha': 'base'},
                'head': {'sha': 'head', 'ref': 'shared/task'},
                'title': 'docs: update policy',
                'body': 'body',
                'labels': [],
            },
        }
        with (
            patch('validate_change.changed_paths', return_value=['docs/guide.md']),
            patch('validate_change.commit_messages', return_value=['docs: update policy']),
            patch('validate_change.verify_commit_contract') as commits,
            patch('validate_change.verify_pr_contract') as body,
            patch('validate_change.validate_pr_paths') as paths,
            patch('validate_change.required_scopes') as scopes,
        ):
            result = resolve_change(Path('.'), event)
        self.assertEqual(result['scopes'], [])
        commits.assert_called_once_with(['docs: update policy'], 'docs: update policy')
        body.assert_called_once_with(Path('.'), 'body', ['docs/guide.md'])
        paths.assert_called_once_with('shared/task', ['docs/guide.md'])
        scopes.assert_not_called()

    def test_normal_pr_emits_resolved_scopes(self):
        event = {
            'action': 'synchronize',
            'pull_request': {
                'base': {'sha': 'base'},
                'head': {'sha': 'head', 'ref': 'windows/task'},
                'title': 'fix(Windows): update app',
                'body': 'body',
                'labels': [],
            },
        }
        with (
            patch('validate_change.changed_paths', return_value=['windows/SIDEY/App.xaml.cs']),
            patch('validate_change.commit_messages', return_value=[]),
            patch('validate_change.verify_commit_contract'),
            patch('validate_change.verify_pr_contract'),
            patch('validate_change.validate_pr_paths'),
            patch('validate_change.required_scopes', return_value=['shared', 'windows']) as scopes,
        ):
            result = resolve_change(Path('.'), event)
        self.assertEqual(result['scopes'], ['shared', 'windows'])
        scopes.assert_called_once_with(['windows/SIDEY/App.xaml.cs'])

    def test_empty_edited_scope_requires_only_scope_job(self):
        verify_gate([], {
            'scope': {'result': 'success'},
            'shared': {'result': 'skipped'},
            'windows': {'result': 'skipped'},
        })

    def test_scope_failure_never_passes_empty_requirements(self):
        with self.assertRaises(WorkflowError):
            verify_gate([], {'scope': {'result': 'failure'}, 'shared': {'result': 'success'}})
