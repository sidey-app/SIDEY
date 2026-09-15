import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).parents[2]


class ApprovedContentTests(unittest.TestCase):
    def test_promoted_files_are_exact_selected_approved_artifacts(self):
        promotion = json.loads((ROOT / 'assets/v1/character-five-source.json').read_text())
        records = json.loads((ROOT / promotion['approval']).read_text())['records']
        selected = {}
        for record in records:
            if record['status'] != 'approved':
                continue
            selection = record['selection']
            if isinstance(selection, str):
                selection = [selection]
            for artifact in record.get('artifacts', []):
                if artifact['candidate_id'] in selection:
                    selected['docs/reviews/character-five/' + artifact['path']] = artifact['sha256']
        self.assertEqual(len(promotion['files']), 18)
        for item in promotion['files']:
            with self.subTest(path=item['destination']):
                self.assertEqual(selected[item['source']], item['sha256'])
                self.assertEqual(hashlib.sha256((ROOT / item['destination']).read_bytes()).hexdigest(), item['sha256'])
                self.assertEqual((ROOT / item['source']).read_bytes(), (ROOT / item['destination']).read_bytes())

    def test_new_offers_keep_independent_entitlements_and_reuse_duck(self):
        catalog = json.loads((ROOT / 'assets/v1/commerce-catalog.json').read_text())
        manifest = json.loads((ROOT / 'assets/v1/manifest.json').read_text())
        self.assertEqual((len(catalog), len(manifest['characters']), len(manifest['throwables'])), (33, 17, 19))
        self.assertEqual(len({p['entitlement'] for p in catalog}), 33)
        duck = [p for p in catalog if p['id'] == 'throwable_squeaky_duck']
        self.assertEqual(len(duck), 1)
        self.assertEqual(duck[0]['related_character_product_id'], 'character_duck')
        self.assertFalse(any('rubber_duck' in p['id'] for p in catalog))
        for animal in ['shiba', 'duck', 'poop', 'tteokbokki', 'quokka']:
            entry = next(p for p in catalog if p['id'] == 'character_' + animal)
            copy = json.loads((ROOT / f'docs/reviews/character-five/copy-v1/pixel_{animal}.json').read_text())
            self.assertEqual(entry['description'], copy['character']['description'])
            self.assertEqual(entry['direct_price'], 1100)
            related = [p for p in catalog if p['related_character_product_id'] == entry['id']]
            self.assertEqual(len(related), 1)
            self.assertEqual(related[0]['description'], copy['keepsake']['description'])
            self.assertNotEqual(entry['entitlement'], related[0]['entitlement'])
