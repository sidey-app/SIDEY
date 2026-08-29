extends Node3D

const CharacterRowScript := preload("res://scripts/characters/character_row.gd")
const OverlayControllerScript := preload("res://scripts/overlay/overlay_controller.gd")
const PlatformBridgeScript := preload("res://scripts/platform/platform_bridge.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const StatusMenuControllerScript := preload("res://scripts/app/status_menu_controller.gd")

var _character_row: CharacterRow
var _overlay_controller: OverlayController
var _platform_bridge: PlatformBridge
var _settings_store: SettingsStore
var _interaction_panel: Control
var _scale_label: Label
var _state_label: Label
var _debug_panel: Control
var _status_menu_controller: StatusMenuController
var _screen_locked := false
var _system_sleeping := false


func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_settings_store = SettingsStoreScript.new()
	_platform_bridge = PlatformBridgeScript.new()
	_platform_bridge.name = "PlatformBridge"
	add_child(_platform_bridge)
	_overlay_controller = OverlayControllerScript.new()
	_overlay_controller.name = "OverlayController"
	add_child(_overlay_controller)
	_overlay_controller.configure(get_window(), _settings_store)
	_overlay_controller.locked_changed.connect(_on_locked_changed)
	_overlay_controller.scale_changed.connect(_on_scale_changed)

	_character_row = CharacterRowScript.new() as CharacterRow
	_character_row.name = "CharacterRow"
	add_child(_character_row)
	var character_count := _requested_debug_character_count()
	var configure_error := _character_row.configure_debug(character_count)
	if configure_error != OK:
		_fail("Character row could not be configured", configure_error)
		return
	_setup_ui()
	_setup_status_menu()
	_setup_platform_bridge()
	_on_locked_changed(_overlay_controller.is_locked())
	_on_scale_changed(_overlay_controller.overlay_scale())
	if _has_argument("--unlocked"):
		_overlay_controller.set_locked(false, false)
	print("APP_ROOT_READY characters=%d report=%s" % [
		_character_row.character_count(),
		_overlay_controller.diagnostic_report(),
	])
	if _has_argument("--smoke-test"):
		get_tree().create_timer(0.25).timeout.connect(_finish_smoke_test)


func _exit_tree() -> void:
	if is_instance_valid(_overlay_controller):
		_overlay_controller.flush_settings()
	if is_instance_valid(_platform_bridge):
		_platform_bridge.unregister_hotkeys()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1:
			_set_debug_motion(CharacterState.Value.ONLINE_IDLE)
		KEY_2:
			_set_debug_motion(CharacterState.Value.TYPING)
		KEY_3:
			_set_debug_motion(CharacterState.Value.OFFLINE_SLEEP)


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
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
	camera.size = 1.48
	camera.position = Vector3(0.0, 1.16, 3.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.16, 0.0), Vector3.UP)


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	_state_label = Label.new()
	_state_label.position = Vector2(286.0, 296.0)
	_state_label.size = Vector2(148.0, 24.0)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.text = "●  Minty Pup · 나"
	_state_label.add_theme_font_size_override("font_size", 14)
	_state_label.add_theme_color_override("font_color", Color("a9eadb"))
	canvas.add_child(_state_label)

	_interaction_panel = PanelContainer.new()
	_interaction_panel.position = Vector2(182.0, 318.0)
	_interaction_panel.size = Vector2(356.0, 38.0)
	canvas.add_child(_interaction_panel)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	_interaction_panel.add_child(controls)
	var drag_button := Button.new()
	drag_button.text = "⠿ 이동"
	drag_button.tooltip_text = "SIDEY 캐릭터 전체를 이동"
	drag_button.button_down.connect(_overlay_controller.begin_drag)
	controls.add_child(drag_button)
	var scale_slider := HSlider.new()
	scale_slider.custom_minimum_size = Vector2(150.0, 0.0)
	scale_slider.min_value = 70.0
	scale_slider.max_value = 150.0
	scale_slider.step = 1.0
	scale_slider.value = _overlay_controller.overlay_scale() * 100.0
	scale_slider.value_changed.connect(func(value: float) -> void: _overlay_controller.set_overlay_scale(value / 100.0))
	controls.add_child(scale_slider)
	_scale_label = Label.new()
	_scale_label.custom_minimum_size = Vector2(44.0, 0.0)
	controls.add_child(_scale_label)
	var lock_button := Button.new()
	lock_button.text = "잠금"
	lock_button.pressed.connect(func() -> void: _overlay_controller.set_locked(true))
	controls.add_child(lock_button)

	if OS.is_debug_build():
		_debug_panel = HBoxContainer.new()
		_debug_panel.position = Vector2(12.0, 12.0)
		_debug_panel.add_theme_constant_override("separation", 4)
		canvas.add_child(_debug_panel)
		_add_state_button(_debug_panel, "온라인", CharacterState.Value.ONLINE_IDLE)
		_add_state_button(_debug_panel, "타이핑", CharacterState.Value.TYPING)
		_add_state_button(_debug_panel, "수면", CharacterState.Value.OFFLINE_SLEEP)


