import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1]))
import catalog_source as c


class CatalogSourceTests(unittest.TestCase):
    def test_pinned_source_survives_new_canonical_but_rejects_forged_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            data = {c.CATALOG: b'[{"id":"old"}]', c.MANIFEST: b'{"old":true}'}
            metadata = {'source_commit': 'a' * 40, 'sha256': {
                path: hashlib.sha256(content).hexdigest() for path, content in data.items()}}
            pin = root / c.SOURCES['macos']
            pin.parent.mkdir(parents=True)
            pin.write_text(json.dumps(metadata))
            with patch.object(c, 'source_bytes', side_effect=lambda r, sha, path: data[path]):
                catalog, manifest, source = c.load_source(root, 'macos')
                self.assertEqual(catalog, [{'id': 'old'}])
                self.assertEqual(manifest, {'old': True})
                self.assertEqual(source['source_commit'], 'a' * 40)
                metadata['sha256'][c.CATALOG] = '0' * 64
                pin.write_text(json.dumps(metadata))
                with self.assertRaisesRegex(ValueError, 'hash differs'):
                    c.load_source(root, 'macos')

    def test_unpinned_platform_still_requires_current_canonical(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / c.CATALOG).parent.mkdir(parents=True)
            (root / c.CATALOG).write_text('[]')
            (root / c.MANIFEST).write_text('{}')
            self.assertEqual(c.load_source(root, 'macos'), ([], {}, None))

    def test_source_requires_full_commit_and_existing_git_history(self):
        with self.assertRaisesRegex(ValueError, 'full commit'):
            c.source_bytes(Path('.'), 'HEAD', c.CATALOG)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'fetch its history'):
                c.source_bytes(Path(directory), 'a' * 40, c.CATALOG)

    def test_platform_filter_does_not_adopt_other_platform_content(self):
        catalog = [{'kind': 'character', 'item_id': 'old'},
                   {'kind': 'throwable', 'item_id': 'product', 'render_asset_id': 'new'}]
        manifest = {'characters': [{'id': 'old', 'supported_platforms': ['windows', 'macos']}],
                    'throwables': [{'id': 'new', 'supported_platforms': ['macos']}], 'bubbles': []}
        self.assertEqual(c.supported_catalog(catalog, manifest, 'windows'), catalog[:1])
