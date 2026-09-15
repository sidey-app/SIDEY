import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import catalog_source as c
import validate_pixel_assets as v

ROOT = Path(__file__).parents[2]


class PixelAssetSourcePinTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        canonical = json.loads((ROOT / c.MANIFEST).read_text())
        self.entry = copy.deepcopy(next(item for item in canonical['characters'] if item['id'] == 'pixel_shiba'))
        self.entry['supported_platforms'] = ['macos', 'windows', 'checkout']
        self.sources = {}
        for sheet in ('base', 'throw_hit'):
            data = (ROOT / f'docs/reviews/character-five/candidates/character-v2/pixel_shiba/{sheet}.png').read_bytes()
            self.entry[sheet]['sha256'] = hashlib.sha256(data).hexdigest()
            path = 'assets/v1/' + self.entry[sheet]['path']
            self.sources[path] = data
            self.write(path, data)
            for platform in ('macos', 'windows'):
                pattern = next(pattern for pattern in canonical['mirrors']['character_base_png' if sheet == 'base' else 'throw_hit_png']
                               if pattern.startswith(platform + '/'))
                self.write(pattern.format(**self.entry), data)
            _, height, rgba = v.decode_rgba_png(data, path)
            bgra = v.rgba_to_bgra(rgba)
            if sheet == 'throw_hit':
                row = len(bgra) // height
                bgra = b''.join(bgra[offset:offset + row] for offset in range(len(bgra) - row, -1, -row))
            self.write(f'windows/src/Sidey.Overlay/Assets/Characters/pixel_shiba/{sheet}.bgra', bgra)
            if sheet == 'base':
                native_manifest = {'character_id': 'pixel_shiba', 'sha256': self.entry['base']['sha256'],
                                   'runtime_bgra': {'byte_length': len(rgba), 'sha256': hashlib.sha256(bgra).hexdigest()}}
                self.write('windows/src/Sidey.Overlay/Assets/Characters/pixel_shiba/manifest.json', json.dumps(native_manifest).encode())
        self.manifest = {'characters': [self.entry], 'throwables': [], 'bubbles': [], 'mirrors': canonical['mirrors']}
        self.sources[c.CATALOG] = b'[]'
        self.sources[c.MANIFEST] = json.dumps(self.manifest).encode()
        for path in (c.CATALOG, c.MANIFEST):
            self.write(path, self.sources[path])
        self.metadata = {'source_commit': 'a' * 40, 'sha256': {
            path: hashlib.sha256(self.sources[path]).hexdigest() for path in (c.CATALOG, c.MANIFEST)}}
        for platform in ('macos', 'windows'):
            self.write(c.SOURCES[platform], json.dumps(self.metadata).encode())
        self.enterContext(patch.object(v, 'REPOSITORY_ROOT', self.root))
        self.enterContext(patch.object(c, 'source_bytes', side_effect=lambda root, commit, path: self.sources[path]))
        self.enterContext(patch.object(v, 'pinned_asset_bytes', side_effect=lambda root, commit, path: self.sources[path]))

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def test_native_pins_keep_verifying_their_assets_after_canonical_changes(self):
        # The canonical file and asset list have advanced independently. Neither
        # may hide an older native asset from its pinned manifest's inventory.
        self.write('assets/v1/characters/pixel_shiba/base.png', b'new canonical bytes')
        current = copy.deepcopy(self.manifest)
        current['characters'] = []
        self.write(c.MANIFEST, json.dumps(current).encode())
        self.assertEqual(v.validate_native_mirrors(), 6)
        self.write('macos/SIDEY/Resources/Characters/PixelShiba/pixel_shiba.png', b'wrong native')
        with self.assertRaisesRegex(AssertionError, 'PNG mirror differs'):
            v.validate_native_mirrors()

    def test_windows_bgra_is_still_checked_against_pinned_rgba(self):
        self.assertEqual(v.validate_native_mirrors(platforms=('windows',)), 4)
        self.write('windows/src/Sidey.Overlay/Assets/Characters/pixel_shiba/throw_hit.bgra', b'wrong bgra')
        with self.assertRaisesRegex(AssertionError, 'BGRA mirror differs'):
            v.validate_native_mirrors(platforms=('windows',))

    def test_new_current_support_still_checks_checkout_only_pinned_asset(self):
        pinned = json.loads(self.sources[c.MANIFEST])
        pinned['characters'][0]['supported_platforms'] = ['checkout']
        self.sources[c.MANIFEST] = json.dumps(pinned).encode()
        self.metadata['sha256'][c.MANIFEST] = hashlib.sha256(self.sources[c.MANIFEST]).hexdigest()
        self.write(c.SOURCES['macos'], json.dumps(self.metadata).encode())
        self.assertEqual(v.validate_native_mirrors(platforms=('macos',)), 2)
        self.write('macos/SIDEY/Resources/Characters/PixelShiba/pixel_shiba.png', b'wrong native')
        with self.assertRaisesRegex(AssertionError, 'PNG mirror differs'):
            v.validate_native_mirrors(platforms=('macos',))

    def test_new_current_native_asset_without_pinned_source_is_rejected(self):
        pinned = json.loads(self.sources[c.MANIFEST])
        pinned['characters'] = []
        self.sources[c.MANIFEST] = json.dumps(pinned).encode()
        self.metadata['sha256'][c.MANIFEST] = hashlib.sha256(self.sources[c.MANIFEST]).hexdigest()
        self.write(c.SOURCES['macos'], json.dumps(self.metadata).encode())
        with self.assertRaisesRegex(AssertionError, 'missing from the reviewed pin'):
            v.validate_native_mirrors(platforms=('macos',))

    def test_forged_native_pin_manifest_hash_is_rejected(self):
        self.metadata['sha256'][c.MANIFEST] = '0' * 64
        self.write(c.SOURCES['macos'], json.dumps(self.metadata).encode())
        with self.assertRaisesRegex(ValueError, 'Catalog source hash differs'):
            v.validate_native_mirrors(platforms=('macos',))

    def test_pinned_asset_bytes_must_match_reviewed_manifest_hash(self):
        self.sources['assets/v1/characters/pixel_shiba/base.png'] += b'corrupt'
        with self.assertRaisesRegex(AssertionError, 'reviewed asset SHA-256 mismatch'):
            v.validate_native_mirrors(platforms=('macos',))

    def test_unpinned_native_bundle_remains_a_strict_current_canonical_mirror(self):
        (self.root / c.SOURCES['macos']).unlink()
        self.assertEqual(v.validate_native_mirrors(platforms=('macos',)), 2)
        newer = (ROOT / 'assets/v1/characters/pixel_shiba/base.png').read_bytes()
        self.assertNotEqual(newer, self.sources['assets/v1/characters/pixel_shiba/base.png'])
        self.write('assets/v1/characters/pixel_shiba/base.png', newer)
        self.manifest['characters'][0]['base']['sha256'] = hashlib.sha256(newer).hexdigest()
        self.write(c.MANIFEST, json.dumps(self.manifest).encode())
        with self.assertRaisesRegex(AssertionError, 'PNG mirror differs'):
            v.validate_native_mirrors(platforms=('macos',))

    def test_web_mirror_remains_bound_to_current_canonical(self):
        source = self.root / 'assets/v1/characters/pixel_shiba/base.png'
        self.write('website/public/assets/store/pixel_shiba.png', source.read_bytes())
        patterns = self.manifest['mirrors']['character_base_png']
        v.validate_declared_web_png_mirrors(source, patterns, self.entry, canonical_only=False)
        self.write('website/public/assets/store/pixel_shiba.png', b'old web')
        with self.assertRaisesRegex(AssertionError, 'PNG mirror differs'):
            v.validate_declared_web_png_mirrors(source, patterns, self.entry, canonical_only=False)
