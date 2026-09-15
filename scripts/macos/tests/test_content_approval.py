import importlib.util
import json
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


class StoreKitRegistrationMetadataTests(unittest.TestCase):
    def test_localizations_fit_app_store_connect_limits(self):
        root = Path(__file__).resolve().parents[3]
        configuration = json.loads((root / 'macos/SIDEYAppStore.storekit').read_text())
        for product in configuration['products']:
            self.assertTrue(product['localizations'], product['productID'])
            for locale in product['localizations']:
                with self.subTest(product=product['productID'], locale=locale['locale']):
                    self.assertGreaterEqual(len(locale['displayName']), 2)
                    self.assertLessEqual(len(locale['displayName']), 30)
                    self.assertGreater(len(locale['description']), 0)
                    self.assertLessEqual(len(locale['description']), 45)
