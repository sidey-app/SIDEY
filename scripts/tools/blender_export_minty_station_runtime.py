"""Bake the approved Minty Pup station motions and export one runtime GLB.

The input .blend is the approved separated station assembly.  Review motions
use Blender IK targets, which GLB/USDZ runtimes do not evaluate.  This script
bakes their evaluated result into the 19-bone armature before exporting the
three runtime clips.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import bpy


CLIPS = (
    ("online_idle", "_author_online_idle", 90),
    ("typing", "_author_typing", 60),
    ("away_sleep", "_author_offline_sleep", 90),
)
EXPORT_OBJECTS = (
    "Chair",
    "Desk",
    "LaptopBase",
    "LaptopLid",
    "MintyPupMesh",
    "MintyPupRig",
)


def _argument() -> Path:
    if "--" not in sys.argv:
        raise SystemExit("Expected: -- output.glb")
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("Expected exactly one output GLB path")
    return Path(args[0]).resolve()


def _motion_module():
    module_path = Path(__file__).with_name("blender_build_minty_motion_review.py")
    spec = importlib.util.spec_from_file_location("sidey_minty_review_motion", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load motion authoring module: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _clear_authored_animation(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.animation_data is not None:
            obj.animation_data_clear()


def _bake_clip(
    module,
    author_name: str,
    runtime_name: str,
    frame_end: int,
    armature: bpy.types.Object,
    targets: dict[str, bpy.types.Object],
) -> bpy.types.Action:
    author = getattr(module, author_name)
    authored = author(armature, targets)
    module._activate_actions(
        {armature.name: armature, **{target.name: target for target in targets.values()}},
        authored,
    )

    scene = bpy.context.scene
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = frame_end
    scene.frame_set(1)

    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    result = bpy.ops.nla.bake(
        frame_start=1,
        frame_end=frame_end,
        step=1,
        only_selected=False,
        visual_keying=True,
        clear_constraints=False,
        clear_parents=False,
        use_current_action=False,
        clean_curves=True,
        bake_types={"POSE"},
    )
    if "FINISHED" not in result or armature.animation_data is None or armature.animation_data.action is None:
        raise RuntimeError(f"Failed to bake {runtime_name}: {result}")

    baked = armature.animation_data.action

    # nla.bake stashes the authored source action in a temporary NLA strip.
    # Remove that strip and source action before assigning the runtime name;
    # otherwise Blender silently produces names such as online_idle.001, which
    # breaks the native clip selector after a GLB round trip.
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)

    for obj in targets.values():
        if obj.animation_data is not None:
            obj.animation_data_clear()
    for action in authored.values():
        if action != baked:
            bpy.data.actions.remove(action, do_unlink=True)
    baked.name = runtime_name
    baked.use_fake_user = True
    return baked


def _validate_scene(actions: dict[str, bpy.types.Action]) -> dict[str, object]:
    meshes = [bpy.data.objects[name] for name in EXPORT_OBJECTS if bpy.data.objects[name].type == "MESH"]
    armature = bpy.data.objects["MintyPupRig"]
    triangles = 0
    for mesh in meshes:
        mesh.data.calc_loop_triangles()
        triangles += len(mesh.data.loop_triangles)
    materials = sorted({
        slot.material.name
        for mesh in meshes
        for slot in mesh.material_slots
        if slot.material is not None
    })
    if len(armature.data.bones) != 19:
        raise RuntimeError(f"Expected 19 bones, got {len(armature.data.bones)}")
    if set(actions) != {"online_idle", "typing", "away_sleep"}:
        raise RuntimeError(f"Unexpected runtime actions: {sorted(actions)}")
    if triangles <= 0 or not materials:
        raise RuntimeError("Runtime station lost mesh geometry or materials")
    return {
        "bones": len(armature.data.bones),
        "meshes": len(meshes),
        "triangles": triangles,
        "materials": materials,
        "actions": {name: [round(value, 3) for value in action.frame_range] for name, action in actions.items()},
        "fps": bpy.context.scene.render.fps,
    }


def main() -> None:
    destination = _argument()
    destination.parent.mkdir(parents=True, exist_ok=True)
    source = bpy.data.filepath
    module = _motion_module()

    armature = bpy.data.objects.get("MintyPupRig")
    if armature is None or armature.type != "ARMATURE":
        raise RuntimeError("Expected MintyPupRig armature")
    targets = {side: bpy.data.objects[f"HandTarget{side}"] for side in (".L", ".R")}
    _clear_authored_animation([armature, *targets.values()])
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    baked_actions: dict[str, bpy.types.Action] = {}
    for runtime_name, author_name, frame_end in CLIPS:
        baked_actions[runtime_name] = _bake_clip(
            module,
            author_name,
            runtime_name,
            frame_end,
            armature,
            targets,
        )

    for pose_bone in armature.pose.bones:
        for constraint in list(pose_bone.constraints):
            pose_bone.constraints.remove(constraint)
    for target in targets.values():
        bpy.data.objects.remove(target, do_unlink=True)

    armature.animation_data_create()
    armature.animation_data.action = None
    for track in list(armature.animation_data.nla_tracks):
        armature.animation_data.nla_tracks.remove(track)
    for name, action in baked_actions.items():
        track = armature.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
    validation = _validate_scene(baked_actions)

    blend_path = destination.with_suffix(".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    bpy.ops.object.select_all(action="DESELECT")
    for name in EXPORT_OBJECTS:
        bpy.data.objects[name].select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_skins=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )

    report = {
        "source": source,
        "output": str(destination),
        "blend": str(blend_path),
        "bytes": destination.stat().st_size,
        "validation": validation,
        "ik_baked": True,
        "runtime_effects_excluded": ["review-only Zzz text"],
    }
    report_path = destination.with_suffix(".json")
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_STATION_RUNTIME_EXPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
