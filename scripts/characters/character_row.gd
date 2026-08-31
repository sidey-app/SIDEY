class_name CharacterRow
extends Node3D

const MAX_CHARACTERS := 5
const CharacterViewScript := preload("res://scripts/characters/character_view.gd")
const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")

var _characters: Array[CharacterView] = []
var _members: Array[Dictionary] = []
var _base_positions: Array[float] = []
var _base_visual_scale := 1.0
var _overlay_scale := OverlayGeometryScript.MIN_SCALE


func configure_debug(count: int, character_id: String = "minty_pup") -> Error:
	var debug_members: Array[Dictionary] = []
	for index in clampi(count, 1, MAX_CHARACTERS):
		debug_members.append({
			"user_id": "debug-%d" % index,
			"nickname": "Debug %d" % (index + 1),
			"character_id": character_id,
			"presence": "online",
			"is_self": index == 0,
		})
	return configure_members(debug_members)


func configure_members(
	members: Array[Dictionary],
	model_path_override := "",
	use_imported_animations := false,
) -> Error:
	clear()
	if members.is_empty() or members.size() > MAX_CHARACTERS:
		return ERR_INVALID_PARAMETER
	_members = members.duplicate(true)
	var safe_count := members.size()
	var positions := layout_positions(safe_count)
	_base_positions = positions.duplicate()
	_base_visual_scale = 0.74 if safe_count == 1 else 0.58
	var vertical_offset := 1.16 if use_imported_animations else (0.24 if safe_count == 1 else 0.30)
	for index in safe_count:
		var member := members[index]
		var character_id := str(member.get("character_id", "minty_pup"))
		var character := CharacterViewScript.new() as CharacterView
		character.name = "Character_%s" % str(member.get("user_id", index)).validate_node_name()
		character.position.x = positions[index]
		character.position.y = vertical_offset
		character.scale = Vector3.ONE * _base_visual_scale
		add_child(character)
		var configure_error := character.configure(
			character_id,
			model_path_override,
			use_imported_animations,
		)
		if configure_error != OK:
			clear()
			return configure_error
		_characters.append(character)
		var presence := PresenceState.from_string(str(member.get("presence", "offline")))
		character.set_motion_state(PresenceState.motion_state(presence), true)
	_apply_overlay_scale()
	return OK


func clear() -> void:
	for character in _characters:
		if is_instance_valid(character):
			character.queue_free()
	_characters.clear()
	_members.clear()
	_base_positions.clear()


func character_count() -> int:
	return _characters.size()


func members() -> Array[Dictionary]:
	return _members.duplicate(true)


func member_index(user_id: String) -> int:
	for index in _members.size():
		if str(_members[index].get("user_id", "")) == user_id:
			return index
	return -1


func set_member_presence(user_id: String, presence: PresenceState.Value, restart := false) -> Error:
	var index := member_index(user_id)
	if index < 0:
		return ERR_DOES_NOT_EXIST
	_members[index]["presence"] = str(PresenceState.to_string_name(presence))
	set_motion_state(index, PresenceState.motion_state(presence), restart)
	return OK


func set_all_motion_states(state: CharacterState.Value, restart := false) -> void:
	for character in _characters:
		character.set_motion_state(state, restart)


func set_overlay_scale(scale: float) -> void:
	_overlay_scale = OverlayGeometryScript.clamp_scale(scale)
	_apply_overlay_scale()


func projected_head_anchors(camera: Camera3D) -> Dictionary:
	var result := {}
	if not is_instance_valid(camera):
		return result
	for index in mini(_members.size(), _characters.size()):
		result[str(_members[index].get("user_id", ""))] = camera.unproject_position(
			_characters[index].head_anchor_global(),
		)
	return result


func _apply_overlay_scale() -> void:
	var factor := _overlay_scale / OverlayGeometryScript.FIXED_WINDOW_SCALE
	for index in _characters.size():
		if index >= _base_positions.size():
			continue
		_characters[index].position.x = _base_positions[index] * factor
		_characters[index].scale = Vector3.ONE * _base_visual_scale * factor


func set_motion_state(index: int, state: CharacterState.Value, restart := false) -> void:
	if index < 0 or index >= _characters.size():
		return
	_characters[index].set_motion_state(state, restart)


static func layout_positions(count: int) -> Array[float]:
	var safe_count := clampi(count, 1, MAX_CHARACTERS)
	if safe_count == 1:
		return [0.0]
	var spacing := 0.585
	var start := -spacing * (safe_count - 1) * 0.5
	var positions: Array[float] = []
	for index in safe_count:
		positions.append(start + index * spacing)
	return positions
