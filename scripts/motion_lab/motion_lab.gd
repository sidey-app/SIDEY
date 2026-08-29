extends Node3D

const ASSET_PATH := "res://assets/characters/dog/dog_mint_v1_rigged.glb"
const TypingKeyboardScript := preload("res://scripts/characters/typing_keyboard.gd")
const SleepEffectScript := preload("res://scripts/characters/sleep_effect.gd")

var _controller: CharacterMotionController
var _state_label: Label
var _notice_label: Label


func _ready() -> void:
	Engine.max_fps = 30
	RenderingServer.set_default_clear_color(Color("111722"))
	_setup_environment()
	_setup_camera()
	_setup_ui()

	if not ResourceLoader.exists(ASSET_PATH):
		_fail("Asset missing: %s" % ASSET_PATH)
		return

	var packed_scene := load(ASSET_PATH) as PackedScene
	if packed_scene == null:
		_fail("Asset could not be loaded: %s" % ASSET_PATH)
		return

	var visual_root := Node3D.new()
	visual_root.name = "CharacterVisualRoot"
	add_child(visual_root)

	var model := packed_scene.instantiate()
	model.name = "MintyPupModel"
	visual_root.add_child(model)
	_normalize_materials(model)

	var imported_animation_player := _find_first_animation_player(model)
	if imported_animation_player != null:
		imported_animation_player.stop()
		imported_animation_player.active = false

	var skeleton := _find_first_skeleton(model)
	if skeleton == null:
		_fail("Skeleton3D missing in %s" % ASSET_PATH)
		return
	var mesh_instance := _find_first_mesh(model)
	if mesh_instance == null:
		_fail("MeshInstance3D missing in %s" % ASSET_PATH)
		return
	var profile := CharacterRigProfile.minty_pup()

	var typing_keyboard := TypingKeyboardScript.new()
	typing_keyboard.name = "TypingKeyboard"
	visual_root.add_child(typing_keyboard)

	var sleep_effect := SleepEffectScript.new()
	sleep_effect.name = "SleepEffect"
	skeleton.add_child(sleep_effect)
	var sleep_effect_error := sleep_effect.configure(
		skeleton,
		profile.bone_name(&"head"),
	)
	if sleep_effect_error != OK:
		_fail("Sleep face effect could not bind to the head bone")
		return

	_controller = CharacterMotionController.new()
	_controller.name = "CharacterMotionController"
	add_child(_controller)
	var configure_error := _controller.configure(
		visual_root,
		skeleton,
		profile,
		typing_keyboard,
		sleep_effect,
	)
	if configure_error != OK:
		_fail("Rig profile validation failed; see error log")
		return

	_controller.state_changed.connect(_on_state_changed)
	var requested_state := _requested_review_state()
	_controller.set_state(requested_state, true)
	_state_label.text = "%s · REVIEW" % CharacterState.label(requested_state)
	_notice_label.text = "1: online_idle    2: typing    3: offline_sleep"
	print("MOTION_LAB_READY asset=%s state=%s" % [
		ASSET_PATH,
		CharacterState.label(requested_state),
	])


func _process(_delta: float) -> void:
	if _controller != null and is_instance_valid(_controller):
		_state_label.text = "%s · REVIEW · %3d%%" % [
			CharacterState.label(_controller.current_state()),
			roundi(_controller.loop_phase() * 100.0),
		]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	match event.physical_keycode:
		KEY_1:
			_controller.set_state(CharacterState.Value.ONLINE_IDLE, true)
			_notice_label.text = "online_idle restarted"
		KEY_2:
			_controller.set_state(CharacterState.Value.TYPING, true)
			_notice_label.text = "typing restarted"
		KEY_3:
			_controller.set_state(CharacterState.Value.OFFLINE_SLEEP, true)
			_notice_label.text = "offline_sleep restarted"
func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111722")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d8e7ef")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-32.0, -28.0, 0.0)
	key_light.light_color = Color("fff2dd")
	key_light.light_energy = 1.15
	key_light.shadow_enabled = false
	add_child(key_light)


func _setup_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "UpperBodyCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.36
	camera.position = Vector3(0.0, 1.16, 3.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.16, 0.0), Vector3.UP)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var title := Label.new()
	title.position = Vector2(24.0, 20.0)
	title.text = "SIDEY · MOTION LAB"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("9fe6d5"))
	canvas.add_child(title)

	_state_label = Label.new()
	_state_label.position = Vector2(24.0, 52.0)
	_state_label.add_theme_font_size_override("font_size", 16)
	_state_label.add_theme_color_override("font_color", Color("f5f7fa"))
	canvas.add_child(_state_label)

	_notice_label = Label.new()
	_notice_label.position = Vector2(24.0, 600.0)
	_notice_label.add_theme_font_size_override("font_size", 14)
	_notice_label.add_theme_color_override("font_color", Color("aebbc8"))
	canvas.add_child(_notice_label)


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


func _requested_review_state() -> CharacterState.Value:
	for argument in OS.get_cmdline_user_args():
		if argument == "--review=typing":
			return CharacterState.Value.TYPING
		if argument == "--review=offline_sleep":
			return CharacterState.Value.OFFLINE_SLEEP
	return CharacterState.Value.ONLINE_IDLE


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


func _on_state_changed(_previous_state: CharacterState.Value, next_state: CharacterState.Value) -> void:
	print("MOTION_STATE_CHANGED state=%s" % CharacterState.label(next_state))


func _fail(message: String) -> void:
	push_error(message)
	_state_label.text = "MOTION LAB ERROR"
	_notice_label.text = message
	get_tree().quit(1)
