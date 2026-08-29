class_name ChatController
extends Node

signal message_accepted(message: Dictionary, active_room: bool)
signal message_rejected(message: Dictionary, error_code: String)
signal typing_event(action: StringName, room_id: String, user_id: String)
signal input_visibility_changed(visible: bool)
signal history_visibility_changed(visible: bool)
signal composer_hover_changed(hovered: bool)

const ChatStoreScript := preload("res://scripts/chat/chat_store.gd")
const TypingTrackerScript := preload("res://scripts/chat/typing_tracker.gd")
const OverlayThemeScript := preload("res://scripts/ui/overlay_theme.gd")
const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const LOGICAL_WIDTH := 720.0
const COMPOSER_SIZE := Vector2(224.0, 42.0)
const COMPOSER_GAP := 4.0
const DEFAULT_IDENTITY_BASELINE_Y := 318.0
const HISTORY_SIZE := Vector2(320.0, 226.0)
const HISTORY_GAP := 6.0
const EDGE_MARGIN := 8.0
const FIXED_UI_FACTOR := OverlayGeometryScript.FIXED_UI_FACTOR
const IME_SUBMIT_MAX_WAIT_FRAMES := 4
const NATIVE_ENTER_NONE := -1
const NATIVE_ENTER_SUBMIT := 0
const NATIVE_ENTER_NEWLINE := 1

var _room_controller: RoomController
var _chat_store: ChatStore
var _typing_tracker: TypingTracker
var _canvas: CanvasLayer
var _input_panel: PanelContainer
var _text_edit: TextEdit
var _history_panel: PanelContainer
var _history_list: VBoxContainer
var _active_room_id := ""
var _self_user_id := ""
var _quiet_mode := false
var _backend_runtime: BackendRuntime
var _send_in_progress := false
var _anchor_x := LOGICAL_WIDTH * 0.5
var _identity_baseline_y := DEFAULT_IDENTITY_BASELINE_Y
var _last_valid_draft := ""
var _restoring_draft := false
var _history_access_enabled := false
var _submit_queued := false
var _submit_wait_frames := 0
var _native_enter_events_enabled := false
var _native_enter_action := NATIVE_ENTER_NONE
var _native_enter_wait_frames := 0
var _platform_bridge: PlatformBridge


func configure(
	room_controller: RoomController,
	canvas: CanvasLayer,
	backend_runtime: BackendRuntime = null,
	platform_bridge: PlatformBridge = null,
) -> void:
	_room_controller = room_controller
	_canvas = canvas
	_backend_runtime = backend_runtime
	_platform_bridge = platform_bridge
	_chat_store = ChatStoreScript.new()
	_typing_tracker = TypingTrackerScript.new()
	_build_ui()
	if is_instance_valid(platform_bridge) and platform_bridge.supports_local_enter_events():
		_native_enter_events_enabled = true
		platform_bridge.local_enter_pressed.connect(_on_native_enter_pressed)
		_text_edit.focus_entered.connect(_set_native_enter_monitor_enabled.bind(true))
		_text_edit.focus_exited.connect(_set_native_enter_monitor_enabled.bind(false))
	set_process(true)
	set_process_input(true)


func set_session(room: Dictionary, profile: Dictionary) -> void:
	_emit_typing_stop()
	_clear_draft()
	if is_instance_valid(_history_panel):
		_history_panel.visible = false
		history_visibility_changed.emit(false)
	_active_room_id = str(room.get("id", ""))
	_self_user_id = str(profile.get("user_id", ""))
	_input_panel.visible = not _active_room_id.is_empty()
	input_visibility_changed.emit(_input_panel.visible)
	_rebuild_history()


func set_quiet_mode(enabled: bool) -> void:
	_quiet_mode = enabled


func quiet_mode() -> bool:
	return _quiet_mode


func open_composer() -> void:
	if _active_room_id.is_empty():
		return
	_input_panel.visible = true
	input_visibility_changed.emit(true)
	_text_edit.grab_focus()


func cancel_composer() -> void:
	_clear_draft()
	_emit_typing_stop()
	if is_instance_valid(_input_panel):
		_input_panel.visible = not _active_room_id.is_empty()
	input_visibility_changed.emit(is_instance_valid(_input_panel) and _input_panel.visible)


