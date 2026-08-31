"""Author and render SIDEY's three Minty Pup review motions.

The source is the approved-scale station assembly.  IK controls remain review
helpers; the user first approves these MOV files, then the motions are baked to
the armature and exported for runtime conversion.

Run with:
  blender station-assembly.blend --background --python \
    scripts/tools/blender_build_minty_motion_review.py -- output-directory
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


FPS = 30
HAND_BASE = {
    ".L": Vector((0.11, 0.10, 0.84)),
    ".R": Vector((-0.11, 0.10, 0.84)),
}
MOTION_BONES = ("spine", "chest", "neck", "head")


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected an output directory after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--stills-only", action="store_true")
    return parser.parse_args(sys.argv[separator + 1 :])


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _new_action(obj: bpy.types.ID, name: str) -> bpy.types.Action:
    obj.animation_data_create()
    action = bpy.data.actions.new(name)
    obj.animation_data.action = action
    return action


def _key_bones(
    armature: bpy.types.Object,
    frame: int,
    rotations: dict[str, tuple[float, float, float]],
) -> None:
    for bone_name in MOTION_BONES:
        bone = armature.pose.bones[bone_name]
        bone.rotation_mode = "XYZ"
        degrees = rotations.get(bone_name, (0.0, 0.0, 0.0))
        bone.rotation_euler = Vector(tuple(math.radians(value) for value in degrees))
        bone.location = Vector((0.0, 0.0, 0.0))
        bone.scale = Vector((1.0, 1.0, 1.0))
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone_name)
        bone.keyframe_insert(data_path="location", frame=frame, group=bone_name)


def _key_hand(target: bpy.types.Object, frame: int, location: Vector) -> None:
    target.location = location
    target.keyframe_insert(data_path="location", frame=frame)


def _set_interpolation(action: bpy.types.Action, interpolation: str) -> None:
    for curve in action.fcurves:
        for point in curve.keyframe_points:
            point.interpolation = interpolation


def _author_online_idle(
    armature: bpy.types.Object,
    targets: dict[str, bpy.types.Object],
) -> dict[str, bpy.types.Action]:
    actions = {armature.name: _new_action(armature, "online_idle")}
    poses = {
        1: {
            "spine": (0.4, 0.0, 0.0),
            "chest": (-0.6, 0.0, 0.0),
            "neck": (2.0, 0.0, 0.0),
            "head": (1.0, 0.0, -1.0),
        },
        23: {
            "spine": (0.8, 0.0, 0.0),
            "chest": (-0.2, 0.0, 0.0),
            "neck": (2.8, 0.0, 0.8),
            "head": (1.8, 0.0, 1.8),
        },
        46: {
            "spine": (0.2, 0.0, 0.0),
            "chest": (-0.8, 0.0, 0.0),
            "neck": (1.5, 0.0, -0.6),
            "head": (0.3, 0.0, -2.0),
        },
        69: {
            "spine": (0.7, 0.0, 0.0),
            "chest": (-0.3, 0.0, 0.0),
            "neck": (2.5, 0.0, 0.2),
            "head": (1.4, 0.0, 0.8),
        },
        91: {
            "spine": (0.4, 0.0, 0.0),
            "chest": (-0.6, 0.0, 0.0),
            "neck": (2.0, 0.0, 0.0),
            "head": (1.0, 0.0, -1.0),
        },
    }
    for frame, pose in poses.items():
        _key_bones(armature, frame, pose)

    hand_offsets = {
        1: {".L": (0.0, 0.0, 0.0), ".R": (0.0, 0.0, 0.0)},
        23: {".L": (0.002, 0.002, 0.002), ".R": (-0.001, -0.001, -0.001)},
        46: {".L": (-0.001, -0.001, -0.001), ".R": (0.002, 0.002, 0.002)},
        69: {".L": (0.001, 0.001, 0.001), ".R": (-0.002, 0.0, 0.001)},
        91: {".L": (0.0, 0.0, 0.0), ".R": (0.0, 0.0, 0.0)},
    }
    for side, target in targets.items():
        actions[target.name] = _new_action(target, f"online_idle.{target.name}")
        for frame, offsets in hand_offsets.items():
            _key_hand(target, frame, HAND_BASE[side] + Vector(offsets[side]))
    for action in actions.values():
        _set_interpolation(action, "BEZIER")
    return actions


def _author_typing(
    armature: bpy.types.Object,
    targets: dict[str, bpy.types.Object],
) -> dict[str, bpy.types.Action]:
    actions = {armature.name: _new_action(armature, "typing")}
    for frame in [1, 11, 21, 31, 41, 51, 61]:
        phase = ((frame - 1) // 10) % 2
        _key_bones(
            armature,
            frame,
            {
                "spine": (1.4, 0.0, 0.0),
                "chest": (0.8, 0.0, 0.0),
                "neck": (5.5 + phase * 0.8, 0.0, -0.4 if phase else 0.5),
                "head": (4.0 + phase * 1.2, 0.0, 0.8 if phase else -0.8),
            },
        )

    for side, target in targets.items():
        actions[target.name] = _new_action(target, f"typing.{target.name}")
    for frame in range(1, 62, 5):
        phase = ((frame - 1) // 5) % 2
        for side, target in targets.items():
            left = side == ".L"
            raised = (phase == 0 and left) or (phase == 1 and not left)
            direction = 1.0 if left else -1.0
            location = HAND_BASE[side] + Vector(
                (
                    direction * (0.003 if raised else -0.002),
                    -0.004 if raised else 0.004,
                    0.012 if raised else -0.004,
                )
            )
            _key_hand(target, frame, location)
    for action in actions.values():
        _set_interpolation(action, "BEZIER")
    return actions


def _author_offline_sleep(
    armature: bpy.types.Object,
    targets: dict[str, bpy.types.Object],
) -> dict[str, bpy.types.Action]:
    actions = {armature.name: _new_action(armature, "offline_sleep")}
    poses = {
        1: {
            "spine": (4.5, 0.0, 0.0),
            "chest": (7.0, 0.0, 0.0),
            "neck": (14.0, 0.0, 2.0),
            "head": (23.0, 0.0, 7.0),
        },
        31: {
            "spine": (5.2, 0.0, 0.0),
            "chest": (7.8, 0.0, 0.0),
            "neck": (15.5, 0.0, 2.5),
            "head": (25.0, 0.0, 8.0),
        },
        61: {
            "spine": (4.2, 0.0, 0.0),
            "chest": (6.6, 0.0, 0.0),
            "neck": (13.2, 0.0, 1.5),
            "head": (21.8, 0.0, 6.3),
        },
        91: {
            "spine": (4.5, 0.0, 0.0),
            "chest": (7.0, 0.0, 0.0),
            "neck": (14.0, 0.0, 2.0),
            "head": (23.0, 0.0, 7.0),
        },
    }
    for frame, pose in poses.items():
        _key_bones(armature, frame, pose)

    sleep_base = {
        ".L": Vector((0.135, 0.115, 0.832)),
        ".R": Vector((-0.135, 0.115, 0.832)),
    }
    for side, target in targets.items():
        actions[target.name] = _new_action(target, f"offline_sleep.{target.name}")
        for frame, lift in [(1, 0.0), (31, -0.002), (61, 0.002), (91, 0.0)]:
            _key_hand(target, frame, sleep_base[side] + Vector((0.0, 0.0, lift)))
    for action in actions.values():
        _set_interpolation(action, "BEZIER")
    return actions


def _sleep_label(camera: bpy.types.Object) -> bpy.types.Object:
    curve = bpy.data.curves.new("SleepReviewLabel", type="FONT")
    curve.body = "Zzz"
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = 0.13
    curve.extrude = 0.004
    curve.bevel_depth = 0.0015
    label = bpy.data.objects.new("SleepReviewLabel", curve)
    bpy.context.scene.collection.objects.link(label)
    label.location = Vector((0.48, 0.28, 1.35))
    label.rotation_euler = (camera.location - label.location).to_track_quat("Z", "Y").to_euler()
    material = bpy.data.materials.new("SleepReviewBlue")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.24, 0.60, 1.0, 1.0)
    shader.inputs["Emission Color"].default_value = (0.24, 0.60, 1.0, 1.0)
    shader.inputs["Emission Strength"].default_value = 0.45
    curve.materials.append(material)
    action = _new_action(label, "offline_sleep.Zzz")
    for frame, z, scale in [(1, 1.35, 0.82), (31, 1.42, 1.0), (61, 1.38, 0.90), (91, 1.35, 0.82)]:
        label.location.z = z
        label.scale = Vector((scale, scale, scale))
        label.keyframe_insert(data_path="location", frame=frame)
        label.keyframe_insert(data_path="scale", frame=frame)
    _set_interpolation(action, "BEZIER")
    label.hide_render = True
    return label


def _configure_render() -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.fps = FPS
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.ffmpeg.format = "QUICKTIME"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = -0.85
    light_settings = {
        "AssemblyKeyLight": (560.0, (1.0, 0.90, 0.82)),
        "AssemblyFillLight": (360.0, (0.78, 0.88, 1.0)),
        "AssemblyRimLight": (520.0, (0.76, 1.0, 0.90)),
    }
    for name, (energy, color) in light_settings.items():
        light = bpy.data.objects.get(name)
        if light is not None and light.type == "LIGHT":
            light.data.energy = energy
            light.data.color = color
    if scene.world and scene.world.use_nodes:
        background = scene.world.node_tree.nodes.get("Background")
        if background is not None:
            background.inputs["Strength"].default_value = 0.24
    camera = scene.camera
    if camera is None:
        raise SystemExit("Assembly camera is missing")
    camera.location = Vector((1.52, -2.18, 1.56))
    camera.data.lens = 68
    _look_at(camera, Vector((0.0, 0.08, 0.84)))
    return camera


def _activate_actions(
    objects: dict[str, bpy.types.Object],
    actions: dict[str, bpy.types.Action],
) -> None:
    for name, action in actions.items():
        objects[name].animation_data.action = action


def _render_clip(
    output: Path,
    objects: dict[str, bpy.types.Object],
    actions: dict[str, bpy.types.Action],
    sleep_label: bpy.types.Object,
    frame_end: int,
    still_frame: int,
    stills_only: bool,
) -> None:
    _activate_actions(objects, actions)
    sleep_label.hide_render = actions["MintyPupRig"].name != "offline_sleep"
    scene = bpy.context.scene
    scene.frame_set(still_frame)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(output.with_suffix(".png"))
    bpy.ops.render.render(write_still=True)
    if stills_only:
        return
    scene.frame_start = 1
    scene.frame_end = frame_end
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.ffmpeg.format = "QUICKTIME"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"
    scene.render.filepath = str(output.with_suffix(""))
    bpy.ops.render.render(animation=True)
    generated = sorted(output.parent.glob(f"{output.stem}????-????.mov"))
    if len(generated) != 1:
        raise SystemExit(f"Expected one rendered movie for {output.name}, found {generated}")
    generated[0].replace(output)


def main() -> None:
    args = _arguments()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    source_blend = bpy.data.filepath
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(armatures) != 1:
        raise SystemExit(f"Expected one armature, found {len(armatures)}")
    armature = armatures[0]
    targets = {side: bpy.data.objects[f"HandTarget{side}"] for side in [".L", ".R"]}
    objects = {armature.name: armature, **{target.name: target for target in targets.values()}}
    camera = _configure_render()
    label = _sleep_label(camera)

    clips = {
        "online_idle": (_author_online_idle(armature, targets), 90, 46),
        "typing": (_author_typing(armature, targets), 60, 31),
        "offline_sleep": (_author_offline_sleep(armature, targets), 90, 31),
    }
    outputs: dict[str, dict[str, str]] = {}
    for name, (actions, frame_end, still_frame) in clips.items():
        output = output_dir / f"{name}.mov"
        _render_clip(
            output,
            objects,
            actions,
            label,
            frame_end,
            still_frame,
            args.stills_only,
        )
        outputs[name] = {
            "movie": str(output),
            "still": str(output.with_suffix(".png")),
            "frames": frame_end,
            "seconds": frame_end / FPS,
        }

    blend_path = output_dir / "minty_pup_motion_review.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    report = {
        "source": source_blend,
        "blend": str(blend_path),
        "fps": FPS,
        "stills_only": args.stills_only,
        "clips": outputs,
        "review_only_effects": ["Zzz text in offline_sleep"],
    }
    (output_dir / "motion-review-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_MOTION_REVIEW_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
