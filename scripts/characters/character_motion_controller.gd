class_name CharacterMotionController
extends Node

signal state_changed(previous_state: CharacterState.Value, next_state: CharacterState.Value)

const ONLINE_IDLE_LENGTH := 6.0
const TYPING_LENGTH := 0.60
const OFFLINE_SLEEP_LENGTH := 4.0

var body_bob := 0.0
var chest_pitch_degrees := 0.0
var chest_roll_degrees := 0.0
var head_roll_degrees := 0.0
var head_pitch_degrees := 0.0
var left_upper_arm_degrees := Vector3.ZERO
var left_forearm_degrees := Vector3.ZERO
var left_hand_degrees := Vector3.ZERO
var right_upper_arm_degrees := Vector3.ZERO
var right_forearm_degrees := Vector3.ZERO
var right_hand_degrees := Vector3.ZERO

var _state := CharacterState.Value.ONLINE_IDLE
var _visual_root: Node3D
var _skeleton: Skeleton3D
var _profile: CharacterRigProfile
var _base_visual_position := Vector3.ZERO
var _base_bone_rotations: Dictionary = {}
var _animation_player: AnimationPlayer
var _typing_prop: Node3D
var _sleep_effect: SleepEffect


func configure(
	visual_root: Node3D,
	skeleton: Skeleton3D,
	profile: CharacterRigProfile,
	typing_prop: Node3D = null,
	sleep_effect: SleepEffect = null,
) -> Error:
	_visual_root = visual_root
	_skeleton = skeleton
	_profile = profile
	_typing_prop = typing_prop
	_sleep_effect = sleep_effect

	var validation_errors := _profile.validate(_skeleton)
	if not validation_errors.is_empty():
		for validation_error in validation_errors:
			push_error("RIG_PROFILE_INVALID %s" % validation_error)
		return ERR_INVALID_DATA

	_base_visual_position = _visual_root.position
	for role in CharacterRigProfile.REQUIRED_ROLES:
		var bone_index := _profile.bone_index(_skeleton, role)
		_base_bone_rotations[role] = _skeleton.get_bone_pose_rotation(bone_index)

	_animation_player = AnimationPlayer.new()
	_animation_player.name = "MotionAnimationPlayer"
	_animation_player.root_node = NodePath("..")
	add_child(_animation_player)
	_install_animation_library()
	set_state(CharacterState.Value.ONLINE_IDLE, true)
	return OK


func set_state(next_state: CharacterState.Value, restart := false) -> void:
	if next_state not in [
		CharacterState.Value.ONLINE_IDLE,
		CharacterState.Value.TYPING,
		CharacterState.Value.OFFLINE_SLEEP,
	]:
		push_warning("STATE_NOT_IMPLEMENTED state=%s" % CharacterState.label(next_state))
		return
	if next_state == _state and not restart:
		return

	var previous_state := _state
	_state = next_state
	var animation_name := CharacterState.label(_state).to_lower()
	_animation_player.play(animation_name, 0.25)
	if is_instance_valid(_typing_prop):
		_typing_prop.visible = _state == CharacterState.Value.TYPING
	if is_instance_valid(_sleep_effect):
		_sleep_effect.set_active(_state == CharacterState.Value.OFFLINE_SLEEP)
	state_changed.emit(previous_state, _state)


func current_state() -> CharacterState.Value:
	return _state


func loop_phase() -> float:
	if _animation_player == null or not _animation_player.is_playing():
		return 0.0
	var animation_length := _animation_player.current_animation_length
	if is_zero_approx(animation_length):
		return 0.0
	return fposmod(_animation_player.current_animation_position, animation_length) / animation_length


func _process(_delta: float) -> void:
	_apply_pose()


func _exit_tree() -> void:
	if is_instance_valid(_visual_root):
		_visual_root.position = _base_visual_position
	if is_instance_valid(_skeleton):
		for role in _base_bone_rotations:
			_set_role_rotation(role, _base_bone_rotations[role])


func _install_animation_library() -> void:
	var library := AnimationLibrary.new()
	library.add_animation(&"RESET", _build_reset_animation())
	library.add_animation(&"online_idle", _build_online_idle_animation())
	library.add_animation(&"typing", _build_typing_animation())
	library.add_animation(&"offline_sleep", _build_offline_sleep_animation())
	_animation_player.add_animation_library(&"", library)


func _build_reset_animation() -> Animation:
	var animation := Animation.new()
	animation.length = 0.1
	_add_value_track(animation, &"body_bob", [[0.0, 0.0]])
	_add_value_track(animation, &"chest_pitch_degrees", [[0.0, 0.0]])
	_add_value_track(animation, &"chest_roll_degrees", [[0.0, 0.0]])
	_add_value_track(animation, &"head_roll_degrees", [[0.0, 0.0]])
	_add_neutral_limb_tracks(animation)
	return animation


