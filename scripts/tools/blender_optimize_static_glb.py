"""Create a texture-preserving static GLB candidate from a dense source GLB.

This intentionally uses Blender's collapse decimator instead of a remesh. A
remesh would destroy the source UVs and require a separate texture-baking pass.
The result is suitable for visual/performance evaluation only; it does not add
a rig or make a fused character/desk asset independently animatable.

Run with:
  blender --background --python scripts/tools/blender_optimize_static_glb.py -- \
    source.glb output.glb --target-triangles 100000 --preview preview.png
"""

from __future__ import annotations

import argparse
import json
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
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--target-triangles", type=int, required=True)
    parser.add_argument("--max-texture-size", type=int)
    parser.add_argument("--preview", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def _triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _world_bounds(mesh_objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for obj in mesh_objects for corner in obj.bound_box]
    minimum = Vector((min(point.x for point in corners), min(point.y for point in corners), min(point.z for point in corners)))
    maximum = Vector((max(point.x for point in corners), max(point.y for point in corners), max(point.z for point in corners)))
    return minimum, maximum


def _render_preview(path: Path, mesh_objects: list[bpy.types.Object]) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = True
    scene.render.filepath = str(path)
    scene.render.image_settings.color_mode = "RGBA"

    minimum, maximum = _world_bounds(mesh_objects)
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    radius = max(size.x, size.y, size.z)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = center + Vector((radius * 1.35, -radius * 1.7, radius * 0.65))
    camera_data.lens = 58
    _look_at(camera, center + Vector((0.0, 0.0, size.z * 0.03)))
    scene.camera = camera

    world = bpy.data.worlds.new("PreviewWorld") if scene.world is None else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.035, 0.045, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45

    for index, (offset, energy, size_value) in enumerate(
        [
            ((-1.5, -2.0, 2.7), 950.0, 4.0),
            ((2.0, -0.5, 1.5), 650.0, 3.0),
            ((0.0, 2.0, 2.2), 850.0, 3.0),
        ]
    ):
        light_data = bpy.data.lights.new(f"PreviewLight{index}", type="AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size_value
        light = bpy.data.objects.new(f"PreviewLight{index}", light_data)
        scene.collection.objects.link(light)
        light.location = center + Vector(offset) * radius
        _look_at(light, center)

    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    args = _arguments()
    source = args.source.expanduser().resolve()
    output = args.output.expanduser().resolve()
    preview = args.preview.expanduser().resolve() if args.preview else None
    if not source.is_file():
        raise SystemExit(f"Source GLB does not exist: {source}")
    if args.target_triangles <= 0:
        raise SystemExit("--target-triangles must be positive")
    if args.max_texture_size is not None and args.max_texture_size <= 0:
        raise SystemExit("--max-texture-size must be positive")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    imported = bpy.ops.import_scene.gltf(filepath=str(source))
    if "FINISHED" not in imported:
        raise SystemExit(f"GLB import failed: {imported}")

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not mesh_objects:
        raise SystemExit("Imported GLB contains no mesh objects")

    if args.max_texture_size is not None:
        for image in bpy.data.images:
            width, height = image.size
            longest_side = max(width, height)
            if longest_side <= args.max_texture_size:
                continue
            scale = args.max_texture_size / longest_side
            image.scale(max(1, round(width * scale)), max(1, round(height * scale)))

    before = sum(_triangle_count(obj) for obj in mesh_objects)
    ratio = min(1.0, args.target_triangles / before)
    for obj in mesh_objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new(name="SIDEY Static Decimate", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)

    after = sum(_triangle_count(obj) for obj in mesh_objects)
    for obj in mesh_objects:
        obj.name = "PuppyDeskStation"
        obj.data.name = "PuppyDeskStationMesh"

    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )

    if preview:
        _render_preview(preview, mesh_objects)

    report = {
        "source": str(source),
        "output": str(output),
        "source_triangles": before,
        "target_triangles": args.target_triangles,
        "output_triangles": after,
        "ratio": ratio,
        "output_bytes": output.stat().st_size,
        "max_texture_size": args.max_texture_size,
        "preview": str(preview) if preview else None,
        "materials": [material.name for material in bpy.data.materials],
        "images": [
            {"name": image.name, "size": list(image.size), "packed": image.packed_file is not None}
            for image in bpy.data.images
        ],
    }
    print("SIDEY_OPTIMIZE_REPORT=" + json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
