class_name SleepEffect
extends Node3D

const SLEEP_TEXT_COLOR := Color("a9eadb")

var _skeleton: Skeleton3D
var _head_bone_index := -1
var _base_head_pose := Transform3D.IDENTITY
var _z_large: Label3D
var _z_small: Label3D


func configure(skeleton: Skeleton3D, head_bone_name: StringName) -> Error:
	_skeleton = skeleton
	_head_bone_index = _skeleton.find_bone(head_bone_name)
	if _head_bone_index < 0:
		push_error("SLEEP_EFFECT_HEAD_BONE_MISSING bone=%s" % head_bone_name)
		return ERR_DOES_NOT_EXIST

	_base_head_pose = _skeleton.get_bone_global_pose(_head_bone_index)
	_build_sleep_text()
	visible = false
	return OK


func set_active(active: bool) -> void:
	visible = active


func sync(loop_phase: float) -> void:
	if not visible or not is_instance_valid(_skeleton):
		return

	var current_head_pose := _skeleton.get_bone_global_pose(_head_bone_index)
	transform = current_head_pose * _base_head_pose.affine_inverse()
	var wave := sin(loop_phase * TAU)
	_z_large.position = Vector3(32.0, 160.0 + wave * 1.8, 31.0)
	_z_small.position = Vector3(43.0, 173.0 - wave * 1.2, 29.0)
	_z_large.modulate.a = 0.78 + wave * 0.14
	_z_small.modulate.a = 0.62 - wave * 0.12


func _build_sleep_text() -> void:
	_z_large = _make_sleep_label("Z", 58, 0.21)
	_z_large.name = "SleepZLarge"
	add_child(_z_large)

	_z_small = _make_sleep_label("z", 42, 0.18)
	_z_small.name = "SleepZSmall"
	add_child(_z_small)


func _make_sleep_label(text: String, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = SLEEP_TEXT_COLOR
	label.outline_modulate = Color("263743")
	label.outline_size = 5
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	return label
