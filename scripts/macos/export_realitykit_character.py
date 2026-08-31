"""Export the approved one-character review slice as RealityKit-ready USDZ clips.

Run with Blender 4.3+:
  Blender --background --python scripts/macos/export_realitykit_character.py -- \
    assets/characters/dog/minty_pup_station_v3_animated.glb \
    macos/SIDEY/Resources/Characters/MintyPup

The source is the approved separated Minty Pup, desk, chair, and laptop vertical
slice. Each USDZ intentionally contains one animation because RealityKit exposes
Blender's USD skeletal timeline reliably in that form.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import bpy


CLIPS = {
    "MintyPupOnlineIdle.usdz": ("online_idle", 90),
    "MintyPupTyping.usdz": ("typing", 60),
    "MintyPupOfflineSleep.usdz": ("away_sleep", 90),
}
RUNTIME_TEXTURE_MAX_DIMENSION = 512
SAMPLE_FRAMES = {
    "online_idle": 46,
    "typing": 31,
    "away_sleep": 31,
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected source and output directory after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.actions, bpy.data.armatures, bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            block.remove(item)


def import_source(source: Path) -> None:
    reset_scene()
    # Set the destination cadence before importing. glTF stores animation time
    # in seconds; importing at Blender's 24 FPS default and switching to 30 FPS
    # afterward would shorten the reviewed three- and two-second clips.
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=str(source.resolve()))
    for obj in list(bpy.context.scene.objects):
        if obj.name.startswith("Icosphere") or obj.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)


def optimize_runtime_textures() -> None:
    for image in bpy.data.images:
        width, height = image.size
        largest_dimension = max(width, height)
        if largest_dimension <= RUNTIME_TEXTURE_MAX_DIMENSION:
            continue
        factor = RUNTIME_TEXTURE_MAX_DIMENSION / largest_dimension
        image.scale(max(1, round(width * factor)), max(1, round(height * factor)))
        image.pack()


def configure_clip(track_name: str, frame_end: int) -> None:
    for obj in bpy.context.scene.objects:
        if obj.animation_data is None:
            continue
        # glTF import leaves one clip in the active-action slot and the others
        # as muted NLA tracks. Clear the active slot first; otherwise every USDZ
        # silently samples the same clip regardless of which track is unmuted.
        obj.animation_data.action = None
        for track in obj.animation_data.nla_tracks:
            is_selected = track.name == track_name
            track.mute = not is_selected
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = frame_end
    scene.frame_set(1)


def validate_scene(track_name: str) -> dict[str, object]:
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    materials = {
        slot.material.name
        for obj in meshes
        for slot in obj.material_slots
        if slot.material is not None
    }
    triangles = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    selected_tracks = {
        track.name
        for obj in bpy.context.scene.objects
        if obj.animation_data is not None
        for track in obj.animation_data.nla_tracks
        if not track.mute
    }
    expected_tracks = {track_name}

    if not armatures or sum(len(obj.data.bones) for obj in armatures) == 0:
        raise RuntimeError("Minty Pup export lost its skeleton")
    if not meshes or triangles == 0 or not materials:
        raise RuntimeError("Minty Pup export lost its mesh or material")
    if not expected_tracks.issubset(selected_tracks):
        raise RuntimeError(f"Expected animation tracks {expected_tracks}, got {selected_tracks}")

    head = armatures[0].pose.bones.get("head")
    if head is None:
        raise RuntimeError("Minty Pup export lost its head bone")
    bpy.context.scene.frame_set(SAMPLE_FRAMES[track_name])
    head_rotation = head.matrix_basis.to_quaternion()

    return {
        "armatures": len(armatures),
        "bones": sum(len(obj.data.bones) for obj in armatures),
        "meshes": len(meshes),
        "triangles": triangles,
        "materials": sorted(materials),
        "animation_tracks": sorted(selected_tracks),
        "fps": bpy.context.scene.render.fps,
        "texture_dimensions": sorted({
            f"{image.size[0]}x{image.size[1]}"
            for image in bpy.data.images
            if image.size[0] > 0 and image.size[1] > 0
        }),
        "head_pose_signature": [round(value, 5) for value in head_rotation],
    }


def export_clip(destination: Path) -> None:
    bpy.ops.wm.usd_export(
        filepath=str(destination.resolve()),
        check_existing=False,
        export_animation=True,
        export_materials=True,
        export_textures=True,
        overwrite_textures=True,
        relative_paths=True,
        export_armatures=True,
        only_deform_bones=True,
        export_shapekeys=False,
        export_cameras=False,
        export_lights=False,
        export_hair=False,
        export_volumes=False,
        convert_world_material=False,
        triangulate_meshes=True,
        root_prim_path="/SIDEY",
    )


def validate_usdz(destination: Path) -> None:
    checker = shutil.which("usdchecker") or "/usr/bin/usdchecker"
    completed = subprocess.run(
        [checker, str(destination.resolve())],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0 or "Success!" not in completed.stdout:
        raise RuntimeError(
            f"usdchecker rejected {destination.name}:\n{completed.stdout}\n{completed.stderr}"
        )


def main() -> None:
    args = arguments()
    if not args.source.is_file():
        raise SystemExit(f"Missing source: {args.source}")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    report = {
        "source": str(args.source),
        "source_sha256": sha256_file(args.source),
        "clips": [],
    }
    for filename, (track_name, frame_end) in CLIPS.items():
        import_source(args.source)
        optimize_runtime_textures()
        configure_clip(track_name, frame_end)
        validation = validate_scene(track_name)
        destination = args.output_dir / filename
        export_clip(destination)
        validate_usdz(destination)
        report["clips"].append({
            "file": filename,
            "track": track_name,
            "frames": [1, frame_end],
            "bytes": destination.stat().st_size,
            "sha256": sha256_file(destination),
            "validation": validation,
            "usdchecker": "Success!",
        })

    signatures = {
        tuple(clip["validation"]["head_pose_signature"])
        for clip in report["clips"]
    }
    if len(signatures) != len(CLIPS):
        raise RuntimeError("Runtime clips do not contain distinct sampled head poses")

    (args.output_dir / "export-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("SIDEY_REALITYKIT_EXPORT=" + json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
