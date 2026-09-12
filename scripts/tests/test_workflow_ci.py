import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).parents[1]))
from workflow import WorkflowError
from workflow_ci import verify_gate


class GateTests(unittest.TestCase):
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