func set_anchor_x(anchor_x: float, identity_rect := Rect2()) -> void:
	_anchor_x = clampf(anchor_x, 0.0, LOGICAL_WIDTH)
	if identity_rect.size.y > 0.0:
		_identity_baseline_y = identity_rect.end.y
	if is_instance_valid(_input_panel):
		_input_panel.position = Vector2(_composer_left(), _composer_top())
	if is_instance_valid(_history_panel):
		_history_panel.position = Vector2(_history_left(), _history_top())


func composer_visible() -> bool:
	return is_instance_valid(_input_panel) and _input_panel.visible


func composer_rect() -> Rect2:
	if not is_instance_valid(_input_panel):
		return Rect2()
	return Rect2(_input_panel.position, _input_panel.size * _input_panel.scale)


func history_rect() -> Rect2:
	if not history_visible():
		return Rect2()
	return Rect2(_history_panel.position, _history_panel.size * _history_panel.scale)


func toggle_history() -> void:
	if not _history_access_enabled or not is_instance_valid(_history_panel) or _active_room_id.is_empty():
		return
	_history_panel.visible = not _history_panel.visible
	if _history_panel.visible:
		_rebuild_history()
	history_visibility_changed.emit(_history_panel.visible)


func history_visible() -> bool:
	return is_instance_valid(_history_panel) and _history_panel.visible


func close_history() -> void:
	if not history_visible():
		return
	_history_panel.visible = false
	history_visibility_changed.emit(false)


func set_history_access_enabled(enabled: bool) -> void:
	_history_access_enabled = enabled
	if not enabled:
		close_history()


func receive_message(message: Dictionary) -> Error:
	var room_id := str(message.get("room_id", ""))
	if not _room_controller.has_room(room_id):
		return ERR_DOES_NOT_EXIST
	var insert_error := _chat_store.insert(message)
	if insert_error != OK:
		return insert_error
	var is_active := room_id == _active_room_id
	if not is_active:
		var unread_error := _room_controller.mark_message_received(room_id)
		if unread_error != OK:
			return unread_error
	else:
		_rebuild_history()
	message_accepted.emit(message.duplicate(true), is_active)
	return OK


func restore_message(message: Dictionary) -> Error:
	var room_id := str(message.get("room_id", ""))
	if not _room_controller.has_room(room_id):
		return ERR_DOES_NOT_EXIST
	var insert_error := _chat_store.insert(message)
	if insert_error != OK:
		return insert_error
	if room_id == _active_room_id:
		_rebuild_history()
	return OK


func recent_messages(room_id: String) -> Array[Dictionary]:
	return _chat_store.recent(room_id)


