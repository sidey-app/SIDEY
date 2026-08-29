extends Node3D

const CharacterRowScript := preload("res://scripts/characters/character_row.gd")
const OverlayControllerScript := preload("res://scripts/overlay/overlay_controller.gd")
const PlatformBridgeScript := preload("res://scripts/platform/platform_bridge.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const StatusMenuControllerScript := preload("res://scripts/app/status_menu_controller.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const CharacterHudScript := preload("res://scripts/characters/character_hud.gd")
const ChatControllerScript := preload("res://scripts/chat/chat_controller.gd")
const OnboardingControllerScript := preload("res://scripts/onboarding/onboarding_controller.gd")
const SettingsControllerScript := preload("res://scripts/settings/settings_controller.gd")
const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const BackendRuntimeScript := preload("res://scripts/backend/backend_runtime.gd")
const ActivityPresenceScript := preload("res://scripts/platform/activity_presence.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const OverlayEditTrayScript := preload("res://scripts/overlay/overlay_edit_tray.gd")

var _character_row: CharacterRow
var _overlay_controller: OverlayController
var _platform_bridge: PlatformBridge
var _settings_store: SettingsStore
var _overlay_edit_tray: OverlayEditTray
var _debug_panel: Control
var _status_menu_controller: StatusMenuController
var _room_controller: RoomController
var _character_hud: CharacterHud
var _chat_controller: ChatController
var _onboarding_controller: OnboardingController
var _settings_controller: SettingsController
var _overlay_canvas: CanvasLayer
var _screen_locked := false
var _system_sleeping := false
var _platform_runtime_active := false
var _ephemeral_settings_path := ""
var _backend_runtime: BackendRuntime
var _idle_seconds := 0.0
var _idle_poll_elapsed := 0.0


func _ready() -> void:
	get_window().theme = SideyThemeScript.create()
	_setup_environment()
	_setup_camera()
	if _has_argument("--local-ux-demo") or _has_argument("--backend-app-smoke"):
		_ephemeral_settings_path = "/tmp/sidey-local-ux-%d.json" % OS.get_process_id()
	_settings_store = SettingsStoreScript.new(
		_ephemeral_settings_path if not _ephemeral_settings_path.is_empty() else "user://settings.json"
	)
	_room_controller = RoomControllerScript.new()
	_room_controller.name = "RoomController"
	add_child(_room_controller)
	var room_configure_error := _room_controller.configure(_settings_store)
	if room_configure_error != OK:
		_fail("Room state could not be restored", room_configure_error)
		return
	if _has_argument("--local-ux-demo"):
		var demo_error := _bootstrap_local_demo()
		if demo_error != OK:
			_fail("Local demo state could not be created", demo_error)
			return
	_platform_bridge = PlatformBridgeScript.new()
	_platform_bridge.name = "PlatformBridge"
	add_child(_platform_bridge)
	var backend_setup_error := _setup_backend_runtime()
	if backend_setup_error != OK:
		_fail("Backend configuration is invalid", backend_setup_error)
		return
	_overlay_controller = OverlayControllerScript.new()
	_overlay_controller.name = "OverlayController"
	add_child(_overlay_controller)
	_overlay_controller.configure(get_window(), _settings_store)
	_overlay_controller.locked_changed.connect(_on_locked_changed)
	_overlay_controller.scale_changed.connect(_on_scale_changed)
	_overlay_controller.overlay_visibility_changed.connect(_on_overlay_visibility_changed)

	_character_row = CharacterRowScript.new() as CharacterRow
	_character_row.name = "CharacterRow"
	add_child(_character_row)
	var configure_error := _configure_initial_characters()
	if configure_error != OK:
		_fail("Character row could not be configured", configure_error)
		return
	_setup_ui()
	_setup_local_ux()
	_setup_status_menu()
	_setup_platform_bridge()
	_on_locked_changed(_overlay_controller.is_locked())
	_on_scale_changed(_overlay_controller.overlay_scale())
	_on_overlay_visibility_changed(_overlay_controller.is_overlay_visible())
	if _has_argument("--unlocked"):
		_overlay_controller.set_locked(false, false)
	elif _has_argument("--locked"):
		_overlay_controller.set_locked(true, false)
	if is_instance_valid(_backend_runtime):
		_character_row.visible = false
		_character_hud.visible = false
		_start_backend_flow.call_deferred()
	elif _room_controller.is_onboarding_complete():
		_activate_room_session()
	elif _has_argument("--smoke-test") or DisplayServer.get_name() == "headless":
		_configure_debug_hud()
		_activate_platform_runtime()
	else:
		_character_row.visible = false
		_character_hud.visible = false
		_onboarding_controller.show_onboarding(_room_controller)
	_apply_debug_actions()
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
	if not _ephemeral_settings_path.is_empty():
		DirAccess.remove_absolute(_ephemeral_settings_path)


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


func _process(delta: float) -> void:
	if not is_instance_valid(_platform_bridge) or not _platform_bridge.is_native_available():
		return
	_idle_poll_elapsed += delta
	if _idle_poll_elapsed < 1.0:
		return
	_idle_poll_elapsed = 0.0
	var next_idle_seconds := _platform_bridge.get_idle_seconds()
	var was_away := _idle_seconds >= ActivityPresence.DEFAULT_IDLE_THRESHOLD_SECONDS
	var is_away := next_idle_seconds >= ActivityPresence.DEFAULT_IDLE_THRESHOLD_SECONDS
	_idle_seconds = next_idle_seconds
	if was_away != is_away:
		_sync_native_activity_state()


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
	_overlay_canvas = CanvasLayer.new()
	_overlay_canvas.layer = 10
	add_child(_overlay_canvas)

	_overlay_edit_tray = OverlayEditTrayScript.new() as OverlayEditTray
	_overlay_edit_tray.name = "OverlayEditTray"
	_overlay_canvas.add_child(_overlay_edit_tray)
	_overlay_edit_tray.history_requested.connect(_on_history_requested)
	_overlay_edit_tray.locked_change_requested.connect(_overlay_controller.set_locked)
	_overlay_edit_tray.drag_requested.connect(_overlay_controller.begin_drag)
	_overlay_edit_tray.scale_requested.connect(_overlay_controller.set_overlay_scale)
	_overlay_edit_tray.set_overlay_scale(_overlay_controller.overlay_scale())
	_overlay_edit_tray.set_available(false)

	if OS.is_debug_build() and _has_argument("--motion-controls"):
		_debug_panel = HBoxContainer.new()
		_debug_panel.position = Vector2(12.0, 12.0)
		_debug_panel.add_theme_constant_override("separation", 4)
		_overlay_canvas.add_child(_debug_panel)
		_add_state_button(_debug_panel, "온라인", CharacterState.Value.ONLINE_IDLE)
		_add_state_button(_debug_panel, "타이핑", CharacterState.Value.TYPING)
		_add_state_button(_debug_panel, "수면", CharacterState.Value.OFFLINE_SLEEP)


func _setup_local_ux() -> void:
	_character_hud = CharacterHudScript.new()
	_character_hud.name = "CharacterHud"
	_overlay_canvas.add_child(_character_hud)
	_chat_controller = ChatControllerScript.new()
	_chat_controller.name = "ChatController"
	add_child(_chat_controller)
	_chat_controller.configure(_room_controller, _overlay_canvas, _backend_runtime)
	_chat_controller.message_accepted.connect(_on_message_accepted)
	_chat_controller.typing_event.connect(_on_typing_event)
	_chat_controller.input_visibility_changed.connect(_on_chat_input_visibility_changed)
	_chat_controller.history_visibility_changed.connect(_on_history_visibility_changed)
	_onboarding_controller = OnboardingControllerScript.new()
	_onboarding_controller.name = "OnboardingController"
	add_child(_onboarding_controller)
	_onboarding_controller.completed.connect(_on_onboarding_completed)
	_settings_controller = SettingsControllerScript.new()
	_settings_controller.name = "SettingsController"
	add_child(_settings_controller)
	_settings_controller.configure(_room_controller, _platform_bridge, _backend_runtime)
	_settings_controller.opened.connect(_on_settings_opened)
	_settings_controller.closed.connect(_on_settings_closed)
	_room_controller.active_room_changed.connect(_on_active_room_changed)
	_room_controller.profile_changed.connect(_on_profile_changed)
	_room_controller.rooms_changed.connect(_on_rooms_changed_for_session)
	if is_instance_valid(_backend_runtime):
		_backend_runtime.message_received.connect(_on_backend_message_received)
		_backend_runtime.typing_changed.connect(_on_backend_typing_changed)
		_backend_runtime.presence_changed.connect(_on_backend_presence_changed)


func _setup_status_menu() -> void:
	_status_menu_controller = StatusMenuControllerScript.new()
	_status_menu_controller.name = "StatusMenuController"
	add_child(_status_menu_controller)
	var status_menu_error := _status_menu_controller.configure(
		_overlay_controller,
		_settings_store,
		_room_controller,
	)
	if status_menu_error != OK and status_menu_error != ERR_UNAVAILABLE:
		push_warning("STATUS_MENU_SETUP_FAILED error=%d" % status_menu_error)
	_status_menu_controller.compose_requested.connect(_on_compose_requested)
	_status_menu_controller.quit_requested.connect(_on_quit_requested)
	_status_menu_controller.settings_requested.connect(_settings_controller.open)
	_status_menu_controller.quiet_mode_changed.connect(_on_quiet_mode_changed)
	_status_menu_controller.room_selected.connect(_on_room_selected)
	_chat_controller.set_quiet_mode(_status_menu_controller.quiet_mode())


func _setup_platform_bridge() -> void:
	_platform_bridge.screen_lock_changed.connect(_on_screen_lock_changed)
	_platform_bridge.system_sleep_changed.connect(_on_system_sleep_changed)
	_platform_bridge.system_resumed.connect(_on_system_resumed)
	_platform_bridge.global_shortcut_pressed.connect(_on_global_shortcut_pressed)
	_screen_locked = _platform_bridge.is_screen_locked()
	_idle_seconds = _platform_bridge.get_idle_seconds()
	_sync_native_activity_state()


func _setup_backend_runtime() -> Error:
	if _has_argument("--local-ux-demo") or _has_argument("--smoke-test") or _has_argument("--offline"):
		return OK
	var config := BackendConfigScript.from_environment()
	var has_partial_config := not config.url.is_empty() or not config.publishable_key.is_empty()
	if not config.is_valid():
		return ERR_INVALID_PARAMETER if has_partial_config else OK
	_backend_runtime = BackendRuntimeScript.new() as BackendRuntime
	_backend_runtime.name = "BackendRuntime"
	add_child(_backend_runtime)
	var session_profile := _argument_value("--backend-profile=")
	return _backend_runtime.configure(
		config,
		_platform_bridge,
		_room_controller,
		"default" if session_profile.is_empty() else session_profile,
	)


func _start_backend_flow() -> void:
	var result: Dictionary = await _backend_runtime.start()
	if not bool(result.get("ok", false)):
		if _has_argument("--backend-app-smoke"):
			push_error("BACKEND_APP_SMOKE_BOOT_FAILED code=%s" % str(result.get("error_code", "unknown")))
			get_tree().quit(1)
			return
		_onboarding_controller.show_onboarding(_room_controller, _backend_runtime)
		_onboarding_controller.show_blocking_error(
			"서버에 연결하지 못했음. 네트워크와 SIDEY 백엔드 설정을 확인한 뒤 앱을 다시 실행해줘.\n오류: %s" \
			% str(result.get("error_code", "unknown"))
		)
		return
	if _has_argument("--backend-app-smoke"):
		_run_backend_app_smoke.call_deferred()
	elif bool(result.get("onboarding_required", false)):
		_onboarding_controller.show_onboarding(_room_controller, _backend_runtime)
	else:
		_activate_room_session()


func _run_backend_app_smoke() -> void:
	if _room_controller.rooms().is_empty():
		var onboarded: Dictionary = await _backend_runtime.onboard_create(
			"앱스모크",
			"minty_pup",
			"앱 스모크 방",
		)
		if not bool(onboarded.get("ok", false)):
			push_error("BACKEND_APP_SMOKE_ONBOARD_FAILED code=%s" % str(onboarded.get("error_code", "unknown")))
			get_tree().quit(1)
			return
	_activate_room_session()
	var message_id := ChatControllerScript._uuid_v4()
	var sent: Dictionary = await _backend_runtime.send_message(
		message_id,
		_room_controller.active_room_id(),
		"AppRoot 백엔드 연결 확인",
	)
	if not bool(sent.get("ok", false)):
		push_error("BACKEND_APP_SMOKE_MESSAGE_FAILED code=%s" % str(sent.get("error_code", "unknown")))
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.4).timeout
	if _chat_controller.recent_messages(_room_controller.active_room_id()).is_empty():
		push_error("BACKEND_APP_SMOKE_MESSAGE_NOT_APPLIED")
		get_tree().quit(1)
		return
	var room_ids: Array[String] = []
	for room in _room_controller.rooms():
		room_ids.append(str(room.get("id", "")))
	for room_id in room_ids:
		await _backend_runtime.leave_room(room_id)
	_backend_runtime.backend_client().clear_session()
	print("SIDEY_BACKEND_APP_SMOKE_OK")
	get_tree().quit(0)


func _activate_platform_runtime() -> void:
	if _platform_runtime_active:
		return
	_platform_runtime_active = true
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
	if is_instance_valid(_overlay_edit_tray):
		_overlay_edit_tray.set_locked(locked)
	if is_instance_valid(_chat_controller):
		_chat_controller.set_history_access_enabled(not locked)
	if is_instance_valid(_debug_panel):
		_debug_panel.visible = not locked
	if is_instance_valid(_platform_bridge) and DisplayServer.get_name() != "headless":
		_report_native_error(_platform_bridge.set_ignores_mouse_events(false), "mouse_passthrough_polygon")
	_sync_overlay_interaction_state()


func _on_scale_changed(scale: float) -> void:
	if is_instance_valid(_overlay_edit_tray):
		_overlay_edit_tray.set_overlay_scale(scale)


func _on_overlay_visibility_changed(overlay_visible: bool) -> void:
	if is_instance_valid(_character_row):
		_character_row.process_mode = Node.PROCESS_MODE_INHERIT \
			if overlay_visible else Node.PROCESS_MODE_DISABLED


func _requested_debug_character_count() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--debug-characters="):
			return clampi(int(argument.trim_prefix("--debug-characters=")), 1, CharacterRow.MAX_CHARACTERS)
	return 1


func _configure_initial_characters() -> Error:
	if _room_controller.is_onboarding_complete():
		var members: Array[Dictionary] = []
		for member in _room_controller.active_room().get("members", []) as Array:
			members.append((member as Dictionary).duplicate(true))
		return _character_row.configure_members(members)
	return _character_row.configure_debug(_requested_debug_character_count())


func _bootstrap_local_demo() -> Error:
	var profile_error := _room_controller.set_profile("민트", "minty_pup")
	if profile_error != OK:
		return profile_error
	var join_error := _room_controller.join_demo_room(RoomController.DEMO_INVITE_CODE)
	if join_error != OK:
		return join_error
	return _room_controller.complete_onboarding()


func _configure_debug_hud() -> void:
	_character_hud.configure_room({
		"name": "로컬 검증",
		"members": _character_row.members(),
	})


func _apply_debug_actions() -> void:
	if not OS.is_debug_build():
		return
	if _has_argument("--open-composer"):
		_on_compose_requested()
	if _has_argument("--demo-message") and _room_controller.is_onboarding_complete():
		var members: Array = _room_controller.active_room().get("members", []) as Array
		if not members.is_empty():
			var sender := members[mini(1, members.size() - 1)] as Dictionary
			_chat_controller.receive_message({
				"id": "debug-message-%d" % Time.get_ticks_usec(),
				"room_id": _room_controller.active_room_id(),
				"sender_id": str(sender.get("user_id", "")),
				"body": "오늘 저녁 같이 먹을래?",
				"created_at": Time.get_unix_time_from_system(),
			})
	if _has_argument("--open-history"):
		_on_history_requested()


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
	_chat_controller.open_composer()


func _on_history_requested() -> void:
	if not is_instance_valid(_chat_controller):
		return
	_chat_controller.toggle_history()


func _on_onboarding_completed() -> void:
	_activate_room_session()
	_overlay_controller.set_overlay_visible(true)


func _activate_room_session() -> void:
	var room := _room_controller.active_room()
	if room.is_empty():
		return
	var members: Array[Dictionary] = []
	for member in room.get("members", []) as Array:
		members.append((member as Dictionary).duplicate(true))
	var configure_error := _character_row.configure_members(members)
	if configure_error != OK:
		_fail("Active room characters could not be configured", configure_error)
		return
	_character_row.visible = true
	_character_hud.visible = true
	_character_hud.configure_room(room)
	_chat_controller.set_anchor_x(_character_hud.self_anchor_x())
	_overlay_edit_tray.set_character_anchor(_character_hud.self_anchor_x(), _chat_controller.composer_rect())
	_overlay_edit_tray.set_available(true)
	_chat_controller.set_session(room, _room_controller.profile())
	_sync_overlay_interaction_state()
	_activate_platform_runtime()


func _on_active_room_changed(_previous_room_id: String, _room_id: String) -> void:
	if _room_controller.is_onboarding_complete():
		_activate_room_session()


func _on_profile_changed(_profile: Dictionary) -> void:
	if _room_controller.is_onboarding_complete():
		_activate_room_session()


func _on_rooms_changed_for_session(_rooms: Array[Dictionary]) -> void:
	if not is_instance_valid(_backend_runtime) or not _room_controller.rooms().is_empty():
		return
	_character_row.clear()
	_character_row.visible = false
	_character_hud.clear_members()
	_character_hud.visible = false
	_chat_controller.set_session({}, {})
	_overlay_edit_tray.set_available(false)
	_sync_overlay_interaction_state()
	_onboarding_controller.show_onboarding(_room_controller, _backend_runtime)


func _on_room_selected(room_id: String) -> void:
	var error := _room_controller.set_active_room(room_id)
	if error != OK:
		push_warning("ROOM_SWITCH_FAILED room_id=%s error=%d" % [room_id, error])


func _on_quiet_mode_changed(enabled: bool) -> void:
	_chat_controller.set_quiet_mode(enabled)
	if enabled:
		_character_hud.hide_all_messages()


func _on_chat_input_visibility_changed(_input_visible: bool) -> void:
	_sync_overlay_interaction_state()


func _on_history_visibility_changed(_history_visible: bool) -> void:
	_sync_overlay_interaction_state()


func _sync_overlay_interaction_state() -> void:
	if not is_instance_valid(_overlay_controller):
		return
	var regions: Array[Rect2] = []
	if is_instance_valid(_chat_controller) and _chat_controller.composer_visible():
		regions.append(_chat_controller.composer_rect())
	if is_instance_valid(_overlay_edit_tray) and _overlay_edit_tray.is_available():
		regions.append(_overlay_edit_tray.interactive_rect())
	if is_instance_valid(_chat_controller) and _chat_controller.history_visible():
		regions.append(_chat_controller.history_rect())
	_overlay_controller.set_interactive_regions(regions)


func _on_settings_opened() -> void:
	if DisplayServer.get_name() != "headless" and _platform_bridge.is_native_available():
		_report_native_error(_platform_bridge.set_overlay_runtime_mode(false), "settings_runtime_mode")


func _on_settings_closed() -> void:
	if _platform_runtime_active and DisplayServer.get_name() != "headless":
		_report_native_error(_platform_bridge.set_overlay_runtime_mode(true), "overlay_runtime_mode")


func _on_message_accepted(message: Dictionary, active_room: bool) -> void:
	if not active_room or _chat_controller.quiet_mode():
		return
	_character_hud.show_message(str(message.get("sender_id", "")), str(message.get("body", "")))


func _on_typing_event(action: StringName, room_id: String, user_id: String) -> void:
	if is_instance_valid(_backend_runtime):
		var send_error := _backend_runtime.send_typing(room_id, action)
		if send_error != OK and send_error != ERR_UNCONFIGURED:
			push_warning("BACKEND_TYPING_SEND_FAILED error=%d" % send_error)
	if room_id != _room_controller.active_room_id():
		return
	var presence := PresenceState.Value.TYPING if action != &"typing_stop" else _local_resting_presence()
	_character_row.set_member_presence(user_id, presence, false)
	_character_hud.set_presence(user_id, presence)


func _on_backend_message_received(message: Dictionary, replayed: bool) -> void:
	var error := _chat_controller.restore_message(message) if replayed else _chat_controller.receive_message(message)
	if error not in [OK, ERR_ALREADY_EXISTS]:
		push_warning("BACKEND_MESSAGE_APPLY_FAILED error=%d" % error)


func _on_backend_typing_changed(room_id: String, user_id: String, typing: bool) -> void:
	if room_id != _room_controller.active_room_id():
		return
	var presence := PresenceState.Value.TYPING if typing else _cached_member_presence(room_id, user_id)
	_character_row.set_member_presence(user_id, presence, false)
	_character_hud.set_presence(user_id, presence)


func _on_backend_presence_changed(room_id: String, user_id: String, presence: String) -> void:
	if room_id != _room_controller.active_room_id():
		return
	var value := PresenceState.from_string(presence)
	_character_row.set_member_presence(user_id, value, false)
	_character_hud.set_presence(user_id, value)


func _cached_member_presence(room_id: String, user_id: String) -> PresenceState.Value:
	for member in _room_controller.room_by_id(room_id).get("members", []) as Array:
		if str((member as Dictionary).get("user_id", "")) == user_id:
			return PresenceState.from_string(str((member as Dictionary).get("presence", "offline")))
	return PresenceState.Value.OFFLINE


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
	if is_instance_valid(_backend_runtime):
		var reconnect_error := _backend_runtime.reconnect_after_resume()
		if reconnect_error != OK:
			push_warning("BACKEND_RESUME_RECONNECT_FAILED error=%d" % reconnect_error)


func _sync_native_activity_state() -> void:
	if not is_instance_valid(_character_row) or not is_instance_valid(_room_controller):
		return
	var presence := _local_resting_presence()
	if is_instance_valid(_backend_runtime):
		_backend_runtime.set_local_presence("away" if presence == PresenceState.Value.AWAY else "online")
	var user_id := str(_room_controller.profile().get("user_id", ""))
	if user_id.is_empty() or _character_row.member_index(user_id) < 0:
		return
	_character_row.set_member_presence(user_id, presence, true)
	_character_hud.set_presence(user_id, presence)


func _local_resting_presence() -> PresenceState.Value:
	return PresenceState.Value.AWAY \
		if ActivityPresenceScript.state(_screen_locked, _system_sleeping, _idle_seconds) == "away" \
		else PresenceState.Value.ONLINE


func _report_native_error(error: Error, operation: String) -> void:
	if error != OK and error != ERR_UNAVAILABLE:
		push_warning("MACOS_BRIDGE_OPERATION_FAILED operation=%s error=%d" % [operation, error])


func _on_quit_requested() -> void:
	_overlay_controller.flush_settings()
	get_tree().quit(0)


func _fail(message: String, error: Error) -> void:
	push_error("APP_ROOT_FAILED message=%s error=%d" % [message, error])
	get_tree().quit(1)
