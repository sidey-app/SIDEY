"""Report connected mesh components from a Blender authoring file.

This inspects Blender's actual indexed mesh before a GLB exporter duplicates
vertices at UV or normal seams.

Run with:
  blender file.blend --background --python \
    scripts/tools/blender_report_mesh_components.py -- report.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected arguments after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def _rounded(vector: Vector) -> list[float]:
    return [round(value, 6) for value in vector]


def main() -> None:
    args = _arguments()
    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(mesh_objects) != 1:
        raise SystemExit(f"Expected one mesh object, found {len(mesh_objects)}")

    obj = mesh_objects[0]
    mesh = obj.data
    adjacency: dict[int, set[int]] = defaultdict(set)
    for edge in mesh.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)

    component_by_vertex: dict[int, int] = {}
    components: list[list[int]] = []
    for vertex in mesh.vertices:
        if vertex.index in component_by_vertex:
            continue
        component_index = len(components)
        stack = [vertex.index]
        indices: list[int] = []
        while stack:
            current = stack.pop()
            if current in component_by_vertex:
                continue
            component_by_vertex[current] = component_index
            indices.append(current)
            stack.extend(adjacency[current] - component_by_vertex.keys())
        components.append(indices)

    polygon_counts = [0] * len(components)
    triangle_counts = [0] * len(components)
    edge_face_counts: dict[tuple[int, int], int] = defaultdict(int)
    for polygon in mesh.polygons:
        component_index = component_by_vertex[polygon.vertices[0]]
        polygon_counts[component_index] += 1
        triangle_counts[component_index] += max(1, len(polygon.vertices) - 2)
        for first, second in polygon.edge_keys:
            edge_face_counts[tuple(sorted((first, second)))] += 1

    boundary_counts = [0] * len(components)
    non_manifold_counts = [0] * len(components)
    for edge in mesh.edges:
        first, second = edge.vertices
        component_index = component_by_vertex[first]
        face_count = edge_face_counts[tuple(sorted((first, second)))]
        if face_count == 1:
            boundary_counts[component_index] += 1
        if face_count != 2:
            non_manifold_counts[component_index] += 1

    report_components = []
    for index, vertex_indices in enumerate(components):
        positions = [obj.matrix_world @ mesh.vertices[i].co for i in vertex_indices]
        minimum = Vector(tuple(min(position[axis] for position in positions) for axis in range(3)))
        maximum = Vector(tuple(max(position[axis] for position in positions) for axis in range(3)))
        report_components.append(
            {
                "component": index,
                "vertices": len(vertex_indices),
                "polygons": polygon_counts[index],
                "triangles": triangle_counts[index],
                "boundary_edges": boundary_counts[index],
                "non_manifold_edges": non_manifold_counts[index],
                "bounds_min": _rounded(minimum),
                "bounds_max": _rounded(maximum),
                "center": _rounded((minimum + maximum) * 0.5),
                "size": _rounded(maximum - minimum),
            }
        )

    report_components.sort(key=lambda component: component["triangles"], reverse=True)
    report = {
        "blend": bpy.data.filepath,
        "object": obj.name,
        "component_count": len(report_components),
        "components": report_components,
    }
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_COMPONENT_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
