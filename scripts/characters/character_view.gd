class_name CharacterView
extends Node3D

const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")
const TypingKeyboardScript := preload("res://scripts/characters/typing_keyboard.gd")
const SleepEffectScript := preload("res://scripts/characters/sleep_effect.gd")

var motion_controller: CharacterMotionController
var character_id := ""


func configure(requested_character_id: String) -> Error:
	if CharacterCatalogScript.has(requested_character_id) == false:
		push_error("CHARACTER_UNKNOWN id=%s" % requested_character_id)
		return ERR_DOES_NOT_EXIST
	var entry := CharacterCatalogScript.get_entry(requested_character_id)
	var model_path := str(entry["model_path"])
	if not ResourceLoader.exists(model_path):
		push_error("CHARACTER_ASSET_MISSING id=%s path=%s" % [requested_character_id, model_path])
		return ERR_FILE_NOT_FOUND
	var packed_scene := load(model_path) as PackedScene
	if packed_scene == null:
		push_error("CHARACTER_ASSET_LOAD_FAILED id=%s path=%s" % [requested_character_id, model_path])
		return ERR_CANT_OPEN

	character_id = requested_character_id
	var visual_root := Node3D.new()
	visual_root.name = "CharacterVisualRoot"
	add_child(visual_root)
	var model := packed_scene.instantiate()
	model.name = "%sModel" % requested_character_id.to_pascal_case()
	visual_root.add_child(model)
	_normalize_materials(model)

	var imported_animation_player := _find_first_animation_player(model)
	if imported_animation_player != null:
		imported_animation_player.stop()
		imported_animation_player.active = false
	var skeleton := _find_first_skeleton(model)
	if skeleton == null:
		push_error("CHARACTER_SKELETON_MISSING id=%s" % requested_character_id)
		return ERR_INVALID_DATA
	if _find_first_mesh(model) == null:
		push_error("CHARACTER_MESH_MISSING id=%s" % requested_character_id)
		return ERR_INVALID_DATA
	var profile := CharacterCatalogScript.rig_profile(requested_character_id)
	if profile == null:
		push_error("CHARACTER_RIG_PROFILE_MISSING id=%s" % requested_character_id)
		return ERR_INVALID_DATA

	var typing_keyboard := TypingKeyboardScript.new()
	typing_keyboard.name = "TypingKeyboard"
	visual_root.add_child(typing_keyboard)
	var sleep_effect := SleepEffectScript.new()
	sleep_effect.name = "SleepEffect"
	skeleton.add_child(sleep_effect)
	var sleep_effect_error := sleep_effect.configure(skeleton, profile.bone_name(&"head"))
	if sleep_effect_error != OK:
		return sleep_effect_error

	motion_controller = CharacterMotionController.new()
	motion_controller.name = "CharacterMotionController"
	add_child(motion_controller)
	return motion_controller.configure(visual_root, skeleton, profile, typing_keyboard, sleep_effect)


func set_motion_state(state: CharacterState.Value, restart := false) -> void:
	if is_instance_valid(motion_controller):
		motion_controller.set_state(state, restart)


func _find_first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_first_skeleton(child)
		if found != null:
			return found
	return null


func _find_first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_first_mesh(child)
		if found != null:
			return found
	return null


func _find_first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_first_animation_player(child)
		if found != null:
			return found
	return null


func _normalize_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var source_material := mesh_instance.mesh.surface_get_material(surface_index)
				if source_material is BaseMaterial3D:
					var material := source_material.duplicate() as BaseMaterial3D
					material.emission_enabled = false
					material.metallic = 0.0
					material.roughness = 0.85
					mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_normalize_materials(child)
