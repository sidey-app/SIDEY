"""Copy approved product assets to Windows; --check performs read-only verification."""

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/v1'
WINDOWS = ROOT / 'windows'
sys.path.insert(0, str(ROOT / 'scripts'))
from catalog_source import load_source, supported_catalog, SOURCES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--source-commit', help='Reviewed public commit to pin when synchronizing')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('pixel_assets', ROOT / 'scripts/validate_pixel_assets.py')
    pixels = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pixels)
    catalog, manifest, source_metadata = load_source(ROOT, 'windows', args.source_commit)
    if not args.check and not args.source_commit:
        parser.error('--source-commit is required when synchronizing')
    catalog = supported_catalog(catalog, manifest, 'windows')
    outputs = {}
    overlay = WINDOWS / 'src/Sidey.Overlay/Assets'

    def sheet(entry, destination, bottom_up=True):
        source = SOURCE / entry['path']
        data = source.read_bytes()
        assert hashlib.sha256(data).hexdigest() == entry['sha256'], source
        width, height, rgba = pixels.parse_rgba_png(source)
        # Base character frames are top-down; throw sheets are bottom-up.
        bgra = bytearray()
        for y in (reversed(range(height)) if bottom_up else range(height)):
            for x in range(width):
                r, g, b, a = rgba[(y * width + x) * 4:(y * width + x + 1) * 4]
                bgra.extend((b, g, r, a))
        outputs[destination.with_suffix('.png')] = data
        outputs[destination.with_suffix('.bgra')] = bytes(bgra)
        return bgra

    for character in manifest['characters']:
        if 'windows' not in character.get('supported_platforms', []):
            continue
        directory = overlay / 'Characters' / character['id']
        bgra = sheet(character['base'], directory / 'base', bottom_up=False)
        sheet(character['throw_hit'], directory / 'throw_hit')
        path = directory / 'manifest.json'
        if path.exists():
            metadata = json.loads(path.read_text(encoding='utf-8'))
            assert metadata['sha256'] == character['base']['sha256'], path
            assert metadata['runtime_bgra']['sha256'] == hashlib.sha256(bgra).hexdigest(), path
        else:
            metadata = {
                'character_id': character['id'], 'display_name': character['display_name'],
                'legacy_aliases': [], 'frame_pixel_size': [24, 24], 'render_dip_size': [48, 48],
                'sheet_pixel_size': [240, 24], 'foot_baseline_pixel': 3, 'filtering': 'nearest',
                'animations': {'idle': [0, 1], 'walk': [2, 3, 4, 5], 'doze': [6, 7], 'offline': [8, 9]},
                'sha256': character['base']['sha256'],
                'runtime_bgra': {'byte_order': 'BGRA', 'alpha': 'straight', 'byte_length': len(bgra),
                                 'sha256': hashlib.sha256(bgra).hexdigest()},
            }
            outputs[path] = (json.dumps(metadata, ensure_ascii=False, indent=2) + '\n').encode()
    supported_throwables = [entry for entry in manifest['throwables']
                            if 'windows' in entry.get('supported_platforms', [])]
    for throwable in supported_throwables:
        directory = overlay / 'Throwables' / throwable['id']
        sheet(throwable['sprite'], directory / 'sprite')
        if 'emitter' in throwable:
            sheet(throwable['emitter'], directory / 'emitter')
    audio_root = WINDOWS / 'src/Sidey.App/Assets/Impacts'
    audio_manifest = json.loads((audio_root / 'manifest.json').read_text(encoding='utf-8'))
    sound_ids = {entry.get('impact_sound_id', entry['id']) for entry in supported_throwables}
    for source in sorted((SOURCE / 'audio').glob('impact-*.wav')):
        sound_id = source.stem.removeprefix('impact-')
        if sound_id not in sound_ids:
            continue
        data = source.read_bytes()
        relative = f'{sound_id}/{sound_id}.wav'
        outputs[audio_root / relative] = data
        entry = {'id': sound_id, 'file': relative, 'sha256': hashlib.sha256(data).hexdigest()}
        existing = next((x for x in audio_manifest if x['id'] == sound_id), None)
        if existing is None:
            audio_manifest.append(entry)
        else:
            assert existing == entry, source
    outputs[audio_root / 'manifest.json'] = (json.dumps(audio_manifest, indent=2) + '\n').encode()
    # The shared source can be checked out as CRLF; Windows JSON is explicitly LF.
    outputs[WINDOWS / 'src/Sidey.Core/Domain/commerce-catalog.json'] = (
        json.dumps(catalog, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    outputs[ROOT / SOURCES['windows']] = (
        json.dumps(source_metadata, indent=2) + '\n').encode('utf-8')
    mismatches = []
    for destination, data in outputs.items():
        assert destination.resolve().is_relative_to(WINDOWS.resolve())
        if destination.exists() and destination.read_bytes() == data:
            continue
        if args.check:
            mismatches.append(str(destination.relative_to(ROOT)))
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
    if mismatches:
        raise SystemExit('Stale Windows assets:\n' + '\n'.join(mismatches))
    print(f'Windows product assets {"verified" if args.check else "synchronized"}: {len(outputs)} files')


if __name__ == '__main__':
    main()
