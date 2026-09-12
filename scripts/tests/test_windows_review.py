import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workflow import verify_windows_run, WorkflowError


class WindowsReviewTests(unittest.TestCase):
    def test_requires_current_main_push_and_actual_smoke(self):
        metadata = dict(head_sha='current', head_branch='main', event='push', status='completed',
                        conclusion='success', path='.github/workflows/integration.yml')
        jobs = [dict(name='windows', conclusion='success',
                     steps=[dict(name='Run Windows app smoke', conclusion='success')])]
        verify_windows_run('current', metadata, jobs)
        for field in metadata:
            with self.subTest(field=field), self.assertRaises(WorkflowError):
                verify_windows_run('current', {**metadata, field: 'other'}, jobs)
        for invalid in [[], [dict(name='windows', conclusion='success', steps=[])],
                        [dict(name='windows', conclusion='skipped')],
                        [dict(name='windows', conclusion='success', steps=[dict(name='Run Windows app smoke', conclusion='skipped')])]]:
            with self.subTest(jobs=invalid), self.assertRaises(WorkflowError):
                verify_windows_run('current', metadata, invalid)
