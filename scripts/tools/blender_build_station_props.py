"""Build SIDEY's reviewable low-poly desk and laptop props.

The output is intentionally deterministic and keeps the desk, laptop base, and
laptop lid as separate nodes.  It is a look-development candidate, not a final
approved production asset.

Run with:
  blender --background --python scripts/tools/blender_build_station_props.py -- \
    artifacts/prop-review/desk_laptop_v1
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
        raise SystemExit("Expected an output directory after --") from error

    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--include-chair", action="store_true")
    parser.add_argument("--asset-name", default="sidey_desk_laptop_v1")
    return parser.parse_args(sys.argv[separator + 1 :])


def _material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    roughness: float = 0.78,
    metallic: float = 0.0,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission_strength > 0.0:
        shader.inputs["Emission Color"].default_value = color
        shader.inputs["Emission Strength"].default_value = emission_strength
    return material


def _apply_modifiers(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def _rounded_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    bevel_width: float,
    *,
    bevel_segments: int = 3,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    bevel = obj.modifiers.new(name="Soft edges", type="BEVEL")
    bevel.width = bevel_width
    bevel.segments = bevel_segments
    bevel.limit_method = "ANGLE"
    bevel.harden_normals = True
    obj.data.materials.append(material)
    _apply_modifiers(obj)

    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth_by_angle()
    return obj


def _flat_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
) -> bpy.types.Object:
    """Create a tiny box without bevel geometry.

    Individual keyboard keys are below the final overlay's pixel scale. Their
    silhouette matters, but spending rounded-box topology on every key does not.
    """

    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def _cylinder(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 16,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    bevel = obj.modifiers.new(name="Soft edges", type="BEVEL")
    bevel.width = min(radius * 0.25, 0.008)
    bevel.segments = 2
    _apply_modifiers(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth_by_angle()
    return obj


def _join(objects: list[bpy.types.Object], name: str) -> bpy.types.Object:
    if not objects:
        raise ValueError(f"Cannot create {name} from an empty object list")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    joined.data.name = f"{name}Mesh"
    return joined


def _set_origin(obj: bpy.types.Object, location: tuple[float, float, float]) -> None:
    scene = bpy.context.scene
    previous_cursor = scene.cursor.location.copy()
    scene.cursor.location = location
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    scene.cursor.location = previous_cursor


def _extruded_xz_shape(
    name: str,
    points: list[tuple[float, float]],
    *,
    center: tuple[float, float, float],
    depth: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    """Create a small extruded silhouette in the XZ plane."""

    half_depth = depth * 0.5
    vertices = [
        (center[0] + x, center[1] - half_depth, center[2] + z)
        for x, z in points
    ] + [
        (center[0] + x, center[1] + half_depth, center[2] + z)
        for x, z in points
    ]
    count = len(points)
    faces: list[tuple[int, ...]] = [
        tuple(reversed(range(count))),
        tuple(range(count, count * 2)),
    ]
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, next_index + count, index + count))

    mesh = bpy.data.meshes.new(f"{name}Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    bevel = obj.modifiers.new(name="Soft logo edge", type="BEVEL")
    bevel.width = 0.0025
    bevel.segments = 2
    _apply_modifiers(obj)
    return obj


def _apple_logo(
    center: tuple[float, float, float],
    material: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Create a small bitten-apple silhouette for the review laptop lid."""

    scale = 0.075
    body_outline = [
        (-0.04, 0.48),
        (-0.23, 0.57),
        (-0.43, 0.49),
        (-0.58, 0.28),
        (-0.62, 0.02),
        (-0.53, -0.25),
        (-0.36, -0.50),
        (-0.18, -0.57),
        (0.00, -0.47),
        (0.17, -0.57),
        (0.34, -0.50),
        (0.50, -0.26),
        (0.57, -0.05),
        (0.43, 0.04),
        (0.35, 0.16),
        (0.39, 0.30),
        (0.52, 0.39),
        (0.39, 0.50),
        (0.19, 0.57),
        (0.03, 0.49),
    ]
    leaf_outline = [
        (-0.03, 0.67),
        (0.06, 0.84),
        (0.27, 0.90),
        (0.22, 0.72),
        (0.08, 0.61),
    ]
    body = _extruded_xz_shape(
        "LaptopAppleLogoBody",
        [(x * scale, z * scale) for x, z in body_outline],
        center=center,
        depth=0.010,
        material=material,
    )
    leaf = _extruded_xz_shape(
        "LaptopAppleLogoLeaf",
        [(x * scale, z * scale) for x, z in leaf_outline],
        center=center,
        depth=0.010,
        material=material,
    )
    return [body, leaf]