func _build_ui() -> void:
	_input_panel = PanelContainer.new()
	_input_panel.name = "InlineComposer"
	_input_panel.position = Vector2(_composer_left(), _composer_top())
	_input_panel.custom_minimum_size = COMPOSER_SIZE
	_input_panel.size = COMPOSER_SIZE
	_input_panel.scale = Vector2.ONE * FIXED_UI_FACTOR
	_input_panel.visible = false
	_input_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	input_visibility_changed.emit(false)
	_canvas.add_child(_input_panel)
	_input_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_text_edit = TextEdit.new()
	_text_edit.name = "MessageInput"
	_text_edit.custom_minimum_size = COMPOSER_SIZE
	_text_edit.placeholder_text = "메시지…"
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.scroll_smooth = true
	_text_edit.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_text_edit.add_theme_font_size_override("font_size", 16)
	_text_edit.add_theme_color_override("font_color", OverlayThemeScript.TEXT_PRIMARY)
	_text_edit.add_theme_color_override("font_placeholder_color", OverlayThemeScript.TEXT_SECONDARY)
	_text_edit.add_theme_color_override("caret_color", Color.WHITE)
	_text_edit.add_theme_color_override("selection_color", Color(1.0, 1.0, 1.0, 0.18))
	_text_edit.add_theme_stylebox_override("normal", OverlayThemeScript.composer_style())
	_text_edit.add_theme_stylebox_override("focus", OverlayThemeScript.composer_style(true))
	_text_edit.add_theme_stylebox_override("read_only", OverlayThemeScript.composer_style())
	_text_edit.text_changed.connect(_on_text_changed)
	_text_edit.gui_input.connect(_on_text_gui_input)
	_text_edit.mouse_entered.connect(func() -> void: composer_hover_changed.emit(true))
	_text_edit.mouse_exited.connect(func() -> void: composer_hover_changed.emit(false))
	_input_panel.add_child(_text_edit)

	_history_panel = PanelContainer.new()
	_history_panel.name = "HistoryPanel"
	_history_panel.position = Vector2(_history_left(), _history_top())
	_history_panel.custom_minimum_size = HISTORY_SIZE
	_history_panel.size = HISTORY_SIZE
	_history_panel.scale = Vector2.ONE * FIXED_UI_FACTOR
	_history_panel.visible = false
	_history_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_history_panel.add_theme_stylebox_override("panel", OverlayThemeScript.history_style())
	_canvas.add_child(_history_panel)
	var history_content := VBoxContainer.new()
	history_content.add_theme_constant_override("separation", 10)
	_history_panel.add_child(history_content)
	var history_title := Label.new()
	history_title.text = "최근 메시지"
	history_title.add_theme_font_size_override("font_size", 17)
	history_title.add_theme_color_override("font_color", OverlayThemeScript.TEXT_PRIMARY)
	history_content.add_child(history_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_content.add_child(scroll)
	_history_list = VBoxContainer.new()
	_history_list.custom_minimum_size = Vector2(280.0, 0.0)
	_history_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_history_list)


func _process(_delta: float) -> void:
	if _active_room_id.is_empty() or _self_user_id.is_empty():
		return
	var event := _typing_tracker.poll(_now_seconds())
	if not event.is_empty():
		typing_event.emit(event, _active_room_id, _self_user_id)


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_text_edit) or not _text_edit.has_focus():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if not is_enter_key(key_event):
		return
	if _native_enter_events_enabled:
		get_viewport().set_input_as_handled()
		return
	if key_event.shift_pressed:
		if _text_edit.has_ime_text():
			_text_edit.apply_ime()
		_text_edit.insert_text_at_caret("\n")
	else:
		_submit_from_enter()
	get_viewport().set_input_as_handled()


func _on_text_changed() -> void:
	if _restoring_draft:
		return
	var body := _text_edit.text
	if ChatStore.validate_draft(body) != OK:
		_restore_last_valid_draft()
		return
	_last_valid_draft = body
	if body.strip_edges().is_empty():
		_emit_typing_stop()
		return
	var event := _typing_tracker.note_input(_now_seconds())
	if not event.is_empty():
		typing_event.emit(event, _active_room_id, _self_user_id)


func _on_text_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_enter_key(event):
			if event.shift_pressed:
				if _text_edit.has_ime_text():
					_text_edit.apply_ime()
				_text_edit.insert_text_at_caret("\n")
			else:
				_submit_from_enter()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_text_edit.release_focus()
			_emit_typing_stop()
			get_viewport().set_input_as_handled()


func _send_current_message() -> void:
	if _send_in_progress:
		return
	var body := _text_edit.text.strip_edges()
	if ChatStore.validate_body(body) != OK:
		return
	if is_instance_valid(_backend_runtime):
		var optimistic_message := {
			"id": _uuid_v4(),
			"room_id": _active_room_id,
			"sender_id": _self_user_id,
			"body": body,
			"created_at": Time.get_unix_time_from_system(),
			"delivery_state": "pending",
		}
		var optimistic_error := _chat_store.insert(optimistic_message)
		if optimistic_error != OK:
			push_warning("OPTIMISTIC_MESSAGE_INSERT_FAILED error=%d" % optimistic_error)
			return
		_send_in_progress = true
		_text_edit.editable = false
		_emit_typing_stop()
		_clear_draft()
		_rebuild_history()
		message_accepted.emit(optimistic_message.duplicate(true), true)
		_send_remote_message.call_deferred(optimistic_message)
		return
	var message := {
		"id": "local-message-%d-%d" % [Time.get_ticks_usec(), randi()],
		"room_id": _active_room_id,
		"sender_id": _self_user_id,
		"body": body,
		"created_at": Time.get_unix_time_from_system(),
	}
	var insert_error := _chat_store.insert(message)
	if insert_error != OK:
		push_warning("LOCAL_MESSAGE_INSERT_FAILED error=%d" % insert_error)
		return
	_emit_typing_stop()
	_clear_draft()
	_rebuild_history()
	message_accepted.emit(message, true)


