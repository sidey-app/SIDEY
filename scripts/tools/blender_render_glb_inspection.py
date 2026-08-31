"""Render deterministic turnarounds and loose-component diagnostics for a GLB.

Run with:
  blender --background --python scripts/tools/blender_render_glb_inspection.py -- \
    source.glb output-directory
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected source and output directory after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def _triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = 0.78
    return material


def _setup_scene(objects: list[bpy.types.Object]) -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"

    minimum, maximum = _bounds(objects)
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    radius = max(size.x, size.y, size.z)

    world = bpy.data.worlds.new("InspectionWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.018, 0.022, 0.030, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    scene.world = world

    light_specs = [
        (center + Vector((-1.8, -2.2, 2.8)) * radius, 850.0, 2.8),
        (center + Vector((2.0, -0.7, 1.5)) * radius, 600.0, 2.4),
        (center + Vector((0.0, 2.0, 2.1)) * radius, 900.0, 2.4),
    ]
    for index, (location, energy, light_size) in enumerate(light_specs):
        data = bpy.data.lights.new(f"InspectionLight{index}", type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = light_size * radius
        light = bpy.data.objects.new(f"InspectionLight{index}", data)
        scene.collection.objects.link(light)
        light.location = location
        _look_at(light, center)

    camera_data = bpy.data.cameras.new("InspectionCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(size.x, size.z) * 1.16
    camera = bpy.data.objects.new("InspectionCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return camera


def _render_axis(
    output: Path,
    camera: bpy.types.Object,
    objects: list[bpy.types.Object],
    axis: Vector,
) -> None:
    minimum, maximum = _bounds(objects)
    center = (minimum + maximum) * 0.5
    radius = max(maximum - minimum)
    camera.location = center + axis * radius * 3.0
    _look_at(camera, center)
    bpy.context.scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def _topology_report(obj: bpy.types.Object) -> dict[str, object]:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    boundary_edges = sum(edge.is_boundary for edge in bm.edges)
    non_manifold_edges = sum(not edge.is_manifold for edge in bm.edges)
    degenerate_faces = sum(face.calc_area() <= 1e-12 for face in bm.faces)
    bm.free()
    return {
        "vertices": len(obj.data.vertices),
        "edges": len(obj.data.edges),
        "polygons": len(obj.data.polygons),
        "triangles": _triangle_count(obj),
        "boundary_edges": boundary_edges,
        "non_manifold_edges": non_manifold_edges,
        "degenerate_faces": degenerate_faces,
        "uv_layers": [layer.name for layer in obj.data.uv_layers],
    }


def _separate_loose(obj: bpy.types.Object) -> list[bpy.types.Object]:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [candidate for candidate in bpy.context.scene.objects if candidate.type == "MESH"]


def main() -> None:
    args = _arguments()
    source = args.source.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if not source.is_file():
        raise SystemExit(f"GLB does not exist: {source}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(source))
    if "FINISHED" not in result:
        raise SystemExit(f"GLB import failed: {result}")
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(mesh_objects) != 1:
        raise SystemExit(f"Expected one mesh object, found {len(mesh_objects)}")
    source_object = mesh_objects[0]
    topology = _topology_report(source_object)
    camera = _setup_scene(mesh_objects)

    axes = {
        "front": Vector((0.0, -1.0, 0.0)),
        "right": Vector((1.0, 0.0, 0.0)),
        "back": Vector((0.0, 1.0, 0.0)),
        "left": Vector((-1.0, 0.0, 0.0)),
    }
    for name, axis in axes.items():
        _render_axis(output_dir / f"textured_{name}.png", camera, mesh_objects, axis)

    components = _separate_loose(source_object)
    palette = [
        (0.95, 0.25, 0.28, 1.0),
        (0.16, 0.66, 0.96, 1.0),
        (0.35, 0.86, 0.44, 1.0),
        (0.98, 0.66, 0.15, 1.0),
        (0.69, 0.35, 0.95, 1.0),
        (0.95, 0.31, 0.72, 1.0),
        (0.20, 0.84, 0.78, 1.0),
        (0.95, 0.90, 0.24, 1.0),
        (0.40, 0.48, 0.96, 1.0),
        (0.96, 0.47, 0.24, 1.0),
        (0.55, 0.88, 0.23, 1.0),
        (0.73, 0.74, 0.78, 1.0),
    ]
    diagnostic_materials = [
        _material(f"ComponentColor{index:02d}", color)
        for index, color in enumerate(palette)
    ]
    components.sort(key=_triangle_count, reverse=True)
    for index, component in enumerate(components):
        component.data.materials.clear()
        component.data.materials.append(diagnostic_materials[index % len(diagnostic_materials)])

    for name, axis in axes.items():
        _render_axis(output_dir / f"components_{name}.png", camera, components, axis)

    component_triangles = [_triangle_count(component) for component in components]
    report = {
        "source": str(source),
        "source_bytes": source.stat().st_size,
        "topology": topology,
        "materials": [material.name for material in bpy.data.materials if not material.name.startswith("ComponentColor")],
        "images": [
            {"name": image.name, "size": list(image.size), "packed": image.packed_file is not None}
            for image in bpy.data.images
        ],
        "loose_components": {
            "count": len(components),
            "largest_triangles": max(component_triangles),
            "median_triangles": statistics.median(component_triangles),
            "under_100_triangles": sum(value < 100 for value in component_triangles),
            "top_20_triangles": component_triangles[:20],
        },
    }
    (output_dir / "inspection-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_INSPECTION_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
