"""Create and validate the first SIDEY Minty Pup deformation rig.

The input must be the minimally welded Blender authoring source.  The script
keeps the original topology and material, adds a compact humanoid armature,
binds with Blender's automatic bone heat weights, fixes detached facial and
tail components to their semantic bones, and exports a rigged GLB.

Run with:
  blender source.blend --background --python \
    scripts/tools/blender_rig_minty_pup.py -- output-directory
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
    parser.add_argument("output_dir", type=Path)
    return parser.parse_args(sys.argv[separator + 1 :])


def _create_armature() -> bpy.types.Object:
    armature_data = bpy.data.armatures.new("MintyPupRig")
    armature = bpy.data.objects.new("MintyPupRig", armature_data)
    bpy.context.scene.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    armature.show_in_front = True
    armature_data.display_type = "OCTAHEDRAL"
    bpy.ops.object.mode_set(mode="EDIT")

    specifications = {
        "root": ((0.0, 0.0, -0.50), (0.0, 0.0, -0.40), None, False, False),
        "pelvis": ((0.0, 0.0, -0.31), (0.0, 0.0, -0.19), "root", False, True),
        "spine": ((0.0, 0.0, -0.19), (0.0, 0.0, 0.01), "pelvis", True, True),
        "chest": ((0.0, 0.0, 0.01), (0.0, 0.0, 0.12), "spine", True, True),
        "neck": ((0.0, 0.0, 0.12), (0.0, 0.0, 0.18), "chest", True, True),
        "head": ((0.0, 0.0, 0.18), (0.0, 0.0, 0.40), "neck", True, True),
        "upper_arm.L": ((0.12, 0.0, 0.08), (0.21, -0.004, -0.01), "chest", False, True),
        "forearm.L": ((0.21, -0.004, -0.01), (0.29, -0.012, -0.12), "upper_arm.L", True, True),
        "hand.L": ((0.29, -0.012, -0.12), (0.33, -0.020, -0.17), "forearm.L", True, True),
        "upper_arm.R": ((-0.12, 0.0, 0.08), (-0.21, -0.004, -0.01), "chest", False, True),
        "forearm.R": ((-0.21, -0.004, -0.01), (-0.29, -0.012, -0.12), "upper_arm.R", True, True),
        "hand.R": ((-0.29, -0.012, -0.12), (-0.33, -0.020, -0.17), "forearm.R", True, True),
        "thigh.L": ((0.075, 0.0, -0.24), (0.075, 0.0, -0.36), "pelvis", False, True),
        "shin.L": ((0.075, 0.0, -0.36), (0.075, -0.005, -0.47), "thigh.L", True, True),
        "foot.L": ((0.075, -0.005, -0.47), (0.075, -0.11, -0.48), "shin.L", True, True),
        "thigh.R": ((-0.075, 0.0, -0.24), (-0.075, 0.0, -0.36), "pelvis", False, True),
        "shin.R": ((-0.075, 0.0, -0.36), (-0.075, -0.005, -0.47), "thigh.R", True, True),
        "foot.R": ((-0.075, -0.005, -0.47), (-0.075, -0.11, -0.48), "shin.R", True, True),
        "tail": ((0.0, 0.11, -0.20), (0.0, 0.20, -0.18), "pelvis", False, True),
    }
    bones: dict[str, bpy.types.EditBone] = {}
    for name, (head, tail, parent_name, connected, deform) in specifications.items():
        bone = armature_data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = deform
        if parent_name:
            bone.parent = bones[parent_name]
            bone.use_connect = connected
        bones[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    return armature


def _prepare_manual_binding(mesh: bpy.types.Object, armature: bpy.types.Object) -> None:
    for bone in armature.data.bones:
        if bone.use_deform:
            mesh.vertex_groups.new(name=bone.name)
    modifier = mesh.modifiers.new(name="MintyPupArmature", type="ARMATURE")
    modifier.object = armature
    mesh.parent = armature


def _component_indices(mesh: bpy.types.Mesh) -> list[list[int]]:
    adjacency = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)
    visited: set[int] = set()
    components: list[list[int]] = []
    for vertex in mesh.vertices:
        if vertex.index in visited:
            continue
        stack = [vertex.index]
        component: list[int] = []
        while stack:
            current = stack.pop()
            if current in visited:
                continue
            visited.add(current)
            component.append(current)
            stack.extend(adjacency[current] - visited)
        components.append(component)
    return components


def _replace_component_weight(
    obj: bpy.types.Object,
    indices: list[int],
    bone_name: str,
    deform_names: set[str],
) -> None:
    for group in obj.vertex_groups:
        if group.name in deform_names:
            group.remove(indices)
    obj.vertex_groups[bone_name].add(indices, 1.0, "REPLACE")


def _distance_and_path_position(point: Vector, path: list[Vector]) -> tuple[float, float]:
    best_distance = float("inf")
    best_path_position = 0.0
    distance_before = 0.0
    for start, end in zip(path, path[1:]):
        segment = end - start
        length = segment.length
        if length <= 1e-8:
            continue
        amount = min(1.0, max(0.0, (point - start).dot(segment) / (length * length)))
        closest = start + segment * amount
        distance = (point - closest).length
        if distance < best_distance:
            best_distance = distance
            best_path_position = distance_before + length * amount
        distance_before += length
    return best_distance, best_path_position


def _weights_between_centers(
    value: float,
    centers: list[tuple[float, str]],
) -> dict[str, float]:
    if value <= centers[0][0]:
        return {centers[0][1]: 1.0}
    if value >= centers[-1][0]:
        return {centers[-1][1]: 1.0}
    for (start, start_name), (end, end_name) in zip(centers, centers[1:]):
        if start <= value <= end:
            amount = (value - start) / (end - start)
            return {start_name: 1.0 - amount, end_name: amount}
    raise RuntimeError("Could not interpolate skinning centers")


def _replace_vertex_weights(
    mesh: bpy.types.Object,
    vertex_index: int,
    weights: dict[str, float],
    deform_names: set[str],
) -> None:
    for group in mesh.vertex_groups:
        if group.name in deform_names:
            group.remove([vertex_index])
    for name, weight in weights.items():
        if weight > 1e-6:
            mesh.vertex_groups[name].add([vertex_index], weight, "REPLACE")


def _constrain_limb_weights(mesh: bpy.types.Object, armature: bpy.types.Object) -> dict[str, int]:
    deform_names = {bone.name for bone in armature.data.bones if bone.use_deform}
    components = _component_indices(mesh.data)
    main_component = max(components, key=len)
    main_indices = set(main_component)
    arm_names = {
        "upper_arm.L",
        "forearm.L",
        "hand.L",
        "upper_arm.R",
        "forearm.R",
        "hand.R",
    }
    leg_names = {
        "thigh.L",
        "shin.L",
        "foot.L",
        "thigh.R",
        "shin.R",
        "foot.R",
    }
    arm_paths = {
        ".L": [
            Vector((0.12, 0.0, 0.08)),
            Vector((0.21, -0.004, -0.01)),
            Vector((0.29, -0.012, -0.12)),
            Vector((0.33, -0.020, -0.17)),
        ],
        ".R": [
            Vector((-0.12, 0.0, 0.08)),
            Vector((-0.21, -0.004, -0.01)),
            Vector((-0.29, -0.012, -0.12)),
            Vector((-0.33, -0.020, -0.17)),
        ],
    }
    arm_centers = [
        (-0.045, "chest"),
        (0.060, "upper_arm{side}"),
        (0.195, "forearm{side}"),
        (0.298, "hand{side}"),
    ]
    leg_centers = [
        (-0.50, "foot{side}"),
        (-0.41, "shin{side}"),
        (-0.30, "thigh{side}"),
        (-0.22, "pelvis"),
    ]
    arm_indices: set[int] = set()
    leg_indices: set[int] = set()
    body_indices: set[int] = set()
    for index in main_indices:
        position = mesh.data.vertices[index].co
        side = ".L" if position.x >= 0.0 else ".R"
        arm_distance, path_position = _distance_and_path_position(position, arm_paths[side])
        is_arm = (
            abs(position.x) > 0.105
            and -0.235 < position.z < 0.155
            and arm_distance < 0.090
        )
        is_leg = (
            position.z < -0.235
            and abs(position.x) < 0.165
            and abs(abs(position.x) - 0.075) < 0.095
        )
        if is_arm:
            formatted_centers = [
                (center, name.format(side=side)) for center, name in arm_centers
            ]
            weights = _weights_between_centers(path_position, formatted_centers)
            _replace_vertex_weights(mesh, index, weights, deform_names)
            arm_indices.add(index)
        elif is_leg:
            formatted_centers = [
                (center, name.format(side=side)) for center, name in leg_centers
            ]
            weights = _weights_between_centers(position.z, formatted_centers)
            _replace_vertex_weights(mesh, index, weights, deform_names)
            leg_indices.add(index)
        else:
            is_head_shell = (
                position.z >= 0.16
                or (
                    position.z >= 0.10
                    and (abs(position.x) > 0.09 or abs(position.y) > 0.07)
                )
            )
            if is_head_shell:
                weights = {"head": 1.0}
            else:
                weights = _weights_between_centers(
                    position.z,
                    [
                        (-0.28, "pelvis"),
                        (-0.10, "spine"),
                        (0.06, "chest"),
                        (0.13, "neck"),
                        (0.19, "head"),
                    ],
                )
            _replace_vertex_weights(mesh, index, weights, deform_names)
            body_indices.add(index)
    return {
        "main_vertices": len(main_indices),
        "manual_arm_vertices": len(arm_indices),
        "manual_leg_vertices": len(leg_indices),
        "manual_body_vertices": len(body_indices),
    }


def _fix_detached_components(mesh: bpy.types.Object, armature: bpy.types.Object) -> list[dict[str, object]]:
    deform_names = {bone.name for bone in armature.data.bones if bone.use_deform}
    reports: list[dict[str, object]] = []
    components = _component_indices(mesh.data)
    tail_indices: set[int] = set()
    for component in components:
        positions = [mesh.data.vertices[index].co for index in component]
        minimum = Vector(tuple(min(position[axis] for position in positions) for axis in range(3)))
        maximum = Vector(tuple(max(position[axis] for position in positions) for axis in range(3)))
        center = (minimum + maximum) * 0.5
        if len(component) > 1000:
            semantic = "main"
            bone_name = None
        elif center.y > 0.05 and center.z < -0.10:
            semantic = "tail"
            bone_name = "tail"
            tail_indices.update(component)
        elif center.z > 0.15:
            semantic = "face"
            bone_name = "head"
        else:
            semantic = "unknown"
            bone_name = None
        if bone_name:
            _replace_component_weight(mesh, component, bone_name, deform_names)
        reports.append(
            {
                "vertices": len(component),
                "center": [round(value, 6) for value in center],
                "semantic": semantic,
                "forced_bone": bone_name,
            }
        )
    non_tail_indices = [
        vertex.index for vertex in mesh.data.vertices if vertex.index not in tail_indices
    ]
    mesh.vertex_groups["tail"].remove(non_tail_indices)
    reports.sort(key=lambda item: int(item["vertices"]), reverse=True)
    return reports


def _limit_and_normalize_weights(mesh: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.object.vertex_group_limit_total(group_select_mode="BONE_DEFORM", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="BONE_DEFORM", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def _repair_unweighted_vertices(mesh: bpy.types.Object, armature: bpy.types.Object) -> list[dict[str, object]]:
    deform_names = {bone.name for bone in armature.data.bones if bone.use_deform}
    group_names = {group.index: group.name for group in mesh.vertex_groups}
    repaired: list[dict[str, object]] = []
    for vertex in mesh.data.vertices:
        has_weight = any(
            group_names.get(assignment.group) in deform_names and assignment.weight > 1e-6
            for assignment in vertex.groups
        )
        if has_weight:
            continue
        mesh.vertex_groups["pelvis"].add([vertex.index], 1.0, "REPLACE")
        repaired.append(
            {
                "vertex": vertex.index,
                "position": [round(value, 6) for value in vertex.co],
                "assigned_bone": "pelvis",
            }
        )
    return repaired


def _weight_report(mesh: bpy.types.Object, armature: bpy.types.Object) -> dict[str, object]:
    deform_names = {bone.name for bone in armature.data.bones if bone.use_deform}
    group_names = {group.index: group.name for group in mesh.vertex_groups}
    unweighted = 0
    zero_sum = 0
    max_influences = 0
    group_counts = {name: 0 for name in sorted(deform_names)}
    for vertex in mesh.data.vertices:
        weights = [
            assignment.weight
            for assignment in vertex.groups
            if group_names.get(assignment.group) in deform_names and assignment.weight > 1e-6
        ]
        if not weights:
            unweighted += 1
        elif sum(weights) <= 1e-6:
            zero_sum += 1
        max_influences = max(max_influences, len(weights))
        for assignment in vertex.groups:
            name = group_names.get(assignment.group)
            if name in group_counts and assignment.weight > 1e-6:
                group_counts[name] += 1
    return {
        "vertices": len(mesh.data.vertices),
        "unweighted_vertices": unweighted,
        "zero_weight_sum_vertices": zero_sum,
        "max_influences": max_influences,
        "group_vertex_counts": group_counts,
    }


def main() -> None:
    args = _arguments()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    source_blend = bpy.data.filepath
    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(mesh_objects) != 1:
        raise SystemExit(f"Expected one mesh object, found {len(mesh_objects)}")
    mesh = mesh_objects[0]
    mesh.name = "MintyPupMesh"
    mesh.data.name = "MintyPupMeshData"
    for group in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(group)
    for modifier in list(mesh.modifiers):
        if modifier.type == "ARMATURE":
            mesh.modifiers.remove(modifier)

    triangles_before_validation = len(mesh.data.polygons)
    mesh_validation_changed = mesh.data.validate(verbose=True, clean_customdata=False)
    mesh.data.update()
    triangles_after_validation = len(mesh.data.polygons)

    armature = _create_armature()
    _prepare_manual_binding(mesh, armature)
    limb_weighting = _constrain_limb_weights(mesh, armature)
    components = _fix_detached_components(mesh, armature)
    _limit_and_normalize_weights(mesh)
    repaired_unweighted = _repair_unweighted_vertices(mesh, armature)
    weights = _weight_report(mesh, armature)
    if weights["unweighted_vertices"] or weights["zero_weight_sum_vertices"]:
        raise SystemExit(f"Rig contains unweighted vertices: {weights}")

    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    glb_path = output_dir / "minty_pup_v2_rigged.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_skins=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    blend_path = output_dir / "minty_pup_v2_rigged.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    report = {
        "source_blend": source_blend,
        "blend": str(blend_path),
        "glb": str(glb_path),
        "bones": [bone.name for bone in armature.data.bones],
        "deform_bones": [bone.name for bone in armature.data.bones if bone.use_deform],
        "components": components,
        "limb_weighting": limb_weighting,
        "weights": weights,
        "repaired_unweighted_vertices": repaired_unweighted,
        "mesh_validation_changed": mesh_validation_changed,
        "triangles_before_validation": triangles_before_validation,
        "triangles_after_validation": triangles_after_validation,
        "glb_bytes": glb_path.stat().st_size,
    }
    report_path = output_dir / "rig-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("SIDEY_RIG_REPORT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