func _send_remote_message(optimistic_message: Dictionary) -> void:
	var message_id := str(optimistic_message.get("id", ""))
	var room_id := str(optimistic_message.get("room_id", ""))
	var body := str(optimistic_message.get("body", ""))
	var result: Dictionary = await _backend_runtime.send_message(
		message_id,
		room_id,
		body,
	)
	_send_in_progress = false
	_text_edit.editable = true
	if not bool(result.get("ok", false)):
		var remove_error := _chat_store.remove(message_id)
		if remove_error not in [OK, ERR_DOES_NOT_EXIST]:
			push_warning("OPTIMISTIC_MESSAGE_ROLLBACK_FAILED error=%d" % remove_error)
		if room_id == _active_room_id:
			_restore_failed_message_draft(body)
			_rebuild_history()
		message_rejected.emit(optimistic_message.duplicate(true), str(result.get("error_code", "unknown")))
		push_warning("REMOTE_MESSAGE_SEND_FAILED code=%s message=%s" % [
			str(result.get("error_code", "unknown")),
			str(result.get("error_message", "")),
		])
		return
	var message := _first_record(result.get("data"))
	if message.is_empty():
		message = optimistic_message.duplicate(true)
	message.erase("delivery_state")
	var replace_error := _chat_store.replace(message)
	if replace_error != OK:
		push_warning("REMOTE_MESSAGE_RECONCILE_FAILED error=%d" % replace_error)
	if room_id == _active_room_id:
		_rebuild_history()


func _restore_failed_message_draft(body: String) -> void:
	_last_valid_draft = body
	_restoring_draft = true
	_text_edit.text = body
	var last_line := maxi(0, _text_edit.get_line_count() - 1)
	_text_edit.set_caret_line(last_line)
	_text_edit.set_caret_column(_text_edit.get_line(last_line).length())
	_restoring_draft = false


func _emit_typing_stop() -> void:
	if _typing_tracker != null and _typing_tracker.stop() and not _active_room_id.is_empty():
		typing_event.emit(&"typing_stop", _active_room_id, _self_user_id)


func _rebuild_history() -> void:
	if not is_instance_valid(_history_list):
		return
	for child in _history_list.get_children():
		child.queue_free()
	for message in _chat_store.recent(_active_room_id):
		var message_block := VBoxContainer.new()
		message_block.add_theme_constant_override("separation", 2)
		var sender := Label.new()
		sender.text = _sender_name(str(message.get("sender_id", "")))
		sender.add_theme_font_size_override("font_size", 14)
		sender.add_theme_color_override("font_color", OverlayThemeScript.TEXT_SECONDARY)
		message_block.add_child(sender)
		var body := Label.new()
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = str(message.get("body", ""))
		body.add_theme_font_size_override("font_size", 16)
		body.add_theme_color_override("font_color", OverlayThemeScript.TEXT_PRIMARY)
		message_block.add_child(body)
		_history_list.add_child(message_block)


func _sender_name(user_id: String) -> String:
	var room := _room_controller.room_by_id(_active_room_id)
	for member in room.get("members", []) as Array:
		if str((member as Dictionary).get("user_id", "")) == user_id:
			return str((member as Dictionary).get("nickname", "친구"))
	return "친구"


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


func _composer_left() -> float:
	var rendered_width := COMPOSER_SIZE.x * FIXED_UI_FACTOR
	return clampf(
		_anchor_x - rendered_width * 0.5,
		EDGE_MARGIN,
		LOGICAL_WIDTH - EDGE_MARGIN - rendered_width,
	)


func _composer_top() -> float:
	return _identity_baseline_y + COMPOSER_GAP


