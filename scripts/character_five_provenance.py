"""Verify selected originals and explicitly recorded compact-feet derivatives.

The reader may use working-tree files or a native bundle's pinned Git commit.
Frame-generator execution belongs to the shared tests, not native verification.
"""
from __future__ import annotations

import hashlib
import json
from collections.abc import Callable
from pathlib import PurePosixPath

PROMOTION = 'assets/v1/character-five-source.json'
GENERATOR = 'docs/reviews/character-five/build_compact_feet_v1.py'
REVISION_ROOT = 'docs/reviews/character-five-compact-feet-v1'
CHARACTERS = {'pixel_shiba', 'pixel_duck', 'pixel_poop', 'pixel_tteokbokki', 'pixel_quokka'}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def selected_artifacts(records: list[dict]) -> dict[str, str]:
    selected = {}
    for record in records:
        if record['status'] != 'approved':
            continue
        selection = record['selection']
        selection = [selection] if isinstance(selection, str) else selection
        for artifact in record.get('artifacts', []):
            if artifact['candidate_id'] in selection:
                selected['docs/reviews/character-five/' + artifact['path']] = artifact['sha256']
    return selected


def verify_character_five_provenance(read: Callable[[str], bytes]) -> list[dict]:
    """Return 18 final {source, destination, sha256} records after verification."""
    def checked(path: str, expected: str) -> bytes:
        parts = PurePosixPath(path)
        require(not parts.is_absolute() and '..' not in parts.parts, f'Unsafe asset path: {path}')
        content = read(path)
        require(hashlib.sha256(content).hexdigest() == expected, f'Asset hash differs: {path}')
        return content

    promotion = json.loads(read(PROMOTION))
    approvals = json.loads(read(promotion['approval']))
    selected = selected_artifacts(approvals['records'])
    require(len(promotion['files']) == 18, 'Expected 18 promoted source files')
    require(len({item['destination'] for item in promotion['files']}) == 18, 'Duplicate promoted destination')
    results, derived_destinations = [], set()
    revision = None
    for item in promotion['files']:
        source, expected = item['source'], item['sha256']
        require(selected.get(source) == expected, f'Original asset was not selected: {source}')
        original = checked(source, expected)
        if derivative := item.get('derivative'):
            destination = PurePosixPath(item['destination'])
            require(len(destination.parts) == 5 and destination.parts[:3] == ('assets', 'v1', 'characters')
                    and destination.parts[3] in CHARACTERS and destination.name in ('base.png', 'throw_hit.png'),
                    'Compact feet may change only the five character sheets')
            require(derivative['kind'] == 'compact_feet_v1', 'Unknown derivative kind')
            require(derivative['generator']['path'] == GENERATOR, 'Unexpected derivative generator')
            checked(GENERATOR, derivative['generator']['sha256'])
            require(derivative['input']['source'] == source and derivative['input']['sha256'] == expected,
                    'Derivative input does not match the selected original')
            require(derivative['revision_metadata'] == REVISION_ROOT + '/revision.json', 'Unexpected revision metadata')
            if revision is None:
                revision = json.loads(read(derivative['revision_metadata']))
                require(revision['status'] == 'user_requested_revision_implementation_reviewed'
                        and revision['authorization']['kind'] == 'user_requested_adjustment'
                        and revision['authorization']['new_pixels_explicitly_approved_by_user'] is False
                        and revision['visual_review']['status'] == 'reviewed_by_implementation_agent'
                        and revision['visual_review']['user_visual_approval_claimed'] is False,
                        'Derivative must distinguish the user request from implementation review')
                require(revision['original_approval']['path'] == promotion['approval'], 'Original approval path changed')
                checked(promotion['approval'], revision['original_approval']['sha256'])
            require(derivative['input']['source_commit'] == revision['source_commit'], 'Derivative input commit differs')
            source, expected = derivative['output']['source'], derivative['output']['sha256']
            relative = '/'.join(destination.parts[-2:])
            require(source == REVISION_ROOT + '/' + relative, 'Derivative result points to a different character sheet')
            reviewed = {entry['path']: entry['sha256'] for entry in revision['result_sheets']}
            require(reviewed.get(relative) == expected, 'Derivative hash differs from reviewed result')
            final = checked(source, expected)
            require(final != original, 'Derivative record must identify a changed sheet')
            derived_destinations.add(item['destination'])
        else:
            final = original
        require(checked(item['destination'], expected) == final, f'Canonical bytes differ: {item["destination"]}')
        results.append({'source': source, 'destination': item['destination'], 'sha256': expected})
    expected_derivatives = {f'assets/v1/characters/{character}/{sheet}.png'
                            for character in CHARACTERS for sheet in ('base', 'throw_hit')}
    require(not derived_destinations or derived_destinations == expected_derivatives,
            'Compact-feet revision must identify exactly ten character sheets')
    return results
