"""Cluster a textured GLB's vertices by sampled base color and report bounds.

The report is intended to help build deterministic review rigs for generated
assets that arrive as a single object without semantic mesh names.
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
    parser.add_argument("source", type=Path)
    parser.add_argument("--clusters", type=int, default=10)
    return parser.parse_args(sys.argv[separator + 1 :])


def _base_color_image() -> bpy.types.Image:
    for image in bpy.data.images:
        name = image.name.lower()
        if "base" in name and "color" in name:
            return image
    raise SystemExit("Could not find a base-color image")


def _sample_vertex_colors(obj: bpy.types.Object, image: bpy.types.Image) -> list[tuple[Vector, Vector]]:
    mesh = obj.data
    if not mesh.uv_layers.active:
        raise SystemExit("Mesh has no active UV layer")
    width, height = image.size
    pixels = image.pixels[:]
    uv_data = mesh.uv_layers.active.data
    vertex_uvs: list[Vector | None] = [None] * len(mesh.vertices)
    for loop in mesh.loops:
        vertex_index = loop.vertex_index
        if vertex_uvs[vertex_index] is None:
            vertex_uvs[vertex_index] = uv_data[loop.index].uv.copy()

    samples: list[tuple[Vector, Vector]] = []
    for vertex, uv in zip(mesh.vertices, vertex_uvs, strict=True):
        if uv is None:
            continue
        x = min(width - 1, max(0, round((uv.x % 1.0) * (width - 1))))
        y = min(height - 1, max(0, round((uv.y % 1.0) * (height - 1))))
        offset = (y * width + x) * 4
        color = Vector((pixels[offset], pixels[offset + 1], pixels[offset + 2]))
        samples.append((vertex.co.copy(), color))
    return samples


def _initial_centers(colors: list[Vector], count: int) -> list[Vector]:
    centers = [max(colors, key=lambda color: color.length_squared).copy()]
    while len(centers) < count:
        candidate = max(
            colors,
            key=lambda color: min((color - center).length_squared for center in centers),
        )
        centers.append(candidate.copy())
    return centers


def _cluster(samples: list[tuple[Vector, Vector]], count: int) -> tuple[list[Vector], list[int]]:
    colors = [color for _, color in samples]
    centers = _initial_centers(colors, count)
    assignments = [0] * len(samples)
    for _ in range(20):
        changed = False
        for index, color in enumerate(colors):
            cluster_index = min(
                range(count),
                key=lambda candidate: (color - centers[candidate]).length_squared,
            )
            if assignments[index] != cluster_index:
                assignments[index] = cluster_index
                changed = True
        sums = [Vector((0.0, 0.0, 0.0)) for _ in range(count)]
        sizes = [0] * count
        for color, cluster_index in zip(colors, assignments, strict=True):
            sums[cluster_index] += color
            sizes[cluster_index] += 1
        for index in range(count):
            if sizes[index]:
                centers[index] = sums[index] / sizes[index]
        if not changed:
            break
    return centers, assignments


def main() -> None:
    args = _arguments()
    source = args.source.expanduser().resolve()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(mesh_objects) != 1:
        raise SystemExit(f"Expected one mesh object, found {len(mesh_objects)}")
    obj = mesh_objects[0]
    samples = _sample_vertex_colors(obj, _base_color_image())
    centers, assignments = _cluster(samples, args.clusters)

    clusters = []
    for index, center in enumerate(centers):
        points = [samples[sample_index][0] for sample_index, value in enumerate(assignments) if value == index]
        minimum = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
        maximum = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
        mean = sum(points, Vector()) / len(points)
        clusters.append(
            {
                "cluster": index,
                "vertices": len(points),
                "color_linear": [round(value, 5) for value in center],
                "minimum": [round(value, 5) for value in minimum],
                "maximum": [round(value, 5) for value in maximum],
                "mean": [round(value, 5) for value in mean],
            }
        )
    clusters.sort(key=lambda item: item["vertices"], reverse=True)
    report = {
        "source": str(source),
        "object": obj.name,
        "vertices": len(samples),
        "bounds": {
            "minimum": [round(value, 5) for value in min((point for point, _ in samples), key=lambda point: point.length_squared)],
            "dimensions": [round(value, 5) for value in obj.dimensions],
        },
        "clusters": clusters,
    }
    print("SIDEY_REGION_REPORT=" + json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
