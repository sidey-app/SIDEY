import json
from pathlib import Path
import unittest


class CatalogPriceTests(unittest.TestCase):
    def test_confirmed_vat_inclusive_price_tiers(self):
        catalog = json.loads(
            (Path(__file__).parents[2] / 'assets/v1/commerce-catalog.json').read_text(encoding='utf-8')
        )
        premium = {'throwable_dujjonku', 'throwable_wakkuball'}
        for entry in catalog:
            with self.subTest(product=entry['id']):
                expected = 3300 if entry['id'] == 'throwable_toy_cannon' else (
                    2200 if entry['kind'] == 'bubble' or entry['id'] in premium else 1100)
                self.assertEqual(entry['direct_price'], expected)
                self.assertEqual(entry['app_store_price'], expected)
