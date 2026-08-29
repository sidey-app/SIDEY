class_name ChatController
extends Node

signal message_accepted(message: Dictionary, active_room: bool)
signal typing_event(action: StringName, room_id: String, user_id: String)
signal input_visibility_changed(visible: bool)

const ChatStoreScript := preload("res://scripts/chat/chat_store.gd")
const TypingTrackerScript := preload("res://scripts/chat/typing_tracker.gd")

var _room_controller: RoomController
var _chat_store: ChatStore
var _typing_tracker: TypingTracker
var _canvas: CanvasLayer
var _input_panel: PanelContainer
var _text_edit: TextEdit
var _send_button: Button
var _counter_label: Label
var _history_panel: PanelContainer
var _history_list: VBoxContainer
var _history_button: Button
var _active_room_id := ""
var _self_user_id := ""
var _quiet_mode := false
var _backend_runtime: BackendRuntime
var _send_in_progress := false


func configure(
	room_controller: RoomController,
	canvas: CanvasLayer,
	backend_runtime: BackendRuntime = null,
) -> void:
	_room_controller = room_controller
	_canvas = canvas
	_backend_runtime = backend_runtime
	_chat_store = ChatStoreScript.new()
	_typing_tracker = TypingTrackerScript.new()
	_build_ui()
	set_process(true)


func set_session(room: Dictionary, profile: Dictionary) -> void:
	cancel_composer()
	_active_room_id = str(room.get("id", ""))
	_self_user_id = str(profile.get("user_id", ""))
	_rebuild_history()


func set_quiet_mode(enabled: bool) -> void:
	_quiet_mode = enabled


func quiet_mode() -> bool:
	return _quiet_mode


func open_composer() -> void:
	if _active_room_id.is_empty():
		return
	_input_panel.visible = true
	_text_edit.grab_focus()
	input_visibility_changed.emit(true)


func cancel_composer() -> void:
	if is_instance_valid(_text_edit):
		_text_edit.text = ""
	if is_instance_valid(_input_panel):
		_input_panel.visible = false
	input_visibility_changed.emit(false)
	_emit_typing_stop()


func set_interaction_enabled(enabled: bool) -> void:
	if not enabled:
		cancel_composer()
	if is_instance_valid(_history_button):
		_history_button.visible = enabled
	if not enabled and is_instance_valid(_history_panel):
		_history_panel.visible = false


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
	_input_panel.position = Vector2(170.0, 214.0)
	_input_panel.size = Vector2(380.0, 98.0)
	_input_panel.visible = false
	input_visibility_changed.emit(false)
	_canvas.add_child(_input_panel)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.055, 0.08, 0.10, 0.96)
	input_style.corner_radius_top_left = 12
	input_style.corner_radius_top_right = 12
	input_style.corner_radius_bottom_left = 12
	input_style.corner_radius_bottom_right = 12
	input_style.content_margin_left = 10.0
	input_style.content_margin_right = 10.0
	input_style.content_margin_top = 8.0
	input_style.content_margin_bottom = 8.0
	_input_panel.add_theme_stylebox_override("panel", input_style)
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	_input_panel.add_child(input_row)
	_text_edit = TextEdit.new()
	_text_edit.custom_minimum_size = Vector2(276.0, 78.0)
	_text_edit.placeholder_text = "짧은 메시지 · 최대 200자 / 3줄"
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.text_changed.connect(_on_text_changed)
	_text_edit.gui_input.connect(_on_text_gui_input)
	input_row.add_child(_text_edit)
	var actions := VBoxContainer.new()
	input_row.add_child(actions)
	_send_button = Button.new()
	_send_button.text = "보내기"
	_send_button.disabled = true
	_send_button.pressed.connect(_send_current_message)
	actions.add_child(_send_button)
	_counter_label = Label.new()
	_counter_label.text = "0 / 200"
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", 11)
	actions.add_child(_counter_label)
	var cancel_button := Button.new()
	cancel_button.text = "닫기"
	cancel_button.pressed.connect(cancel_composer)
	actions.add_child(cancel_button)

	_history_button = Button.new()
	_history_button.position = Vector2(640.0, 42.0)
	_history_button.size = Vector2(68.0, 30.0)
	_history_button.text = "기록"
	_history_button.visible = false
	_history_button.pressed.connect(_toggle_history)
	_canvas.add_child(_history_button)
	_history_panel = PanelContainer.new()
	_history_panel.position = Vector2(440.0, 76.0)
	_history_panel.size = Vector2(268.0, 166.0)
	_history_panel.visible = false
	_canvas.add_child(_history_panel)
	var scroll := ScrollContainer.new()
	_history_panel.add_child(scroll)
	_history_list = VBoxContainer.new()
	_history_list.custom_minimum_size = Vector2(244.0, 0.0)
	_history_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_history_list)