def _make_desk(
    cream: bpy.types.Material,
    silver: bpy.types.Material,
) -> bpy.types.Object:
    parts = [
        _rounded_box("DeskTop", (0.0, 0.0, 0.70), (1.20, 0.68, 0.10), cream, 0.045, bevel_segments=4),
        _rounded_box("DeskLeftPanel", (-0.49, 0.02, 0.35), (0.15, 0.52, 0.62), cream, 0.060, bevel_segments=4),
        _rounded_box("DeskRightPanel", (0.49, 0.02, 0.35), (0.15, 0.52, 0.62), cream, 0.060, bevel_segments=4),
        _rounded_box("DeskFrontApron", (0.0, -0.285, 0.62), (0.73, 0.055, 0.14), cream, 0.025),
        _rounded_box("DeskDrawerFace", (0.0, -0.319, 0.63), (0.48, 0.018, 0.095), cream, 0.014),
        _rounded_box("DeskDrawerHandle", (0.0, -0.333, 0.63), (0.14, 0.018, 0.026), silver, 0.012),
        _rounded_box("DeskLeftFoot", (-0.49, -0.005, 0.052), (0.19, 0.56, 0.055), cream, 0.025),
        _rounded_box("DeskRightFoot", (0.49, -0.005, 0.052), (0.19, 0.56, 0.055), cream, 0.025),
    ]
    desk = _join(parts, "Desk")
    _set_origin(desk, (0.0, 0.0, 0.0))
    return desk


def _make_laptop_base(
    silver: bpy.types.Material,
    dark: bpy.types.Material,
) -> bpy.types.Object:
    base_top = 0.812
    parts = [
        _rounded_box("LaptopBaseShell", (0.0, 0.025, 0.785), (0.64, 0.43, 0.052), silver, 0.024, bevel_segments=4),
        _rounded_box("LaptopKeyboardWell", (0.0, -0.005, base_top + 0.004), (0.52, 0.18, 0.010), dark, 0.010),
        _rounded_box("LaptopTrackpad", (0.0, 0.150, base_top + 0.005), (0.23, 0.080, 0.009), dark, 0.012),
    ]

    row_specs = [
        (-0.065, 11, 0.039),
        (-0.025, 11, 0.039),
        (0.015, 10, 0.042),
        (0.055, 9, 0.045),
    ]
    for row_index, (y, count, key_width) in enumerate(row_specs):
        total_width = count * key_width + (count - 1) * 0.007
        start_x = -total_width * 0.5 + key_width * 0.5
        for key_index in range(count):
            parts.append(
                _flat_box(
                    f"LaptopKey_{row_index:02d}_{key_index:02d}",
                    (start_x + key_index * (key_width + 0.007), y, base_top + 0.012),
                    (key_width, 0.028, 0.010),
                    silver,
                )
            )

    parts.extend(
        [
            _flat_box("LaptopSpaceBar", (0.0, 0.092, base_top + 0.012), (0.20, 0.025, 0.010), silver),
            _cylinder(
                "LaptopLeftHinge",
                (-0.23, -0.184, base_top + 0.006),
                0.022,
                0.115,
                dark,
                rotation=(0.0, math.radians(90.0), 0.0),
                vertices=16,
            ),
            _cylinder(
                "LaptopRightHinge",
                (0.23, -0.184, base_top + 0.006),
                0.022,
                0.115,
                dark,
                rotation=(0.0, math.radians(90.0), 0.0),
                vertices=16,
            ),
        ]
    )

    laptop_base = _join(parts, "LaptopBase")
    _set_origin(laptop_base, (0.0, -0.184, base_top + 0.006))
    return laptop_base