func _setup_status_menu() -> void:
	_status_menu_controller = StatusMenuControllerScript.new()
	_status_menu_controller.name = "StatusMenuController"
	add_child(_status_menu_controller)
	var status_menu_error := _status_menu_controller.configure(_overlay_controller, _settings_store)
	if status_menu_error != OK and status_menu_error != ERR_UNAVAILABLE:
		push_warning("STATUS_MENU_SETUP_FAILED error=%d" % status_menu_error)
	_status_menu_controller.compose_requested.connect(_on_compose_requested)
	_status_menu_controller.quit_requested.connect(_on_quit_requested)


func _setup_platform_bridge() -> void:
	_platform_bridge.screen_lock_changed.connect(_on_screen_lock_changed)
	_platform_bridge.system_sleep_changed.connect(_on_system_sleep_changed)
	_platform_bridge.system_resumed.connect(_on_system_resumed)
	_platform_bridge.global_shortcut_pressed.connect(_on_global_shortcut_pressed)
	_screen_locked = _platform_bridge.is_screen_locked()
	_sync_native_activity_state()
	if DisplayServer.get_name() == "headless" or not _platform_bridge.is_native_available():
		return
	_report_native_error(_platform_bridge.set_overlay_runtime_mode(true), "runtime_mode")
	_report_native_error(_platform_bridge.set_all_spaces_window_policy(true), "all_spaces")
	_report_native_error(_platform_bridge.register_default_hotkeys(), "global_hotkeys")


func _add_state_button(parent: Control, text: String, state: CharacterState.Value) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void: _set_debug_motion(state))
	parent.add_child(button)


func _set_debug_motion(state: CharacterState.Value) -> void:
	if is_instance_valid(_character_row):
		_character_row.set_all_motion_states(state, true)


func _on_locked_changed(locked: bool) -> void:
	if is_instance_valid(_interaction_panel):
		_interaction_panel.visible = not locked
	if is_instance_valid(_debug_panel):
		_debug_panel.visible = not locked
	if is_instance_valid(_platform_bridge) and DisplayServer.get_name() != "headless":
		_report_native_error(_platform_bridge.set_ignores_mouse_events(locked), "mouse_passthrough")


func _on_scale_changed(scale: float) -> void:
	if is_instance_valid(_scale_label):
		_scale_label.text = "%d%%" % roundi(scale * 100.0)


func _requested_debug_character_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--debug-characters="):
			return clampi(int(argument.trim_prefix("--debug-characters=")), 1, CharacterRow.MAX_CHARACTERS)
	return 1


func _has_argument(expected: String) -> bool:
	return expected in OS.get_cmdline_user_args()


func _finish_smoke_test() -> void:
	var capture_path := _argument_value("--capture=")
	if not capture_path.is_empty():
		var capture_error := get_viewport().get_texture().get_image().save_png(capture_path)
		if capture_error != OK:
			push_error("APP_ROOT_CAPTURE_FAILED path=%s error=%d" % [capture_path, capture_error])
			get_tree().quit(1)
			return
		print("APP_ROOT_CAPTURE_OK path=%s" % capture_path)
	print("APP_ROOT_SMOKE_OK report=%s status_menu=%s" % [
		{
			"overlay": _overlay_controller.diagnostic_report(),
			"platform": _platform_bridge.capability_report(),
		},
		_status_menu_controller.is_available(),
	])
	get_tree().quit(0)


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _on_compose_requested() -> void:
	_overlay_controller.set_overlay_visible(true)
	_overlay_controller.set_locked(false)
	_state_label.text = "●  메시지 UI는 로컬 UX 단계에서 연결"


func _on_global_shortcut_pressed(action: StringName) -> void:
	match action:
		&"compose":
			_on_compose_requested()
		&"toggle_lock":
			_overlay_controller.toggle_locked()


func _on_screen_lock_changed(locked: bool) -> void:
	_screen_locked = locked
	_sync_native_activity_state()


func _on_system_sleep_changed(sleeping: bool) -> void:
	_system_sleeping = sleeping
	_sync_native_activity_state()


func _on_system_resumed() -> void:
	_sync_native_activity_state()


func _sync_native_activity_state() -> void:
	if not is_instance_valid(_character_row):
		return
	var next_state := CharacterState.Value.OFFLINE_SLEEP \
		if _screen_locked or _system_sleeping \
		else CharacterState.Value.ONLINE_IDLE
	_character_row.set_all_motion_states(next_state, true)


func _report_native_error(error: Error, operation: String) -> void:
	if error != OK and error != ERR_UNAVAILABLE:
		push_warning("MACOS_BRIDGE_OPERATION_FAILED operation=%s error=%d" % [operation, error])


func _on_quit_requested() -> void:
	_overlay_controller.flush_settings()
	get_tree().quit(0)


func _fail(message: String, error: Error) -> void:
	push_error("APP_ROOT_FAILED message=%s error=%d" % [message, error])
	get_tree().quit(1)
