class_name CharacterRigProfile
extends Resource

const REQUIRED_ROLES: Array[StringName] = [
	&"hips",
	&"spine_lower",
	&"spine_middle",
	&"chest",
	&"left_shoulder",
	&"left_upper_arm",
	&"left_forearm",
	&"left_hand",
	&"right_shoulder",
	&"right_upper_arm",
	&"right_forearm",
	&"right_hand",
	&"neck",
	&"head",
]

var model_path := ""
var bone_names: Dictionary = {}
var bubble_anchor_offset := Vector3.ZERO


static func minty_pup() -> CharacterRigProfile:
	var profile := CharacterRigProfile.new()
	profile.model_path = "res://assets/characters/dog/dog_mint_v1_rigged.glb"
	profile.bone_names = {
		&"hips": &"Hips",
		&"spine_lower": &"Spine02",
		&"spine_middle": &"Spine01",
		&"chest": &"Spine",
		&"left_shoulder": &"LeftShoulder",
		&"left_upper_arm": &"LeftArm",
		&"left_forearm": &"LeftForeArm",
		&"left_hand": &"LeftHand",
		&"right_shoulder": &"RightShoulder",
		&"right_upper_arm": &"RightArm",
		&"right_forearm": &"RightForeArm",
		&"right_hand": &"RightHand",
		&"neck": &"neck",
		&"head": &"Head",
	}
	profile.bubble_anchor_offset = Vector3(0.0, 0.60, 0.0)
	return profile


func bone_index(skeleton: Skeleton3D, role: StringName) -> int:
	var mapped_bone_name := bone_name(role)
	if mapped_bone_name.is_empty():
		return -1
	return skeleton.find_bone(mapped_bone_name)


func bone_name(role: StringName) -> StringName:
	return bone_names.get(role, &"") as StringName


func validate(skeleton: Skeleton3D) -> PackedStringArray:
	var errors := PackedStringArray()
	for role in REQUIRED_ROLES:
		var bone_name: StringName = bone_names.get(role, &"")
		if bone_name.is_empty():
			errors.append("missing role mapping: %s" % role)
		elif skeleton.find_bone(bone_name) < 0:
			errors.append("missing bone for %s: %s" % [role, bone_name])
	return errors
