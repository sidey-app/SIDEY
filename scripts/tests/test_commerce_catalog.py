import copy
import json
from pathlib import Path
import sys
import unittest


SCRIPTS = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(SCRIPTS / "skills"))

import commerce_catalog as catalog_tool  # noqa: E402
from sidey_tools import WorkflowError  # noqa: E402
from sidey_tools.repository import validate_paths  # noqa: E402


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.products = catalog_tool.read_json(
            catalog_tool.ROOT / catalog_tool.CATALOG
        )
        self.manifest = catalog_tool.read_json(
            catalog_tool.ROOT / catalog_tool.MANIFEST
        )

    def test_duplicate_id_offer_and_unknown_asset_fail(self):
        mutations = [
            lambda products: products.append(
                copy.deepcopy(products[0])
            ),
            lambda products: products[1].update(
                app_store_product_id=(
                    products[0]["app_store_product_id"]
                )
            ),
            lambda products: products[0].update(
                render_asset_id="missing"
            ),
            lambda products: products[0].update(
                related_character_product_id="missing"
            ),
        ]

        for mutate in mutations:
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                products = copy.deepcopy(self.products)
                mutate(products)
                catalog_tool.validate(products, self.manifest)

    def test_deterministic_generation_and_platform_boundaries(self):
        for target in ("shared", "macos"):
            outputs = catalog_tool.generated(self.products, target)
            self.assertEqual(
                outputs,
                catalog_tool.generated(self.products, target),
            )
            validate_paths(f"{target}/catalog", list(outputs))

            other = "macos" if target == "shared" else "shared"
            with self.assertRaises(WorkflowError):
                validate_paths(f"{other}/catalog", list(outputs))

    def test_shared_generation_only_owns_public_website_mirror(self):
        outputs = catalog_tool.generated(self.products, "shared")
        mirror = "website/public/assets/commerce-products.js"
        self.assertEqual(set(outputs), {mirror})

        checked_in = (catalog_tool.ROOT / mirror).read_bytes()
        self.assertEqual(outputs[mirror], checked_in)

    def test_storekit_missing_offer_or_wrong_price_is_rejected(self):
        configuration = catalog_tool.read_json(
            catalog_tool.ROOT / catalog_tool.STOREKIT_CONFIGURATION
        )
        pinned, _, _ = catalog_tool.load_source(
            catalog_tool.ROOT,
            "macos",
        )
        catalog_tool.check_storekit(pinned, configuration)

        missing_offer = {
            **configuration,
            "products": configuration["products"][1:],
        }
        wrong_price = copy.deepcopy(configuration)
        wrong_price["products"][0]["displayPrice"] = "1"
        for invalid in (missing_offer, wrong_price):
            with self.assertRaises(ValueError):
                catalog_tool.check_storekit(pinned, invalid)


if __name__ == "__main__":
    unittest.main()
