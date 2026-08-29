class_name CharacterRow
extends Node3D

const MAX_CHARACTERS := 5
const CharacterViewScript := preload("res://scripts/characters/character_view.gd")

var _characters: Array[CharacterView] = []


func configure_debug(count: int, character_id: String = "minty_pup") -> Error:
	clear()
	var safe_count := clampi(count, 1, MAX_CHARACTERS)
	var positions := layout_positions(safe_count)
	var visual_scale := 1.0 if safe_count == 1 else 0.58
	for index in safe_count:
		var character := CharacterViewScript.new() as CharacterView
		character.name = "Character%d" % (index + 1)
		character.position.x = positions[index]
		character.scale = Vector3.ONE * visual_scale
		add_child(character)
		var configure_error := character.configure(character_id)
		if configure_error != OK:
			clear()
			return configure_error
		_characters.append(character)
	return OK


func clear() -> void:
	for character in _characters:
		if is_instance_valid(character):
			character.queue_free()
	_characters.clear()


func character_count() -> int:
	return _characters.size()


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