func _build_online_idle_animation() -> Animation:
	var animation := Animation.new()
	animation.length = ONLINE_IDLE_LENGTH
	animation.loop_mode = Animation.LOOP_LINEAR

	_add_value_track(animation, &"body_bob", [
		[0.0, 0.0],
		[1.5, 0.010],
		[3.0, 0.0],
		[4.5, -0.004],
		[6.0, 0.0],
	])
	_add_value_track(animation, &"chest_pitch_degrees", [
		[0.0, -0.35],
		[1.5, 0.60],
		[3.0, -0.25],
		[4.5, 0.45],
		[6.0, -0.35],
	])
	_add_value_track(animation, &"chest_roll_degrees", [[0.0, 0.0], [ONLINE_IDLE_LENGTH, 0.0]])
	_add_value_track(animation, &"head_roll_degrees", [
		[0.0, 0.0],
		[4.15, 0.0],
		[4.70, 2.6],
		[5.15, 2.2],
		[5.75, 0.0],
		[6.0, 0.0],
	])
	_add_neutral_limb_tracks(animation)
	return animation


func _build_typing_animation() -> Animation:
	var animation := Animation.new()
	animation.length = TYPING_LENGTH
	animation.loop_mode = Animation.LOOP_LINEAR

	_add_value_track(animation, &"body_bob", [
		[0.0, 0.0],
		[0.15, 0.004],
		[0.30, 0.0],
		[0.45, 0.004],
		[TYPING_LENGTH, 0.0],
	])
	_add_value_track(animation, &"chest_pitch_degrees", [
		[0.0, 1.2],
		[0.15, 1.8],
		[0.30, 1.2],
		[0.45, 1.8],
		[TYPING_LENGTH, 1.2],
	])
	_add_value_track(animation, &"chest_roll_degrees", [[0.0, 0.0], [TYPING_LENGTH, 0.0]])
	_add_value_track(animation, &"head_roll_degrees", [[0.0, 0.0], [TYPING_LENGTH, 0.0]])
	_add_value_track(animation, &"head_pitch_degrees", [[0.0, 2.0], [TYPING_LENGTH, 2.0]])

	_add_value_track(animation, &"left_upper_arm_degrees", [
		[0.0, Vector3(-8.0, 0.0, 18.0)],
		[TYPING_LENGTH, Vector3(-8.0, 0.0, 18.0)],
	])
	_add_value_track(animation, &"right_upper_arm_degrees", [
		[0.0, Vector3(-8.0, 0.0, -18.0)],
		[TYPING_LENGTH, Vector3(-8.0, 0.0, -18.0)],
	])
	_add_value_track(animation, &"left_forearm_degrees", [
		[0.0, Vector3(-106.0, 0.0, 50.0)],
		[0.15, Vector3(-94.0, 0.0, 50.0)],
		[0.30, Vector3(-106.0, 0.0, 50.0)],
		[0.45, Vector3(-94.0, 0.0, 50.0)],
		[TYPING_LENGTH, Vector3(-106.0, 0.0, 50.0)],
	])
	_add_value_track(animation, &"right_forearm_degrees", [
		[0.0, Vector3(-94.0, 0.0, -50.0)],
		[0.15, Vector3(-106.0, 0.0, -50.0)],
		[0.30, Vector3(-94.0, 0.0, -50.0)],
		[0.45, Vector3(-106.0, 0.0, -50.0)],
		[TYPING_LENGTH, Vector3(-94.0, 0.0, -50.0)],
	])
	_add_value_track(animation, &"left_hand_degrees", [
		[0.0, Vector3(64.0, 0.0, -4.0)],
		[0.15, Vector3(52.0, 0.0, -4.0)],
		[0.30, Vector3(64.0, 0.0, -4.0)],
		[0.45, Vector3(52.0, 0.0, -4.0)],
		[TYPING_LENGTH, Vector3(64.0, 0.0, -4.0)],
	])
	_add_value_track(animation, &"right_hand_degrees", [
		[0.0, Vector3(52.0, 0.0, 4.0)],
		[0.15, Vector3(64.0, 0.0, 4.0)],
		[0.30, Vector3(52.0, 0.0, 4.0)],
		[0.45, Vector3(64.0, 0.0, 4.0)],
		[TYPING_LENGTH, Vector3(52.0, 0.0, 4.0)],
	])
	return animation