func _history_left() -> float:
	var rendered_width := HISTORY_SIZE.x * FIXED_UI_FACTOR
	return clampf(
		_anchor_x - rendered_width * 0.5,
		EDGE_MARGIN,
		LOGICAL_WIDTH - EDGE_MARGIN - rendered_width,
	)


func _history_top() -> float:
	return _composer_top() - HISTORY_GAP - HISTORY_SIZE.y * FIXED_UI_FACTOR


func _clear_draft() -> void:
	_last_valid_draft = ""
	if not is_instance_valid(_text_edit):
		return
	_restoring_draft = true
	_text_edit.text = ""
	_restoring_draft = false


func _restore_last_valid_draft() -> void:
	_restoring_draft = true
	_text_edit.text = _last_valid_draft
	var last_line := maxi(0, _text_edit.get_line_count() - 1)
	_text_edit.set_caret_line(last_line)
	_text_edit.set_caret_column(_text_edit.get_line(last_line).length())
	_restoring_draft = false


func _queue_submit() -> void:
	if _submit_queued or _send_in_progress:
		return
	_submit_queued = true
	_submit_wait_frames = 0
	_flush_queued_submit.call_deferred()


func _flush_queued_submit() -> void:
	if not is_instance_valid(_text_edit):
		_submit_queued = false
		return
	if _text_edit.has_ime_text():
		if _submit_wait_frames >= IME_SUBMIT_MAX_WAIT_FRAMES:
			_submit_queued = false
			return
		_submit_wait_frames += 1
		_text_edit.apply_ime()
		get_tree().process_frame.connect(_flush_queued_submit, CONNECT_ONE_SHOT)
		return
	_submit_queued = false
	_send_current_message()


func _submit_from_enter() -> void:
	if _submit_queued or _send_in_progress:
		return
	if _text_edit.has_ime_text():
		_text_edit.apply_ime()
		_queue_submit()
		return
	_send_current_message()


func _on_native_enter_pressed(shift_pressed: bool) -> void:
	if not is_instance_valid(_text_edit) or not _text_edit.has_focus():
		return
	if _native_enter_action != NATIVE_ENTER_NONE:
		return
	_native_enter_action = NATIVE_ENTER_NEWLINE if shift_pressed else NATIVE_ENTER_SUBMIT
	_native_enter_wait_frames = 0
	get_tree().process_frame.connect(_flush_native_enter, CONNECT_ONE_SHOT)


func _flush_native_enter() -> void:
	if _native_enter_action == NATIVE_ENTER_NONE or not is_instance_valid(_text_edit):
		return
	if _text_edit.has_ime_text():
		if _native_enter_wait_frames >= IME_SUBMIT_MAX_WAIT_FRAMES:
			_native_enter_action = NATIVE_ENTER_NONE
			push_warning("NATIVE_IME_ENTER_TIMEOUT")
			return
		_native_enter_wait_frames += 1
		_text_edit.apply_ime()
		get_tree().process_frame.connect(_flush_native_enter, CONNECT_ONE_SHOT)
		return
	var action := _native_enter_action
	_native_enter_action = NATIVE_ENTER_NONE
	if action == NATIVE_ENTER_NEWLINE:
		_text_edit.insert_text_at_caret("\n")
	else:
		_send_current_message()


func _set_native_enter_monitor_enabled(enabled: bool) -> void:
	if is_instance_valid(_platform_bridge):
		_platform_bridge.set_local_enter_monitor_enabled(enabled)


func _exit_tree() -> void:
	_set_native_enter_monitor_enabled(false)


static func is_enter_key(event: InputEventKey) -> bool:
	return event.keycode in [KEY_ENTER, KEY_KP_ENTER]


static func should_submit_key(event: InputEventKey, _ime_active: bool) -> bool:
	return is_enter_key(event) and not event.shift_pressed


static func _first_record(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array and not (value as Array).is_empty() and (value as Array)[0] is Dictionary:
		return ((value as Array)[0] as Dictionary).duplicate(true)
	return {}


static func _uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8),
		hex.substr(8, 4),
		hex.substr(12, 4),
		hex.substr(16, 4),
		hex.substr(20, 12),
	]
