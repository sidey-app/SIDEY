#!/usr/bin/env python3
"""Verify native asset bytes against the bundle's reviewed Git source."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from catalog_source import load_source


def selected_artifacts(records: list[dict]) -> dict[str, str]:
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
    return selected


def verify(root: Path = ROOT) -> int:
    _, manifest, source = load_source(root, 'macos')
    if source is None:
        raise ValueError('macOS content requires a recorded source commit')
    commit = source['source_commit']
    resources = root / 'macos/SIDEY/Resources'
    count = 0

    def read(path: str) -> bytes:
        # Binary assets must not undergo the JSON source reader's newline normalization.
        return subprocess.check_output(['git', 'show', f'{commit}:{path}'], cwd=root)

    def compare(path: str, native: Path, expected: str) -> None:
        nonlocal count
        if hashlib.sha256(read(path)).hexdigest() != expected:
            raise ValueError(f'Reviewed source hash differs: {path}')
        if hashlib.sha256(native.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Native asset differs from reviewed source: {native}')
        count += 1

    for character in manifest['characters']:
        for key, native in [
            ('base', resources / 'Characters' / character['macos_directory'] / f"{character['id']}.png"),
            ('throw_hit', resources / 'CharacterThrow/ActionSheets' / f"{character['id']}_throw_hit.png"),
        ]:
            asset = character[key]
            compare('assets/v1/' + asset['path'], native, asset['sha256'])
    for item in manifest['throwables']:
        asset = item['sprite']
        compare('assets/v1/' + asset['path'], resources / 'CharacterThrow/ObjectSheets' / f"{item['id']}.png", asset['sha256'])

    # Promotion records identify the exact candidate selected by the user.
    promotion = json.loads(read('assets/v1/character-five-source.json'))
    approvals = json.loads(read(promotion['approval']))
    selected = selected_artifacts(approvals['records'])
    for item in promotion['files']:
        expected = item['sha256']
        if selected.get(item['source']) != expected:
            raise ValueError(f"Promoted asset was not selected: {item['source']}")
        if hashlib.sha256(read(item['source'])).hexdigest() != expected:
            raise ValueError(f"Selected source hash differs: {item['source']}")
        if hashlib.sha256(read(item['destination'])).hexdigest() != expected:
            raise ValueError(f"Promoted destination hash differs: {item['destination']}")
        if item['destination'].startswith('assets/v1/audio/'):
            compare(item['destination'], resources / 'DirectImpactAudio' / Path(item['destination']).name, expected)
    return count


if __name__ == '__main__':
    try:
        print(f'macOS: {verify()} asset files match their reviewed source')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
