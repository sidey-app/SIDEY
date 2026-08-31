"""Assemble the rigged Minty Pup with SIDEY's independent station props.

This creates a review-only seated typing pose.  The pose validates scale,
chair clearance, laptop placement, and hand reach before motion authoring.

Run with:
  blender rigged-character.blend --background --python \
    scripts/tools/blender_assemble_station_preview.py -- station.glb output-dir
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected arguments after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("station", type=Path)
    parser.add_argument("output_dir", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _empty(name: str, location: tuple[float, float, float]) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.empty_display_type = "SPHERE"
    obj.empty_display_size = 0.025
    obj.hide_render = True
    return obj


def _pose_character(armature: bpy.types.Object) -> dict[str, bpy.types.Object]:
    armature.location = Vector((0.0, 0.38, 0.764))
    armature.scale = Vector((1.10, 1.10, 1.10))
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.location = Vector((0.0, 0.0, 0.0))
        bone.rotation_euler = Vector((0.0, 0.0, 0.0))
        bone.scale = Vector((1.0, 1.0, 1.0))

    for side in [".L", ".R"]:
        armature.pose.bones[f"thigh{side}"].rotation_euler.x = math.radians(70.0)
        armature.pose.bones[f"shin{side}"].rotation_euler.x = math.radians(-75.0)
    armature.pose.bones["neck"].rotation_euler.x = math.radians(7.0)
    armature.pose.bones["head"].rotation_euler.x = math.radians(4.0)

    controls: dict[str, bpy.types.Object] = {}
    for side, direction in [(".L", 1.0), (".R", -1.0)]:
        target = _empty(f"HandTarget{side}", (0.11 * direction, 0.10, 0.84))
        pole = _empty(f"ElbowPole{side}", (0.36 * direction, 0.37, 0.83))
        constraint = armature.pose.bones[f"forearm{side}"].constraints.new("IK")
        constraint.name = f"TypingIK{side}"
        constraint.target = target
        constraint.pole_target = pole
        constraint.chain_count = 2
        constraint.use_stretch = False
        constraint.pole_angle = math.radians(90.0 * direction)
        controls[f"target{side}"] = target
        controls[f"pole{side}"] = pole
    bpy.context.view_layer.update()
    return controls


def _setup_scene() -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"

    for existing in [obj for obj in scene.objects if obj.type in {"LIGHT", "CAMERA"}]:
        bpy.data.objects.remove(existing, do_unlink=True)
    world = bpy.data.worlds.get("StationAssemblyWorld") or bpy.data.worlds.new("StationAssemblyWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.018, 0.022, 0.030, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.40
    scene.world = world

    ground_material = bpy.data.materials.get("AssemblyGround") or bpy.data.materials.new("AssemblyGround")
    ground_material.use_nodes = True
    shader = ground_material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.032, 0.043, 0.055, 1.0)
    shader.inputs["Roughness"].default_value = 0.95
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "AssemblyGround"
    ground.data.materials.append(ground_material)

    lights = [
        ("Key", (-2.2, -2.8, 3.0), 900.0, 3.0, (1.0, 0.82, 0.69)),
        ("Fill", (2.4, -1.0, 2.1), 650.0, 2.7, (0.67, 0.84, 1.0)),
        ("Rim", (0.0, 2.6, 2.8), 950.0, 2.4, (0.65, 1.0, 0.88)),
    ]
    target = Vector((0.0, 0.05, 0.72))
    for name, location, energy, size, color in lights:
        data = bpy.data.lights.new(f"Assembly{name}Light", type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        data.use_shadow = False
        light = bpy.data.objects.new(f"Assembly{name}Light", data)
        scene.collection.objects.link(light)
        light.location = location
        _look_at(light, target)

    data = bpy.data.cameras.new("AssemblyCamera")
    camera = bpy.data.objects.new("AssemblyCamera", data)
    scene.collection.objects.link(camera)
    data.lens = 58
    scene.camera = camera
    return camera


def _render(
    output: Path,
    camera: bpy.types.Object,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    lens: float,
) -> None:
    camera.location = location
    camera.data.lens = lens
    _look_at(camera, Vector(target))
    bpy.context.scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    args = _arguments()
    station = args.station.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if not station.is_file():
        raise SystemExit(f"Station GLB does not exist: {station}")
    rigged_character = bpy.data.filepath

    meshes_before = set(obj.name for obj in bpy.context.scene.objects if obj.type == "MESH")
    bpy.ops.import_scene.gltf(filepath=str(station))
    station_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name not in meshes_before
    ]
    for obj in station_meshes:
        if obj.name == "LaptopBase":
            obj.scale = Vector((0.85, 0.80, 1.0))
        elif obj.name == "LaptopLid":
            obj.scale = Vector((0.85, 0.85, 0.60))
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    character_meshes = [
        obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name in meshes_before
    ]
    if len(armatures) != 1 or len(character_meshes) != 1:
        raise SystemExit("Expected one rigged character in the source Blender file")
    armature = armatures[0]
    armature.hide_render = True
    controls = _pose_character(armature)
    camera = _setup_scene()

    views = {
        "assembly_front": ((0.0, -2.85, 1.38), (0.0, 0.04, 0.70), 62.0),
        "assembly_hero": ((1.85, -2.55, 1.62), (0.0, 0.04, 0.72), 58.0),
        "assembly_side": ((2.55, 0.02, 1.42), (0.0, 0.12, 0.70), 62.0),
        "assembly_contact": ((1.45, -0.95, 1.78), (0.0, 0.06, 0.83), 68.0),
    }
    for name, (location, target, lens) in views.items():
        _render(output_dir / f"{name}.png", camera, location, target, lens)

    contact_errors: dict[str, float] = {}
    for side in [".L", ".R"]:
        wrist = armature.matrix_world @ armature.pose.bones[f"forearm{side}"].tail
        contact_errors[side] = round((wrist - controls[f"target{side}"].location).length, 6)

    blend_path = output_dir / "minty_pup_station_assembly.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    report = {
        "rigged_character": rigged_character,
        "station": str(station),
        "blend": str(blend_path),
        "character_location": [round(value, 4) for value in armature.location],
        "character_scale": [round(value, 4) for value in armature.scale],
        "laptop_scale": {
            obj.name: [round(value, 4) for value in obj.scale]
            for obj in station_meshes
            if obj.name in {"LaptopBase", "LaptopLid"}
        },
        "station_meshes": [obj.name for obj in station_meshes],
        "hand_target_error": contact_errors,
        "views": [str(output_dir / f"{name}.png") for name in views],
    }
    (output_dir / "assembly-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_ASSEMBLY_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
