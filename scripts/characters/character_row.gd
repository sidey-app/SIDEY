class_name CharacterRow
extends Node3D

const MAX_CHARACTERS := 5
const CharacterViewScript := preload("res://scripts/characters/character_view.gd")

var _characters: Array[CharacterView] = []
var _members: Array[Dictionary] = []


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


func configure_members(members: Array[Dictionary]) -> Error:
	clear()
	if members.is_empty() or members.size() > MAX_CHARACTERS:
		return ERR_INVALID_PARAMETER
	_members = members.duplicate(true)
	var safe_count := members.size()
	var positions := layout_positions(safe_count)
	var visual_scale := 1.0 if safe_count == 1 else 0.58
	for index in safe_count:
		var member := members[index]
		var character_id := str(member.get("character_id", "minty_pup"))
		var character := CharacterViewScript.new() as CharacterView
		character.name = "Character_%s" % str(member.get("user_id", index)).validate_node_name()
		character.position.x = positions[index]
		character.scale = Vector3.ONE * visual_scale
		add_child(character)
		var configure_error := character.configure(character_id)
		if configure_error != OK:
			clear()
			return configure_error
		_characters.append(character)
		var presence := PresenceState.from_string(str(member.get("presence", "offline")))
		character.set_motion_state(PresenceState.motion_state(presence), true)
	return OK


func clear() -> void:
	for character in _characters:
		if is_instance_valid(character):
			character.queue_free()
	_characters.clear()
	_members.clear()


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


func set_motion_state(index: int, state: CharacterState.Value, restart := false) -> void:
	if index < 0 or index >= _characters.size():
		return
	_characters[index].set_motion_state(state, restart)


static func layout_positions(count: int) -> Array[float]:
	var safe_count := clampi(count, 1, MAX_CHARACTERS)
	if safe_count == 1:
		return [0.0]
	var spacing := 0.58
	var start := -spacing * (safe_count - 1) * 0.5
	var positions: Array[float] = []
	for index in safe_count:
		positions.append(start + index * spacing)
	return positions
