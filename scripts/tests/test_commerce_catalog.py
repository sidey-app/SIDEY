import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parents[1]))
import commerce_catalog as c
from workflow import validate_paths, WorkflowError


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.products = json.loads((c.ROOT / c.CATALOG).read_text())
        self.manifest = json.loads((c.ROOT / 'assets/v1/manifest.json').read_text())

    def test_duplicate_id_offer_and_unknown_asset_fail(self):
        for mutate in [lambda p: p.append(copy.deepcopy(p[0])),
                       lambda p: p[1].update(app_store_product_id=p[0]['app_store_product_id']),
                       lambda p: p[0].update(render_asset_id='missing'),
                       lambda p: p[0].update(related_character_product_id='missing')]:
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                products = copy.deepcopy(self.products)
                mutate(products)
                c.validate(products, self.manifest)

    def test_deterministic_generation_and_platform_boundaries(self):
        for target in ['shared', 'macos']:
            output = c.generated(self.products, target)
            self.assertEqual(output, c.generated(self.products, target))
            validate_paths(target+'/catalog', output)
            with self.assertRaises(WorkflowError):
                validate_paths(('macos' if target == 'shared' else 'shared')+'/catalog', output)

    def test_storekit_current_offer_missing_or_wrong_price_is_rejected(self):
        original = json.loads((c.ROOT / 'macos/SIDEYAppStore.storekit').read_text())
        c.check_storekit(self.products, original)
        for config in [dict(original, products=original['products'][1:]), copy.deepcopy(original)]:
            if len(config['products']) == len(original['products']):
                config['products'][0]['displayPrice'] = '1'
            with self.assertRaises(ValueError):
                c.check_storekit(self.products, config)