func _process(_delta: float) -> void:
	if _active_room_id.is_empty() or _self_user_id.is_empty():
		return
	var event := _typing_tracker.poll(_now_seconds())
	if not event.is_empty():
		typing_event.emit(event, _active_room_id, _self_user_id)


func _on_text_changed() -> void:
	var body := _text_edit.text
	var valid := ChatStore.validate_body(body) == OK
	_send_button.disabled = not valid
	_counter_label.text = "%d / %d" % [body.length(), ChatStore.MAX_BODY_LENGTH]
	_counter_label.add_theme_color_override(
		"font_color",
		Color("dce9ec") if valid or body.is_empty() else Color("ff837a"),
	)
	if body.is_empty():
		_emit_typing_stop()
		return
	var event := _typing_tracker.note_input(_now_seconds())
	if not event.is_empty():
		typing_event.emit(event, _active_room_id, _self_user_id)


func _on_text_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (event.meta_pressed or event.ctrl_pressed):
			_send_current_message()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			cancel_composer()
			get_viewport().set_input_as_handled()


func _send_current_message() -> void:
	if _send_in_progress:
		return
	var body := _text_edit.text.strip_edges()
	if ChatStore.validate_body(body) != OK:
		return
	if is_instance_valid(_backend_runtime):
		_send_remote_message.call_deferred(body)
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
	_text_edit.text = ""
	_input_panel.visible = false
	_rebuild_history()
	message_accepted.emit(message, true)


func _send_remote_message(body: String) -> void:
	_send_in_progress = true
	_send_button.disabled = true
	var message_id := _uuid_v4()
	var result: Dictionary = await _backend_runtime.send_message(
		message_id,
		_active_room_id,
		body,
	)
	_send_in_progress = false
	if not bool(result.get("ok", false)):
		push_warning("REMOTE_MESSAGE_SEND_FAILED code=%s message=%s" % [
			str(result.get("error_code", "unknown")),
			str(result.get("error_message", "")),
		])
		_on_text_changed()
		return
	var message := _first_record(result.get("data"))
	if message.is_empty():
		message = {
			"id": message_id,
			"room_id": _active_room_id,
			"sender_id": _self_user_id,
			"body": body,
			"created_at": Time.get_unix_time_from_system(),
		}
	var insert_error := _chat_store.insert(message)
	if insert_error not in [OK, ERR_ALREADY_EXISTS]:
		push_warning("REMOTE_MESSAGE_CACHE_FAILED error=%d" % insert_error)
		return
	_emit_typing_stop()
	_text_edit.text = ""
	_input_panel.visible = false
	_rebuild_history()
	if insert_error == OK:
		message_accepted.emit(message, true)


func _emit_typing_stop() -> void:
	if _typing_tracker != null and _typing_tracker.stop() and not _active_room_id.is_empty():
		typing_event.emit(&"typing_stop", _active_room_id, _self_user_id)


func _toggle_history() -> void:
	_history_panel.visible = not _history_panel.visible
	if _history_panel.visible:
		_rebuild_history()


func _rebuild_history() -> void:
	if not is_instance_valid(_history_list):
		return
	for child in _history_list.get_children():
		child.queue_free()
	for message in _chat_store.recent(_active_room_id):
		var line := Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.text = "%s  %s" % [_sender_name(str(message.get("sender_id", ""))), str(message.get("body", ""))]
		line.add_theme_font_size_override("font_size", 12)
		_history_list.add_child(line)


func _sender_name(user_id: String) -> String:
	var room := _room_controller.room_by_id(_active_room_id)
	for member in room.get("members", []) as Array:
		if str((member as Dictionary).get("user_id", "")) == user_id:
			return str((member as Dictionary).get("nickname", "친구"))
	return "친구"


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0


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