def _make_laptop_lid(
    silver: bpy.types.Material,
    dark: bpy.types.Material,
) -> bpy.types.Object:
    hinge = (0.0, -0.184, 0.818)
    center_z = hinge[2] + 0.195
    parts = [
        _rounded_box("LaptopLidShell", (0.0, hinge[1], center_z), (0.62, 0.038, 0.39), silver, 0.024, bevel_segments=4),
        _rounded_box("LaptopScreen", (0.0, hinge[1] + 0.023, center_z + 0.006), (0.535, 0.012, 0.300), dark, 0.017, bevel_segments=4),
        _rounded_box("LaptopScreenStatus", (0.0, hinge[1] + 0.031, center_z + 0.015), (0.175, 0.008, 0.026), silver, 0.012),
        _rounded_box("LaptopScreenLineLeft", (-0.085, hinge[1] + 0.031, center_z - 0.040), (0.120, 0.008, 0.014), silver, 0.007),
        _rounded_box("LaptopScreenLineRight", (0.070, hinge[1] + 0.031, center_z - 0.040), (0.155, 0.008, 0.014), silver, 0.007),
        _cylinder(
            "LaptopCameraDot",
            (0.0, hinge[1] + 0.030, center_z + 0.168),
            0.007,
            0.006,
            dark,
            rotation=(math.radians(90.0), 0.0, 0.0),
            vertices=12,
        ),
    ]
    parts.extend(_apple_logo((0.0, hinge[1] - 0.024, center_z), dark))
    laptop_lid = _join(parts, "LaptopLid")
    _set_origin(laptop_lid, hinge)
    laptop_lid.rotation_mode = "XYZ"
    laptop_lid.rotation_euler.x = math.radians(13.0)
    return laptop_lid


def _make_chair(
    cream: bpy.types.Material,
    silver: bpy.types.Material,
) -> bpy.types.Object:
    parts = [
        _rounded_box("ChairSeat", (0.0, 0.43, 0.43), (0.50, 0.42, 0.10), cream, 0.045, bevel_segments=4),
        _rounded_box("ChairBack", (0.0, 0.615, 0.70), (0.52, 0.10, 0.46), cream, 0.055, bevel_segments=4),
        _rounded_box("ChairBackInset", (0.0, 0.555, 0.72), (0.31, 0.022, 0.19), silver, 0.011, bevel_segments=3),
    ]
    for side_name, x in [("Left", -0.18), ("Right", 0.18)]:
        for depth_name, y in [("Front", 0.31), ("Back", 0.54)]:
            parts.append(
                _rounded_box(
                    f"Chair{side_name}{depth_name}Leg",
                    (x, y, 0.215),
                    (0.085, 0.085, 0.39),
                    cream,
                    0.030,
                    bevel_segments=3,
                )
            )
    chair = _join(parts, "Chair")
    _set_origin(chair, (0.0, 0.43, 0.0))
    return chair


