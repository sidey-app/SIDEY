"""Read a platform catalog from its reviewed source, including staged rollouts."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import subprocess

CATALOG = 'assets/v1/commerce-catalog.json'
MANIFEST = 'assets/v1/manifest.json'
SOURCES = {
    'macos': 'macos/SIDEY/Resources/Commerce/catalog-source.json',
    'windows': 'windows/src/Sidey.Core/Domain/catalog-source.json',
}


def source_bytes(root: Path, commit: str, path: str) -> bytes:
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Catalog source must be a full commit SHA')
    result = subprocess.run(['git', 'show', f'{commit}:{path}'], cwd=root, capture_output=True)
    if result.returncode:
        raise ValueError(f'Catalog source {commit} is unavailable; fetch its history before verification')
    return result.stdout.replace(b'\r\n', b'\n')


def provenance(root: Path, commit: str) -> dict:
    return {'source_commit': commit, 'sha256': {
        path: hashlib.sha256(source_bytes(root, commit, path)).hexdigest()
        for path in (CATALOG, MANIFEST)}}


def load_source(root: Path, platform: str, commit: str | None = None):
    source_path = root / SOURCES[platform]
    if commit is not None:
        metadata = provenance(root, commit)
    elif source_path.exists():
        metadata = json.loads(source_path.read_text(encoding='utf-8'))
    else:
        # Existing bundles remain strict mirrors until their first explicit pin.
        return (json.loads((root / CATALOG).read_text(encoding='utf-8')),
                json.loads((root / MANIFEST).read_text(encoding='utf-8')), None)
    values = []
    for path in (CATALOG, MANIFEST):
        expected = metadata['sha256'][path]
        # Always verify the recorded commit, not just a self-reported bundle hash.
        data = source_bytes(root, metadata['source_commit'], path)
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f'Catalog source hash differs: {platform} {path}')
        values.append(json.loads(data))
    return (*values, metadata)


def supported_catalog(catalog, manifest, platform):
    assets = {kind: {a['id']: a for a in manifest[kind + 's']}
              for kind in ('character', 'throwable', 'bubble')}
    return [entry for entry in catalog
            if platform in assets[entry['kind']][entry.get('render_asset_id') or entry['item_id']]['supported_platforms']]
