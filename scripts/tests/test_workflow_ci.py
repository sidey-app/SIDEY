import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
from workflow import WorkflowError
from workflow_ci import commit_subjects, verify_commit_contract, verify_gate


class GateTests(unittest.TestCase):
    def test_commit_subjects_remove_only_git_record_newlines(self):
        output = 'fix(Shared): 첫 번째 변경  \x00\nMerge branch \'main\' into shared/task\x00\n'
        with patch('workflow_ci.git', return_value=output):
            self.assertEqual(
                commit_subjects(Path('.'), 'base', 'head'),
                ['fix(Shared): 첫 번째 변경  ', "Merge branch 'main' into shared/task"],
            )

    def test_new_commit_range_and_pr_title_follow_policy(self):
        verify_commit_contract(
            [
                'chore(Shared): 기여자 구조 정리',
                "Merge branch 'main' into shared/contributor-architecture",
            ],
            'chore(Shared): AI 기여자 구조 최종화',
        )

    def test_invalid_new_commit_or_pr_title_fails_gate(self):
        with self.assertRaisesRegex(WorkflowError, 'commit subject'):
            verify_commit_contract(['Contributor architecture cleanup'])
        with self.assertRaisesRegex(WorkflowError, 'PR title'):
            verify_commit_contract(
                ['chore(Shared): 기여자 구조 정리'],
                'Contributor architecture cleanup',
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
