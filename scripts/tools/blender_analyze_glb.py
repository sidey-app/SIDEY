"""Print structural and geometry statistics for a GLB imported into Blender.

Run with:
  blender --background --python scripts/tools/blender_analyze_glb.py -- model.glb
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


def _argument_path() -> Path:
    try:
        separator = sys.argv.index("--")
        return Path(sys.argv[separator + 1]).expanduser().resolve()
    except (ValueError, IndexError) as error:
        raise SystemExit("Expected a GLB path after --") from error


def _should_separate_loose_parts() -> bool:
    try:
        separator = sys.argv.index("--")
    except ValueError:
        return False
    return "--separate-loose" in sys.argv[separator + 2 :]


def _mesh_report(obj: bpy.types.Object) -> dict[str, object]:
    mesh = obj.data
    mesh.calc_loop_triangles()
    dimensions = [round(float(value), 6) for value in obj.dimensions]
    return {
        "name": obj.name,
        "mesh": mesh.name,
        "vertices": len(mesh.vertices),
        "edges": len(mesh.edges),
        "polygons": len(mesh.polygons),
        "triangles": len(mesh.loop_triangles),
        "materials": [slot.material.name if slot.material else "" for slot in obj.material_slots],
        "shape_keys": list(mesh.shape_keys.key_blocks.keys()) if mesh.shape_keys else [],
        "vertex_groups": len(obj.vertex_groups),
        "dimensions": dimensions,
        "parent": obj.parent.name if obj.parent else "",
        "modifiers": [modifier.type for modifier in obj.modifiers],
    }


def main() -> None:
    source_path = _argument_path()
    if not source_path.is_file():
        raise SystemExit(f"GLB does not exist: {source_path}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(source_path))
    if "FINISHED" not in result:
        raise SystemExit(f"GLB import failed: {result}")

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if _should_separate_loose_parts():
        for obj in list(mesh_objects):
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.mesh.separate(type="LOOSE")
            bpy.ops.object.mode_set(mode="OBJECT")
        mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    mesh_reports = [_mesh_report(obj) for obj in mesh_objects]
    mesh_reports.sort(key=lambda item: int(item["triangles"]), reverse=True)
    report = {
        "source": str(source_path),
        "file_bytes": source_path.stat().st_size,
        "objects": len(bpy.context.scene.objects),
        "mesh_object_count": len(mesh_reports),
        "mesh_objects": mesh_reports[:50] if _should_separate_loose_parts() else mesh_reports,
        "mesh_triangle_buckets": {
            "at_least_10000": sum(int(item["triangles"]) >= 10_000 for item in mesh_reports),
            "at_least_1000": sum(int(item["triangles"]) >= 1_000 for item in mesh_reports),
            "at_least_100": sum(int(item["triangles"]) >= 100 for item in mesh_reports),
            "under_100": sum(int(item["triangles"]) < 100 for item in mesh_reports),
        },
        "armatures": [
            {
                "name": obj.name,
                "bones": len(obj.data.bones),
                "children": [child.name for child in obj.children],
            }
            for obj in armatures
        ],
        "materials": [material.name for material in bpy.data.materials],
        "images": [
            {
                "name": image.name,
                "size": list(image.size),
                "packed": image.packed_file is not None,
            }
            for image in bpy.data.images
        ],
    }
    print("SIDEY_GLB_REPORT=" + json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
