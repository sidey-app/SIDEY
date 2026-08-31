"""Render deterministic pose probes for the Minty Pup rig.

Run with:
  blender rigged.blend --background --python \
    scripts/tools/blender_render_rig_deformation_probe.py -- output-directory
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
    parser.add_argument("output_dir", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def _bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return minimum, maximum


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _setup_scene(mesh: bpy.types.Object) -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.camera = None

    minimum, maximum = _bounds(mesh)
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    radius = max(size)

    world = bpy.data.worlds.get("RigProbeWorld") or bpy.data.worlds.new("RigProbeWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.018, 0.022, 0.030, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    scene.world = world

    for existing in [obj for obj in scene.objects if obj.type in {"LIGHT", "CAMERA"}]:
        bpy.data.objects.remove(existing, do_unlink=True)
    light_specs = [
        (Vector((-1.8, -2.2, 2.8)), 850.0, 2.8),
        (Vector((2.0, -0.7, 1.5)), 600.0, 2.4),
        (Vector((0.0, 2.0, 2.1)), 900.0, 2.4),
    ]
    for index, (offset, energy, size_scale) in enumerate(light_specs):
        data = bpy.data.lights.new(f"RigProbeLight{index}", type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size_scale * radius
        data.use_shadow = False
        light = bpy.data.objects.new(f"RigProbeLight{index}", data)
        scene.collection.objects.link(light)
        light.location = center + offset * radius
        _look_at(light, center)

    camera_data = bpy.data.cameras.new("RigProbeCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(size.x, size.z) * 1.22
    camera = bpy.data.objects.new("RigProbeCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def _reset_pose(armature: bpy.types.Object) -> None:
    for bone in armature.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.location = Vector((0.0, 0.0, 0.0))
        bone.rotation_euler = Vector((0.0, 0.0, 0.0))
        bone.scale = Vector((1.0, 1.0, 1.0))


def _apply_pose(armature: bpy.types.Object, rotations: dict[str, tuple[float, float, float]]) -> None:
    _reset_pose(armature)
    for name, degrees in rotations.items():
        armature.pose.bones[name].rotation_euler = Vector(
            tuple(math.radians(value) for value in degrees)
        )
    bpy.context.view_layer.update()


def _render(output: Path, camera: bpy.types.Object, mesh: bpy.types.Object, view: str) -> None:
    minimum, maximum = _bounds(mesh)
    center = (minimum + maximum) * 0.5
    radius = max(maximum - minimum)
    axes = {
        "front": Vector((0.0, -1.0, 0.0)),
        "three_quarter": Vector((1.25, -2.0, 0.55)).normalized(),
        "right": Vector((1.0, 0.0, 0.0)),
    }
    camera.location = center + axes[view] * radius * 3.0
    _look_at(camera, center)
    bpy.context.scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    args = _arguments()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(meshes) != 1 or len(armatures) != 1:
        raise SystemExit(f"Expected one mesh and one armature, found {len(meshes)} and {len(armatures)}")
    mesh = meshes[0]
    armature = armatures[0]
    camera = _setup_scene(mesh)
    armature.hide_render = True

    poses = {
        "rest": {},
        "elbow_x": {"forearm.L": (55.0, 0.0, 0.0), "forearm.R": (-55.0, 0.0, 0.0)},
        "elbow_z": {"forearm.L": (0.0, 0.0, -55.0), "forearm.R": (0.0, 0.0, 55.0)},
        "shoulder_x": {"upper_arm.L": (35.0, 0.0, 0.0), "upper_arm.R": (-35.0, 0.0, 0.0)},
        "shoulder_z": {"upper_arm.L": (0.0, 0.0, -35.0), "upper_arm.R": (0.0, 0.0, 35.0)},
        "sit_x_positive": {
            "thigh.L": (70.0, 0.0, 0.0),
            "thigh.R": (-70.0, 0.0, 0.0),
            "shin.L": (-75.0, 0.0, 0.0),
            "shin.R": (75.0, 0.0, 0.0),
        },
        "sit_x_same": {
            "thigh.L": (70.0, 0.0, 0.0),
            "thigh.R": (70.0, 0.0, 0.0),
            "shin.L": (-75.0, 0.0, 0.0),
            "shin.R": (-75.0, 0.0, 0.0),
        },
        "head": {"neck": (8.0, 0.0, 0.0), "head": (18.0, 0.0, 10.0)},
    }
    outputs: list[str] = []
    for pose_name, rotations in poses.items():
        _apply_pose(armature, rotations)
        views = ["front", "right"] if pose_name.startswith("sit") else ["front", "three_quarter"]
        for view in views:
            output = output_dir / f"{pose_name}_{view}.png"
            _render(output, camera, mesh, view)
            outputs.append(str(output))
    _reset_pose(armature)
    report = {"blend": bpy.data.filepath, "poses": poses, "renders": outputs}
    (output_dir / "probe-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_RIG_PROBE_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