func _build_offline_sleep_animation() -> Animation:
	var animation := Animation.new()
	animation.length = OFFLINE_SLEEP_LENGTH
	animation.loop_mode = Animation.LOOP_LINEAR

	_add_value_track(animation, &"body_bob", [
		[0.0, -0.070],
		[1.4, -0.078],
		[2.45, -0.088],
		[2.68, -0.067],
		[3.15, -0.073],
		[4.0, -0.070],
	])
	_add_value_track(animation, &"chest_pitch_degrees", [
		[0.0, 8.5],
		[1.4, 9.5],
		[2.45, 11.5],
		[2.68, 7.0],
		[3.15, 8.2],
		[4.0, 8.5],
	])
	_add_value_track(animation, &"chest_roll_degrees", [
		[0.0, -0.8],
		[1.0, 0.6],
		[2.0, 1.0],
		[3.0, -0.7],
		[4.0, -0.8],
	])
	_add_value_track(animation, &"head_pitch_degrees", [
		[0.0, 12.0],
		[1.4, 16.0],
		[2.45, 23.0],
		[2.68, 6.0],
		[3.15, 11.0],
		[4.0, 12.0],
	])
	_add_value_track(animation, &"head_roll_degrees", [
		[0.0, -1.4],
		[1.0, -0.3],
		[2.0, 1.4],
		[3.0, 0.2],
		[4.0, -1.4],
	])
	_add_value_track(animation, &"left_upper_arm_degrees", [
		[0.0, Vector3(5.0, 0.0, 12.0)],
		[OFFLINE_SLEEP_LENGTH, Vector3(5.0, 0.0, 12.0)],
	])
	_add_value_track(animation, &"right_upper_arm_degrees", [
		[0.0, Vector3(5.0, 0.0, -12.0)],
		[OFFLINE_SLEEP_LENGTH, Vector3(5.0, 0.0, -12.0)],
	])
	_add_value_track(animation, &"left_forearm_degrees", [[0.0, Vector3.ZERO], [OFFLINE_SLEEP_LENGTH, Vector3.ZERO]])
	_add_value_track(animation, &"left_hand_degrees", [[0.0, Vector3.ZERO], [OFFLINE_SLEEP_LENGTH, Vector3.ZERO]])
	_add_value_track(animation, &"right_forearm_degrees", [[0.0, Vector3.ZERO], [OFFLINE_SLEEP_LENGTH, Vector3.ZERO]])
	_add_value_track(animation, &"right_hand_degrees", [[0.0, Vector3.ZERO], [OFFLINE_SLEEP_LENGTH, Vector3.ZERO]])
	return animation


func _add_neutral_limb_tracks(animation: Animation) -> void:
	var end_time := animation.length
	_add_value_track(animation, &"head_pitch_degrees", [[0.0, 0.0], [end_time, 0.0]])
	_add_value_track(animation, &"left_upper_arm_degrees", [[0.0, Vector3.ZERO], [end_time, Vector3.ZERO]])
	_add_value_track(animation, &"left_forearm_degrees", [[0.0, Vector3.ZERO], [end_time, Vector3.ZERO]])
	_add_value_track(animation, &"left_hand_degrees", [[0.0, Vector3.ZERO], [end_time, Vector3.ZERO]])
	_add_value_track(animation, &"right_upper_arm_degrees", [[0.0, Vector3.ZERO], [end_time, Vector3.ZERO]])
	_add_value_track(animation, &"right_forearm_degrees", [[0.0, Vector3.ZERO], [end_time, Vector3.ZERO]])
	_add_value_track(animation, &"right_hand_degrees", [[0.0, Vector3.ZERO], [end_time, Vector3.ZERO]])


func _add_value_track(animation: Animation, property_name: StringName, keys: Array) -> void:
	var track_index := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, NodePath(".:%s" % property_name))
	animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_CUBIC)
	animation.value_track_set_update_mode(track_index, Animation.UPDATE_CONTINUOUS)
	for key in keys:
		animation.track_insert_key(track_index, key[0], key[1])


func _apply_pose() -> void:
	if not is_instance_valid(_visual_root) or not is_instance_valid(_skeleton):
		return

	_visual_root.position = _base_visual_position + Vector3.UP * body_bob

	var chest_base: Quaternion = _base_bone_rotations[&"chest"]
	var head_base: Quaternion = _base_bone_rotations[&"head"]
	var chest_offset := Quaternion(Vector3.RIGHT, deg_to_rad(chest_pitch_degrees))
	chest_offset *= Quaternion(Vector3.FORWARD, deg_to_rad(chest_roll_degrees))
	var head_offset := (
		Quaternion(Vector3.RIGHT, deg_to_rad(head_pitch_degrees))
		* Quaternion(Vector3.FORWARD, deg_to_rad(head_roll_degrees))
	)
	_set_role_rotation(&"chest", chest_base * chest_offset)
	_set_role_rotation(&"head", head_base * head_offset)
	_apply_role_euler(&"left_upper_arm", left_upper_arm_degrees)
	_apply_role_euler(&"left_forearm", left_forearm_degrees)
	_apply_role_euler(&"left_hand", left_hand_degrees)
	_apply_role_euler(&"right_upper_arm", right_upper_arm_degrees)
	_apply_role_euler(&"right_forearm", right_forearm_degrees)
	_apply_role_euler(&"right_hand", right_hand_degrees)
	if is_instance_valid(_sleep_effect):
		_skeleton.force_update_all_bone_transforms()
		_sleep_effect.sync(loop_phase())


func _set_role_rotation(role: StringName, rotation: Quaternion) -> void:
	var bone_index := _profile.bone_index(_skeleton, role)
	if bone_index >= 0:
		_skeleton.set_bone_pose_rotation(bone_index, rotation)


func _apply_role_euler(role: StringName, degrees: Vector3) -> void:
	var radians := Vector3(
		deg_to_rad(degrees.x),
		deg_to_rad(degrees.y),
		deg_to_rad(degrees.z),
	)
	var base_rotation: Quaternion = _base_bone_rotations[role]
	_set_role_rotation(role, base_rotation * Quaternion.from_euler(radians))
