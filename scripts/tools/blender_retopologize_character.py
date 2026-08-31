"""Create a continuous review topology from a fragmented generated character.

This script deliberately stops before texture transfer or rigging.  The output
must pass silhouette and connected-component review first.

Run with:
  blender --background --python scripts/tools/blender_retopologize_character.py -- \
    source.glb output-directory --voxel-size 0.004 --target-faces 8000
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected arguments after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--voxel-size", type=float, default=0.004)
    parser.add_argument("--target-faces", type=int, default=8000)
    return parser.parse_args(sys.argv[separator + 1 :])


def _triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _topology(obj: bpy.types.Object) -> dict[str, int]:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.edges.ensure_lookup_table()
    report = {
        "vertices": len(obj.data.vertices),
        "edges": len(obj.data.edges),
        "polygons": len(obj.data.polygons),
        "triangles": _triangle_count(obj),
        "boundary_edges": sum(edge.is_boundary for edge in bm.edges),
        "non_manifold_edges": sum(not edge.is_manifold for edge in bm.edges),
    }
    bm.free()
    return report


def _bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _review_material() -> bpy.types.Material:
    material = bpy.data.materials.new("RetopologyReview")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.42, 0.52, 0.66, 1.0)
    shader.inputs["Roughness"].default_value = 0.82
    return material


def _keep_largest_component(obj: bpy.types.Object) -> tuple[bpy.types.Object, int]:
    """Remove remesh specks while preserving the dominant character surface."""

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    components = [candidate for candidate in bpy.context.scene.objects if candidate.type == "MESH" and not candidate.hide_viewport]
    components.sort(key=_triangle_count, reverse=True)
    largest = components[0]
    for component in components[1:]:
        bpy.data.objects.remove(component, do_unlink=True)
    largest.name = "MintyPupRetopology"
    largest.data.name = "MintyPupRetopologyMesh"
    bpy.ops.object.select_all(action="DESELECT")
    largest.select_set(True)
    bpy.context.view_layer.objects.active = largest
    return largest, len(components) - 1


def _setup_render(obj: bpy.types.Object) -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"

    minimum, maximum = _bounds(obj)
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    radius = max(size.x, size.y, size.z)

    world = bpy.data.worlds.new("RetopologyWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.018, 0.022, 0.030, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    scene.world = world

    for index, (offset, energy, light_size) in enumerate(
        [
            ((-1.8, -2.2, 2.8), 850.0, 2.8),
            ((2.0, -0.7, 1.5), 600.0, 2.4),
            ((0.0, 2.0, 2.1), 900.0, 2.4),
        ]
    ):
        data = bpy.data.lights.new(f"RetopologyLight{index}", type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = light_size * radius
        light = bpy.data.objects.new(f"RetopologyLight{index}", data)
        scene.collection.objects.link(light)
        light.location = center + Vector(offset) * radius
        _look_at(light, center)

    camera_data = bpy.data.cameras.new("RetopologyCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(size.x, size.z) * 1.16
    camera = bpy.data.objects.new("RetopologyCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def _render(
    output: Path,
    camera: bpy.types.Object,
    obj: bpy.types.Object,
    axis: Vector,
) -> None:
    minimum, maximum = _bounds(obj)
    center = (minimum + maximum) * 0.5
    radius = max(maximum - minimum)
    camera.location = center + axis * radius * 3.0
    _look_at(camera, center)
    bpy.context.scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    args = _arguments()
    source = args.source.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if not source.is_file():
        raise SystemExit(f"Source GLB does not exist: {source}")
    if args.voxel_size <= 0.0:
        raise SystemExit("--voxel-size must be positive")
    if args.target_faces <= 0:
        raise SystemExit("--target-faces must be positive")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(source))
    if "FINISHED" not in result:
        raise SystemExit(f"GLB import failed: {result}")
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(mesh_objects) != 1:
        raise SystemExit(f"Expected one mesh object, found {len(mesh_objects)}")
    source_object = mesh_objects[0]
    source_object.name = "MintyPupSource"
    source_topology = _topology(source_object)

    candidate = source_object.copy()
    candidate.data = source_object.data.copy()
    bpy.context.scene.collection.objects.link(candidate)
    candidate.name = "MintyPupRetopology"
    source_object.hide_viewport = True
    source_object.hide_render = True

    bpy.ops.object.select_all(action="DESELECT")
    candidate.select_set(True)
    bpy.context.view_layer.objects.active = candidate
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    candidate.data.remesh_voxel_size = args.voxel_size
    candidate.data.remesh_voxel_adaptivity = 0.0
    candidate.data.use_remesh_fix_poles = True
    candidate.data.use_remesh_preserve_volume = True
    bpy.ops.object.voxel_remesh()
    voxel_topology = _topology(candidate)

    bpy.ops.object.quadriflow_remesh(
        use_mesh_symmetry=True,
        use_preserve_sharp=False,
        use_preserve_boundary=False,
        preserve_attributes=False,
        smooth_normals=True,
        mode="FACES",
        target_faces=args.target_faces,
        seed=0,
    )
    candidate, removed_components = _keep_largest_component(candidate)
    candidate.data.materials.clear()
    candidate.data.materials.append(_review_material())
    bpy.ops.object.shade_smooth_by_angle()
    final_topology = _topology(candidate)

    bpy.ops.object.select_all(action="DESELECT")
    candidate.select_set(True)
    bpy.context.view_layer.objects.active = candidate
    glb_path = output_dir / "minty_pup_v2_retopology.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_normals=True,
        export_materials="EXPORT",
        export_apply=False,
    )

    camera = _setup_render(candidate)
    axes = {
        "front": Vector((0.0, -1.0, 0.0)),
        "right": Vector((1.0, 0.0, 0.0)),
        "back": Vector((0.0, 1.0, 0.0)),
        "left": Vector((-1.0, 0.0, 0.0)),
    }
    for name, axis in axes.items():
        _render(output_dir / f"retopology_{name}.png", camera, candidate, axis)

    blend_path = output_dir / "minty_pup_v2_retopology.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    report = {
        "source": str(source),
        "voxel_size": args.voxel_size,
        "target_faces": args.target_faces,
        "source_topology": source_topology,
        "voxel_topology": voxel_topology,
        "removed_components": removed_components,
        "final_topology": final_topology,
        "outputs": {"glb": str(glb_path), "blend": str(blend_path)},
    }
    (output_dir / "retopology-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_RETOPOLOGY_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
