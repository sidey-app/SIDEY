import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('content_assets', Path(__file__).resolve().parents[1] / 'verify_content_assets.py')
CONTENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTENT)


class SelectedApprovalTests(unittest.TestCase):
    def test_only_explicitly_selected_approved_candidates_are_accepted(self):
        artifacts = [dict(candidate_id=name, path=name + '.wav', sha256=name) for name in ('A', 'B')]
        for selection in ('B', ['B']):
            self.assertEqual(CONTENT.selected_artifacts([
                dict(status='approved', selection=selection, artifacts=artifacts),
                dict(status='pending', selection='A', artifacts=artifacts),
            ]), {'docs/reviews/character-five/B.wav': 'B'})
