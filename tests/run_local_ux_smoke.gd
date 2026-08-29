extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const ChatControllerScript := preload("res://scripts/chat/chat_controller.gd")


class FakeBackendRuntime:
	extends BackendRuntime

	var next_result: Dictionary = {"ok": true, "data": {}}
	var sends: Array[Dictionary] = []

	func send_message(message_id: String, room_id: String, body: String) -> Dictionary:
		sends.append({"id": message_id, "room_id": room_id, "body": body})
		await get_tree().process_frame
		return next_result.duplicate(true)


var _failures := 0
var _settings_path := ""
var _accepted_active_flags: Array[bool] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings_path = "/tmp/sidey-local-ux-smoke-%d.json" % OS.get_process_id()
	var rooms := RoomControllerScript.new() as RoomController
	root.add_child(rooms)
	_check(rooms.configure(SettingsStoreScript.new(_settings_path)) == OK, "room controller configured")
	_check(rooms.set_profile("민트") == OK, "local profile created")
	_check(rooms.create_room("첫 그룹") == OK, "first room created")
	var first_room_id := rooms.active_room_id()
	_check(rooms.join_demo_room(RoomController.DEMO_INVITE_CODE) == OK, "demo room joined")
	_check(rooms.set_active_room(first_room_id) == OK, "first room activated")
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var chat := ChatControllerScript.new() as ChatController
	root.add_child(chat)
	chat.configure(rooms, canvas)
	chat.set_anchor_x(78.0)
	chat.set_session(rooms.active_room(), rooms.profile())
	chat.message_accepted.connect(func(_message: Dictionary, active: bool) -> void: _accepted_active_flags.append(active))
	_check(chat.composer_visible(), "inline composer remains visible for an active room")
	_check(is_equal_approx(chat.composer_rect().position.x, 8.0), "inline composer follows the clamped self anchor")
	_check(chat.composer_rect().size.is_equal_approx(Vector2(179.2, 33.6)), "composer stays at the fixed 160 percent size")
	var message_input := canvas.find_child("MessageInput", true, false) as TextEdit
	_check(message_input != null, "inline composer has a text input")
	if message_input != null:
		_check(message_input.placeholder_text == "메시지…", "inline composer has the compact placeholder")
		_check((canvas.find_child("InlineComposer", true, false) as Control).find_children("*", "Button", true, false).is_empty(), "inline composer has no text buttons")
		var composer_style := message_input.get_theme_stylebox("normal") as StyleBoxFlat
		_check(composer_style != null and composer_style.bg_color.a >= 0.7 and composer_style.bg_color.r < 0.1, "inline composer uses a dark translucent style")
	var inactive_message := _message("inactive-1", "demo-friends", "demo-user-1", "비활성 그룹 메시지")
	_check(chat.receive_message(inactive_message) == OK, "inactive message accepted")
	_check(rooms.unread_count("demo-friends") == 1, "inactive message increments unread")
	_check(chat.receive_message(inactive_message) == ERR_ALREADY_EXISTS, "retransmit UUID deduplicated")
	_check(rooms.unread_count("demo-friends") == 1, "dedupe does not increment unread")
	var replay_message := _message("replay-1", "demo-friends", "demo-user-2", "재연결 기록")
	_check(chat.restore_message(replay_message) == OK, "reconnect history restored")
	_check(rooms.unread_count("demo-friends") == 1, "reconnect history does not increment unread")
	var active_message := _message("active-1", first_room_id, str(rooms.profile()["user_id"]), "활성 그룹 메시지")
	_check(chat.receive_message(active_message) == OK, "active message accepted")
	_check(chat.recent_messages(first_room_id).size() == 1, "active history rendered from store")
	_check(_accepted_active_flags == [false, true], "active flag distinguishes bubble behavior")
	chat.toggle_history()
	_check(not chat.history_visible(), "history cannot open while overlay editing is locked")
	chat.set_history_access_enabled(true)
	chat.toggle_history()
	_check(chat.history_visible(), "history opens after overlay editing is unlocked")
	var history_panel := canvas.find_child("HistoryPanel", true, false) as PanelContainer
	var history_style := history_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_check(history_style != null and history_style.bg_color.r < 0.1 and history_style.bg_color.a >= 0.8, "history uses a dark translucent panel")
	chat.set_history_access_enabled(false)
	_check(not chat.history_visible(), "locking closes the history panel")
	if message_input != null:
		var enter := _key_event(KEY_ENTER)
		var shift_enter := _key_event(KEY_ENTER, true)
		_check(ChatControllerScript.should_submit_key(enter, false), "Enter submits a draft")
		_check(not ChatControllerScript.should_submit_key(shift_enter, false), "Shift+Enter remains a newline")
		_check(ChatControllerScript.should_submit_key(enter, true), "Enter submits after applying active IME text")
		message_input.text = "Enter 전송"
		chat._on_text_changed()
		message_input.grab_focus()
		await process_frame
		var message_count := chat.recent_messages(first_room_id).size()
		chat._input(enter)
		_check(chat.recent_messages(first_room_id).size() == message_count + 1, "pre-GUI Enter sends the current draft on its first press")
		_check(message_input.text.is_empty(), "successful send clears only the draft")
		_check(chat.composer_visible(), "successful send keeps the composer visible")
		message_input.text = "첫째 줄"
		chat._on_text_changed()
		message_input.set_caret_line(0)
		message_input.set_caret_column(message_input.text.length())
		chat._input(shift_enter)
		message_input.insert_text_at_caret("둘째 줄")
		_check(message_input.text == "첫째 줄\n둘째 줄", "multiline draft accepts Shift+Enter newlines")
		message_input.text = "한글 조합 확정"
		chat._on_text_changed()
		message_count = chat.recent_messages(first_room_id).size()
		chat._on_native_enter_pressed(false)
		await process_frame
		await process_frame
		_check(chat.recent_messages(first_room_id).size() == message_count + 1, "native IME Enter submits after committed text is applied")
		_check(message_input.text.is_empty(), "native IME Enter clears the submitted draft")
		var valid_length_draft := "가".repeat(ChatStore.MAX_BODY_LENGTH)
		message_input.text = valid_length_draft
		chat._on_text_changed()
		message_input.text += "나"
		chat._on_text_changed()
		_check(message_input.text == valid_length_draft, "draft restores after exceeding 200 characters")
		message_input.text = "1\n2\n3"
		chat._on_text_changed()
		message_input.text += "\n4"
		chat._on_text_changed()
		_check(message_input.text == "1\n2\n3", "draft restores after exceeding three lines")
		message_input.text = "   "
		chat._on_text_changed()
		message_count = chat.recent_messages(first_room_id).size()
		chat._on_text_gui_input(enter)
		_check(chat.recent_messages(first_room_id).size() == message_count, "blank message is rejected")
		var fake_backend := FakeBackendRuntime.new()
		root.add_child(fake_backend)
		chat._backend_runtime = fake_backend
		var optimistic_messages: Array[Dictionary] = []
		var rejected_messages: Array[Dictionary] = []
		chat.message_accepted.connect(func(message: Dictionary, _active: bool) -> void:
			if str(message.get("delivery_state", "")) == "pending":
				optimistic_messages.append(message)
		)
		chat.message_rejected.connect(func(message: Dictionary, _error_code: String) -> void:
			rejected_messages.append(message)
		)
		message_input.text = "바로 보이는 말풍선"
		chat._on_text_changed()
		message_count = chat.recent_messages(first_room_id).size()
		chat._send_current_message()
		_check(chat.recent_messages(first_room_id).size() == message_count + 1, "remote send inserts optimistic history immediately")
		_check(optimistic_messages.size() == 1, "remote send emits an immediate optimistic bubble")
		_check(message_input.text.is_empty(), "optimistic send clears the draft before server response")
		await _wait_until(func() -> bool: return not chat._send_in_progress)
		_check(fake_backend.sends.size() == 1, "optimistic message is persisted to the backend")
		_check(chat.recent_messages(first_room_id).size() == message_count + 1, "server success does not duplicate the optimistic message")
		_check(not chat.recent_messages(first_room_id)[-1].has("delivery_state"), "server success reconciles pending delivery state")
		fake_backend.next_result = {
			"ok": false,
			"error_code": "transport_error",
			"error_message": "offline",
		}
		message_input.text = "실패하면 복구"
		chat._on_text_changed()
		message_count = chat.recent_messages(first_room_id).size()
		chat._send_current_message()
		_check(chat.recent_messages(first_room_id).size() == message_count + 1, "failed remote send is optimistic before the response")
		await _wait_until(func() -> bool: return not chat._send_in_progress)
		_check(chat.recent_messages(first_room_id).size() == message_count, "failed remote send rolls back optimistic history")
		_check(message_input.text == "실패하면 복구", "failed remote send restores the original draft")
		_check(rejected_messages.size() == 1, "failed remote send emits user feedback")
		fake_backend.queue_free()
	chat.queue_free()
	canvas.queue_free()
	rooms.queue_free()
	_finish.call_deferred()


func _message(id: String, room_id: String, sender_id: String, body: String) -> Dictionary:
	return {
		"id": id,
		"room_id": room_id,
		"sender_id": sender_id,
		"body": body,
		"created_at": Time.get_unix_time_from_system(),
	}


func _key_event(keycode: Key, shift_pressed := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.shift_pressed = shift_pressed
	return event


func _wait_until(predicate: Callable, timeout_seconds := 2.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("LOCAL_UX_TEST_FAILED %s" % label)


func _finish() -> void:
	DirAccess.remove_absolute(_settings_path)
	if _failures == 0:
		print("SIDEY_LOCAL_UX_SMOKE_OK")
		quit(0)
	else:
		push_error("SIDEY_LOCAL_UX_SMOKE_FAILED failures=%d" % _failures)
		quit(1)
