"""Build a constrained review rig and motion previews for the fused desk asset.

This is deliberately a review rig, not a production character rig. The source
is a generated mesh made of hundreds of disconnected surface fragments, so the
script separates character/prop faces using texture color and coordinates,
then limits deformation to the head, torso, and hands.

Run with:
  blender --background --python scripts/tools/blender_build_station_review.py -- \
    assets/characters/dog/puppy_desk_station_v1_static.glb \
    artifacts/motion-review/puppy_desk_station_v1 --stills-only
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector


def _arguments() -> argparse.Namespace:
    try:
        separator = sys.argv.index("--")
    except ValueError as error:
        raise SystemExit("Expected arguments after --") from error
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--stills-only", action="store_true")
    return parser.parse_args(sys.argv[separator + 1 :])


def _base_color_image() -> bpy.types.Image:
    for image in bpy.data.images:
        lowered = image.name.lower()
        if "base" in lowered and "color" in lowered:
            return image
    raise SystemExit("Could not find the base-color texture")


def _face_colors(obj: bpy.types.Object, image: bpy.types.Image) -> list[Vector]:
    mesh = obj.data
    uv_layer = mesh.uv_layers.active
    if uv_layer is None:
        raise SystemExit("Source mesh has no active UV layer")
    width, height = image.size
    pixels = image.pixels[:]
    result: list[Vector] = []
    for polygon in mesh.polygons:
        samples = []
        for loop_index in polygon.loop_indices:
            uv = uv_layer.data[loop_index].uv
            x = min(width - 1, max(0, round((uv.x % 1.0) * (width - 1))))
            y = min(height - 1, max(0, round((uv.y % 1.0) * (height - 1))))
            offset = (y * width + x) * 4
            samples.append(Vector((pixels[offset], pixels[offset + 1], pixels[offset + 2])))
        result.append(_mean(samples))
    return result


def _mean(values: list[Vector]) -> Vector:
    return sum(values, Vector()) / len(values)


def _is_blue(color: Vector) -> bool:
    return color.z > 0.24 and color.z > color.x + 0.10 and color.z > color.y + 0.07


def _is_cream(color: Vector) -> bool:
    return color.x > 0.65 and color.y > 0.55 and color.z > 0.42 and color.x - color.z < 0.30


def _is_dog_white(color: Vector) -> bool:
    return color.x > 0.80 and color.y > 0.74 and color.z > 0.62 and color.x - color.z < 0.20


def _is_dark(color: Vector) -> bool:
    return max(color) < 0.43


def _is_gray(color: Vector) -> bool:
    return 0.12 < sum(color) / 3.0 < 0.82 and max(color) - min(color) < 0.20


def _face_categories(obj: bpy.types.Object, colors: list[Vector]) -> tuple[list[bool], list[bool]]:
    character_faces: list[bool] = []
    laptop_lid_faces: list[bool] = []
    for polygon in obj.data.polygons:
        positions = [obj.data.vertices[index].co for index in polygon.vertices]
        centroid = _mean(positions)
        color = colors[polygon.index]
        inside_character_width = abs(centroid.x) < 0.53
        core_head_region = centroid.z > 0.24 and centroid.y > 0.00 and abs(centroid.x) < 0.60
        head_region = centroid.z > 0.02 and centroid.y > -0.24 and inside_character_width
        body_region = centroid.z > -0.64 and centroid.y > 0.00 and abs(centroid.x) < 0.44
        hand_region = (
            -0.30 < centroid.z < 0.16
            and -0.17 < centroid.y < 0.24
            and 0.06 < abs(centroid.x) < 0.40
        )
        is_character = (
            core_head_region
            or (head_region and (_is_cream(color) or _is_dark(color) or _is_blue(color)))
            or (body_region and (_is_blue(color) or _is_dark(color)))
            or (hand_region and (_is_blue(color) or _is_dog_white(color)))
        )

        laptop_region = centroid.y < 0.04 and -0.20 < centroid.z < 0.57 and abs(centroid.x) < 0.46
        is_laptop_lid = not is_character and laptop_region and centroid.z > -0.055
        character_faces.append(is_character)
        laptop_lid_faces.append(is_laptop_lid)
    return character_faces, laptop_lid_faces


def _copy_with_faces(
    source: bpy.types.Object,
    name: str,
    keep_faces: list[bool],
) -> bpy.types.Object:
    result = source.copy()
    result.data = source.data.copy()
    result.name = name
    result.data.name = f"{name}Mesh"
    bpy.context.scene.collection.objects.link(result)
    mesh = bmesh.new()
    mesh.from_mesh(result.data)
    mesh.faces.ensure_lookup_table()
    bmesh.ops.delete(
        mesh,
        geom=[face for face in mesh.faces if not keep_faces[face.index]],
        context="FACES",
    )
    mesh.to_mesh(result.data)
    mesh.free()
    result.data.update()
    return result


def _bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    minimum = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
    maximum = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
    return minimum, maximum


def _set_origin(obj: bpy.types.Object, origin: Vector) -> None:
    obj.data.transform(Matrix.Translation(-origin))
    obj.location += origin


def _create_armature() -> bpy.types.Object:
    armature_data = bpy.data.armatures.new("PuppyDeskReviewRig")
    armature = bpy.data.objects.new("PuppyDeskReviewRig", armature_data)
    bpy.context.scene.collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    specifications = {
        "root": ((0.0, 0.20, -0.62), (0.0, 0.20, -0.38), None),
        "torso": ((0.0, 0.24, -0.40), (0.0, 0.24, 0.20), "root"),
        "head": ((0.0, 0.24, 0.16), (0.0, 0.24, 0.66), "torso"),
        "hand.L": ((-0.20, -0.02, -0.16), (-0.20, -0.02, 0.03), "torso"),
        "hand.R": ((0.20, -0.02, -0.16), (0.20, -0.02, 0.03), "torso"),
    }
    bones: dict[str, bpy.types.EditBone] = {}
    for name, (head, tail, parent_name) in specifications.items():
        bone = armature_data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent_name:
            bone.parent = bones[parent_name]
        bones[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.show_in_front = True
    return armature


def _smoothstep(lower: float, upper: float, value: float) -> float:
    if lower == upper:
        return 0.0
    amount = min(1.0, max(0.0, (value - lower) / (upper - lower)))
    return amount * amount * (3.0 - 2.0 * amount)


def _bind_character(character: bpy.types.Object, armature: bpy.types.Object) -> dict[str, int]:
    groups = {name: character.vertex_groups.new(name=name) for name in ["root", "torso", "head", "hand.L", "hand.R"]}
    weighted_counts = {name: 0 for name in groups}
    for vertex in character.data.vertices:
        position = vertex.co
        head_weight = _smoothstep(0.10, 0.32, position.z)
        hand_weight = 0.0
        hand_name = ""
        if -0.34 < position.z < 0.17 and position.y < 0.17 and abs(position.x) > 0.07:
            side_amount = _smoothstep(0.07, 0.23, abs(position.x))
            front_amount = 1.0 - _smoothstep(0.06, 0.22, position.y)
            hand_weight = min(0.90, side_amount * front_amount)
            hand_name = "hand.L" if position.x < 0.0 else "hand.R"
        root_weight = (1.0 - _smoothstep(-0.48, -0.24, position.z)) * (1.0 - head_weight)
        torso_weight = max(0.0, 1.0 - head_weight - hand_weight - root_weight)
        weights = {
            "root": root_weight,
            "torso": torso_weight,
            "head": head_weight,
            "hand.L": hand_weight if hand_name == "hand.L" else 0.0,
            "hand.R": hand_weight if hand_name == "hand.R" else 0.0,
        }
        total = sum(weights.values())
        if total <= 0.0:
            weights["torso"] = 1.0
            total = 1.0
        for name, weight in weights.items():
            if weight <= 0.0001:
                continue
            groups[name].add([vertex.index], weight / total, "REPLACE")
            weighted_counts[name] += 1

    modifier = character.modifiers.new(name="PuppyDeskReviewArmature", type="ARMATURE")
    modifier.object = armature
    character.parent = armature
    return weighted_counts


def _reset_pose(armature: bpy.types.Object) -> None:
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "XYZ"
        pose_bone.location = Vector((0.0, 0.0, 0.0))
        pose_bone.rotation_euler = Vector((0.0, 0.0, 0.0))
        pose_bone.scale = Vector((1.0, 1.0, 1.0))


def _key_pose(armature: bpy.types.Object, frame: int, values: dict[str, dict[str, tuple[float, float, float]]]) -> None:
    _reset_pose(armature)
    for bone_name, properties in values.items():
        bone = armature.pose.bones[bone_name]
        if "location" in properties:
            bone.location = Vector(properties["location"])
        if "rotation" in properties:
            bone.rotation_euler = Vector(properties["rotation"])
    for bone in armature.pose.bones:
        bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=bone.name)


def _create_armature_actions(armature: bpy.types.Object) -> dict[str, bpy.types.Action]:
    armature.animation_data_create()
    actions: dict[str, bpy.types.Action] = {}

    online = bpy.data.actions.new("online_idle")
    armature.animation_data.action = online
    online_poses = {
        1: {"head": {"rotation": (0.02, 0.0, -0.015)}},
        16: {"head": {"rotation": (-0.015, 0.018, 0.010)}},
        31: {"head": {"rotation": (0.025, 0.008, -0.010)}},
        46: {"head": {"rotation": (-0.010, -0.018, 0.012)}},
        61: {"head": {"rotation": (0.018, -0.008, -0.008)}},
        76: {"head": {"rotation": (-0.012, 0.012, 0.010)}},
        91: {"head": {"rotation": (0.02, 0.0, -0.015)}},
    }
    for frame, pose in online_poses.items():
        _key_pose(armature, frame, pose)
    actions["online_idle"] = online

    typing = bpy.data.actions.new("typing")
    armature.animation_data.action = typing
    for frame in range(1, 62, 5):
        left_up = ((frame - 1) // 5) % 2 == 0
        values = {
            "head": {"rotation": (0.035 if left_up else 0.012, 0.0, 0.0)},
            "hand.L": {"location": (0.0, 0.009 if left_up else -0.002, 0.0)},
            "hand.R": {"location": (0.0, -0.002 if left_up else 0.009, 0.0)},
        }
        _key_pose(armature, frame, values)
    actions["typing"] = typing

    away = bpy.data.actions.new("away_sleep")
    armature.animation_data.action = away
    away_poses = {
        1: {"head": {"rotation": (0.02, 0.0, 0.0)}},
        18: {"torso": {"rotation": (0.06, 0.0, 0.0)}, "head": {"rotation": (0.12, 0.0, 0.0)}},
        38: {
            "torso": {"location": (0.0, -0.018, 0.012), "rotation": (0.12, 0.0, 0.0)},
            "head": {"location": (0.0, -0.060, 0.038), "rotation": (0.26, 0.0, 0.03)},
            "hand.L": {"location": (0.0, -0.006, 0.008)},
            "hand.R": {"location": (0.0, -0.006, -0.008)},
        },
        64: {
            "torso": {"location": (0.0, -0.016, 0.010), "rotation": (0.11, 0.0, 0.0)},
            "head": {"location": (0.0, -0.056, 0.036), "rotation": (0.24, 0.0, 0.03)},
        },
        91: {
            "torso": {"location": (0.0, -0.018, 0.012), "rotation": (0.12, 0.0, 0.0)},
            "head": {"location": (0.0, -0.060, 0.038), "rotation": (0.26, 0.0, 0.03)},
        },
    }
    for frame, pose in away_poses.items():
        _key_pose(armature, frame, pose)
    actions["away_sleep"] = away

    armature.animation_data.action = online
    return actions


def _create_lid_action(lid: bpy.types.Object) -> bpy.types.Action:
    lid.rotation_mode = "XYZ"
    lid.animation_data_create()
    action = bpy.data.actions.new("away_laptop_close")
    lid.animation_data.action = action
    lid.rotation_euler = Vector((0.0, 0.0, 0.0))
    lid.keyframe_insert(data_path="rotation_euler", frame=1)
    lid.rotation_euler.x = math.radians(47.0)
    lid.keyframe_insert(data_path="rotation_euler", frame=38)
    lid.keyframe_insert(data_path="rotation_euler", frame=91)
    return action


def _simple_material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = 0.82
    return material


def _rounded_box(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    material: bpy.types.Material,
    bevel_width: float,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bevel = obj.modifiers.new(name="Soft edges", type="BEVEL")
    bevel.width = bevel_width
    bevel.segments = 3
    bevel.limit_method = "ANGLE"
    bpy.ops.object.shade_smooth_by_angle()
    obj.data.materials.append(material)
    return obj


def _create_offline_station() -> list[bpy.types.Object]:
    wood = _simple_material("OfflineStationWood", (0.55, 0.37, 0.22, 1.0))
    laptop = _simple_material("OfflineStationLaptop", (0.24, 0.27, 0.32, 1.0))
    objects = [
        _rounded_box("OfflineDeskTop", (0.0, -0.06, -0.24), (1.12, 0.86, 0.16), wood, 0.07),
        _rounded_box("OfflineDeskLeft", (-0.46, -0.03, -0.63), (0.20, 0.66, 0.76), wood, 0.07),
        _rounded_box("OfflineDeskRight", (0.46, -0.03, -0.63), (0.20, 0.66, 0.76), wood, 0.07),
        _rounded_box("OfflineChairSeat", (0.0, 0.48, -0.54), (0.62, 0.48, 0.13), wood, 0.05),
        _rounded_box("OfflineChairBack", (0.0, 0.66, -0.14), (0.66, 0.14, 0.48), wood, 0.06),
        _rounded_box("OfflineChairLeftLeg", (-0.23, 0.57, -0.79), (0.11, 0.11, 0.52), wood, 0.04),
        _rounded_box("OfflineChairRightLeg", (0.23, 0.57, -0.79), (0.11, 0.11, 0.52), wood, 0.04),
        _rounded_box("OfflineLaptopBase", (0.0, -0.26, -0.11), (0.67, 0.47, 0.055), laptop, 0.025),
        _rounded_box("OfflineLaptopLid", (0.0, -0.25, -0.065), (0.65, 0.45, 0.045), laptop, 0.025),
    ]
    for obj in objects:
        obj.hide_render = True
    return objects


def _create_sleep_label(camera: bpy.types.Object) -> bpy.types.Object:
    font = bpy.data.curves.new("SleepLabelText", type="FONT")
    font.body = "Zzz"
    font.align_x = "CENTER"
    font.align_y = "CENTER"
    font.size = 0.16
    font.extrude = 0.006
    font.bevel_depth = 0.002
    label = bpy.data.objects.new("SleepLabel", font)
    bpy.context.scene.collection.objects.link(label)
    label.location = Vector((0.43, 0.19, 0.95))
    label.rotation_euler = (camera.location - label.location).to_track_quat("Z", "Y").to_euler()
    material = _simple_material("SleepLabelMaterial", (0.30, 0.68, 1.0, 1.0))
    font.materials.append(material)
    label.hide_render = True
    for frame, height, scale in [(1, 0.95, 0.80), (31, 1.07, 1.0), (61, 0.99, 0.88), (91, 0.95, 0.80)]:
        label.location.z = height
        label.scale = Vector((scale, scale, scale))
        label.keyframe_insert(data_path="location", frame=frame)
        label.keyframe_insert(data_path="scale", frame=frame)
    return label


def _look_at(obj: bpy.types.Object, target: Vector, axis: str = "-Z") -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat(axis, "Y").to_euler()


def _setup_review_scene(objects: list[bpy.types.Object]) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.fps = 30
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.ffmpeg.format = "QUICKTIME"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"

    minimums, maximums = zip(*[_bounds(obj) for obj in objects], strict=True)
    minimum = Vector((min(value.x for value in minimums), min(value.y for value in minimums), min(value.z for value in minimums)))
    maximum = Vector((max(value.x for value in maximums), max(value.y for value in maximums), max(value.z for value in maximums)))
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    radius = max(size)

    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = center + Vector((radius * 1.35, -radius * 1.7, radius * 0.65))
    camera_data.lens = 58
    _look_at(camera, center + Vector((0.0, 0.0, size.z * 0.03)))
    scene.camera = camera

    world = bpy.data.worlds.new("ReviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.035, 0.045, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.45
    scene.world = world

    lights = [
        ((-1.5, -2.0, 2.7), 950.0, 4.0),
        ((2.0, -0.5, 1.5), 650.0, 3.0),
        ((0.0, 2.0, 2.2), 850.0, 3.0),
    ]
    for index, (offset, energy, size_value) in enumerate(lights):
        light_data = bpy.data.lights.new(f"ReviewLight{index}", type="AREA")
        light_data.energy = energy
        light_data.shape = "DISK"
        light_data.size = size_value
        light_data.use_shadow = False
        light = bpy.data.objects.new(f"ReviewLight{index}", light_data)
        scene.collection.objects.link(light)
        light.location = center + Vector(offset) * radius
        _look_at(light, center)


def _render_still(
    output: Path,
    armature: bpy.types.Object,
    character: bpy.types.Object,
    props: bpy.types.Object,
    lid: bpy.types.Object,
    offline_station: list[bpy.types.Object],
    sleep_label: bpy.types.Object,
    armature_action: bpy.types.Action,
    lid_action: bpy.types.Action | None,
    frame: int,
    offline: bool = False,
) -> None:
    scene = bpy.context.scene
    armature.animation_data.action = armature_action
    lid.animation_data.action = lid_action
    if lid_action is None:
        lid.rotation_euler = Vector((0.0, 0.0, 0.0))
    character.hide_render = offline
    armature.hide_render = offline
    props.hide_render = offline
    lid.hide_render = offline
    for obj in offline_station:
        obj.hide_render = not offline
    sleep_label.hide_render = offline or armature_action.name != "away_sleep"
    scene.frame_set(frame)
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)


def _render_movie(
    output: Path,
    armature: bpy.types.Object,
    character: bpy.types.Object,
    props: bpy.types.Object,
    lid: bpy.types.Object,
    offline_station: list[bpy.types.Object],
    sleep_label: bpy.types.Object,
    armature_action: bpy.types.Action,
    lid_action: bpy.types.Action | None,
    frame_end: int,
    offline: bool = False,
) -> None:
    scene = bpy.context.scene
    armature.animation_data.action = armature_action
    lid.animation_data.action = lid_action
    if lid_action is None:
        lid.rotation_euler = Vector((0.0, 0.0, 0.0))
    character.hide_render = offline
    armature.hide_render = offline
    props.hide_render = offline
    lid.hide_render = offline
    for obj in offline_station:
        obj.hide_render = not offline
    sleep_label.hide_render = offline or armature_action.name != "away_sleep"
    scene.frame_start = 1
    scene.frame_end = frame_end
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.ffmpeg.format = "QUICKTIME"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
    scene.render.ffmpeg.ffmpeg_preset = "GOOD"
    scene.render.filepath = str(output.with_suffix(""))
    bpy.ops.render.render(animation=True)


def main() -> None:
    args = _arguments()
    source = args.source.expanduser().resolve()
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    source_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(source_objects) != 1:
        raise SystemExit(f"Expected one source mesh, found {len(source_objects)}")
    source_object = source_objects[0]
    colors = _face_colors(source_object, _base_color_image())
    character_faces, laptop_lid_faces = _face_categories(source_object, colors)
    prop_faces = [not character and not lid for character, lid in zip(character_faces, laptop_lid_faces, strict=True)]

    character = _copy_with_faces(source_object, "CharacterSkinnedMesh", character_faces)
    props = _copy_with_faces(source_object, "StationProps", prop_faces)
    lid = _copy_with_faces(source_object, "LaptopLid", laptop_lid_faces)
    bpy.data.objects.remove(source_object, do_unlink=True)

    lid_minimum, lid_maximum = _bounds(lid)
    hinge = Vector((0.0, lid_maximum.y, lid_minimum.z))
    _set_origin(lid, hinge)

    armature = _create_armature()
    weighted_counts = _bind_character(character, armature)
    actions = _create_armature_actions(armature)
    lid_action = _create_lid_action(lid)
    offline_station = _create_offline_station()
    _setup_review_scene([character, props, lid, *offline_station])
    sleep_label = _create_sleep_label(bpy.context.scene.camera)

    stills = {
        "online_idle": (actions["online_idle"], None, 46, False),
        "typing": (actions["typing"], None, 31, False),
        "away_sleep": (actions["away_sleep"], lid_action, 64, False),
        "offline": (actions["away_sleep"], lid_action, 91, True),
    }
    for name, (action, active_lid_action, frame, offline) in stills.items():
        _render_still(
            output_dir / f"{name}.png",
            armature,
            character,
            props,
            lid,
            offline_station,
            sleep_label,
            action,
            active_lid_action,
            frame,
            offline,
        )

    animated_glb = output_dir / "puppy_desk_station_v1_review_rigged.glb"
    character.hide_render = False
    armature.hide_render = False
    props.hide_render = False
    lid.hide_render = False
    for obj in offline_station:
        obj.hide_render = True
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [character, props, lid, armature]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(animated_glb),
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
    blend_path = output_dir / "puppy_desk_station_v1_review_rigged.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    if not args.stills_only:
        _render_movie(output_dir / "online_idle.mov", armature, character, props, lid, offline_station, sleep_label, actions["online_idle"], None, 90)
        _render_movie(output_dir / "typing.mov", armature, character, props, lid, offline_station, sleep_label, actions["typing"], None, 60)
        _render_movie(output_dir / "away_sleep.mov", armature, character, props, lid, offline_station, sleep_label, actions["away_sleep"], lid_action, 90)
        _render_movie(output_dir / "offline.mov", armature, character, props, lid, offline_station, sleep_label, actions["away_sleep"], lid_action, 60, True)

    report = {
        "source": str(source),
        "source_faces": len(character_faces),
        "character_faces": sum(character_faces),
        "prop_faces": sum(prop_faces),
        "laptop_lid_faces": sum(laptop_lid_faces),
        "character_vertices": len(character.data.vertices),
        "prop_vertices": len(props.data.vertices),
        "laptop_lid_vertices": len(lid.data.vertices),
        "laptop_lid_bounds": {
            "minimum": [round(value, 5) for value in lid_minimum],
            "maximum": [round(value, 5) for value in lid_maximum],
            "hinge": [round(value, 5) for value in hinge],
        },
        "weighted_vertices": weighted_counts,
        "actions": list(actions),
        "animated_glb": str(animated_glb),
        "blend": str(blend_path),
        "movies_rendered": not args.stills_only,
    }
    print("SIDEY_STATION_REVIEW_REPORT=" + json.dumps(report, ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
