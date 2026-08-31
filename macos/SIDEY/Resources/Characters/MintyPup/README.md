# Minty Pup native macOS assets

These USDZ files are generated from the approved
`minty_pup_station_v3_animated.glb` vertical-slice asset. The source keeps the
character, chair, desk, laptop base, and laptop lid as separate objects; the
character uses a 19-bone rig with baked `online_idle`, `typing`, and
`away_sleep` clips. SIDEY validates each USDZ with RealityKit and renders it
with SceneKit at 30 FPS. Runtime texture copies are capped at 512 px for the
small overlay; the source GLB is left unchanged.

Regenerate from the repository root:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python scripts/macos/export_realitykit_character.py -- \
  assets/characters/dog/minty_pup_station_v3_animated.glb \
  macos/SIDEY/Resources/Characters/MintyPup
```

Validate each output with `/usr/bin/usdchecker` before release.

`export-report.json` records the SHA-256 of the source GLB and each exact USDZ
copied into the app bundle. `verify_character_asset_lineage.py` checks the
repository source and output hashes before every native Release build;
`MintyPupAssetTests` checks the bundled USDZ hashes together with file size,
rig, materials, animation tracks, cadence, and loader support. Keeping the
repository read out of the GUI-hosted XCTest also avoids macOS Documents-folder
privacy stalls.
USDZ container metadata is not byte-for-byte deterministic across separate
Blender exports, so output hashes provide artifact traceability; the semantic
validation fields are the reproducibility contract between exports.