def _look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def _setup_preview_scene() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = bpy.data.worlds.new("SIDEYPreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.022, 0.026, 0.035, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.38
    scene.world = world

    ground_material = _material("PreviewGround", (0.026, 0.030, 0.040, 1.0), roughness=0.95)
    bpy.ops.mesh.primitive_plane_add(size=8.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground.data.materials.append(ground_material)

    light_specs = [
        ("KeyLight", (-2.4, -3.0, 3.4), 850.0, 3.0, (1.0, 0.80, 0.66)),
        ("FillLight", (2.8, -1.5, 2.0), 620.0, 2.5, (0.65, 0.82, 1.0)),
        ("RimLight", (0.0, 2.7, 3.0), 900.0, 2.0, (0.58, 1.0, 0.86)),
    ]
    for name, location, energy, size, color in light_specs:
        data = bpy.data.lights.new(name, type="AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = location
        _look_at(light, Vector((0.0, 0.0, 0.65)))

    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera_data.lens = 58
    scene.camera = camera


def _render(
    output: Path,
    location: tuple[float, float, float],
    target: tuple[float, float, float],
    lens: float,
) -> None:
    scene = bpy.context.scene
    camera = scene.camera
    camera.location = location
    camera.data.lens = lens
    _look_at(camera, Vector(target))
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def _triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _bounds(obj: bpy.types.Object) -> dict[str, list[float]]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = Vector((min(p.x for p in corners), min(p.y for p in corners), min(p.z for p in corners)))
    maximum = Vector((max(p.x for p in corners), max(p.y for p in corners), max(p.z for p in corners)))
    return {
        "minimum": [round(value, 4) for value in minimum],
        "maximum": [round(value, 4) for value in maximum],
        "dimensions": [round(value, 4) for value in maximum - minimum],
    }


def main() -> None:
    args = _arguments()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    cream = _material("StationCream", (0.57, 0.38, 0.22, 1.0), roughness=0.84)
    silver = _material("LaptopSilver", (0.42, 0.46, 0.50, 1.0), roughness=0.36, metallic=0.72)
    dark = _material("StationDark", (0.022, 0.038, 0.050, 1.0), roughness=0.64, emission_strength=0.06)

    station_root = bpy.data.objects.new("StationProps", None)
    bpy.context.scene.collection.objects.link(station_root)
    desk = _make_desk(cream, silver)
    laptop_base = _make_laptop_base(silver, dark)
    laptop_lid = _make_laptop_lid(silver, dark)
    mesh_objects = [desk, laptop_base, laptop_lid]
    if args.include_chair:
        mesh_objects.append(_make_chair(cream, silver))
    for obj in mesh_objects:
        obj.parent = station_root

    bpy.ops.object.select_all(action="DESELECT")
    station_root.select_set(True)
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = station_root
    glb_path = output_dir / f"{args.asset_name}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_extras=True,
        export_apply=False,
    )

    _setup_preview_scene()
    _render(output_dir / "desk_laptop_hero.png", (2.05, -2.55, 1.62), (0.0, 0.0, 0.59), 58.0)
    _render(output_dir / "desk_laptop_front.png", (0.0, -2.72, 1.30), (0.0, 0.0, 0.58), 62.0)
    _render(output_dir / "laptop_detail.png", (1.05, 1.55, 1.30), (0.0, -0.01, 0.92), 65.0)

    laptop_base.hide_render = True
    laptop_lid.hide_render = True
    _render(output_dir / "desk_only.png", (1.85, -2.35, 1.45), (0.0, 0.0, 0.52), 60.0)
    laptop_base.hide_render = False
    laptop_lid.hide_render = False

    blend_path = output_dir / f"{args.asset_name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    report = {
        "status": "review_candidate",
        "source_script": str(Path(__file__).resolve()),
        "outputs": {
            "blend": str(blend_path),
            "glb": str(glb_path),
        },
        "nodes": ["StationProps", *[obj.name for obj in mesh_objects]],
        "materials": ["StationCream", "LaptopSilver", "StationDark"],
        "objects": {
            obj.name: {
                "triangles": _triangle_count(obj),
                "bounds": _bounds(obj),
            }
            for obj in mesh_objects
        },
        "total_triangles": sum(_triangle_count(obj) for obj in mesh_objects),
        "glb_bytes": glb_path.stat().st_size,
    }
    (output_dir / "review-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
