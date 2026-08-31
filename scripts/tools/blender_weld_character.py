"""Weld coincident GLB seam vertices without changing the visible character.

GLB exporters may duplicate vertices along UV or normal seams.  This script
tests the least-destructive cleanup before any voxel remesh or retopology.

Run with:
  blender --background --python scripts/tools/blender_weld_character.py -- \
    source.glb output.glb --threshold 0.00001
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected arguments after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--threshold", type=float, default=0.00001)
    return parser.parse_args(sys.argv[separator + 1 :])


def _triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _topology(obj: bpy.types.Object) -> dict[str, int]:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    visited: set[int] = set()
    component_sizes: list[int] = []
    for vertex in bm.verts:
        if vertex.index in visited:
            continue
        stack = [vertex]
        size = 0
        while stack:
            current = stack.pop()
            if current.index in visited:
                continue
            visited.add(current.index)
            size += 1
            for edge in current.link_edges:
                neighbor = edge.other_vert(current)
                if neighbor.index not in visited:
                    stack.append(neighbor)
        component_sizes.append(size)
    component_sizes.sort(reverse=True)
    report = {
        "vertices": len(obj.data.vertices),
        "edges": len(obj.data.edges),
        "polygons": len(obj.data.polygons),
        "triangles": _triangle_count(obj),
        "boundary_edges": sum(edge.is_boundary for edge in bm.edges),
        "non_manifold_edges": sum(not edge.is_manifold for edge in bm.edges),
        "connected_components": len(component_sizes),
        "largest_component_vertices": component_sizes[0] if component_sizes else 0,
    }
    bm.free()
    return report


def main() -> None:
    args = _arguments()
    source = args.source.expanduser().resolve()
    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if not source.is_file():
        raise SystemExit(f"Source GLB does not exist: {source}")
    if args.threshold <= 0.0:
        raise SystemExit("--threshold must be positive")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(source))
    if "FINISHED" not in result:
        raise SystemExit(f"GLB import failed: {result}")
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(mesh_objects) != 1:
        raise SystemExit(f"Expected one mesh object, found {len(mesh_objects)}")
    obj = mesh_objects[0]
    before = _topology(obj)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=args.threshold, use_unselected=False)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.name = "MintyPupWelded"
    obj.data.name = "MintyPupWeldedMesh"
    after = _topology(obj)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_apply=False,
    )
    blend_path = output.with_suffix(".blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    report = {
        "source": str(source),
        "output": str(output),
        "threshold": args.threshold,
        "before": before,
        "after": after,
        "removed_vertices": before["vertices"] - after["vertices"],
        "output_bytes": output.stat().st_size,
    }
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_WELD_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
