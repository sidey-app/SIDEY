extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const ChatControllerScript := preload("res://scripts/chat/chat_controller.gd")

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
		_check(not ChatControllerScript.should_submit_key(enter, true), "Enter does not submit while IME text is active")
		message_input.text = "Enter 전송"
		chat._on_text_changed()
		var message_count := chat.recent_messages(first_room_id).size()
		chat._on_text_gui_input(enter)
		_check(chat.recent_messages(first_room_id).size() == message_count + 1, "Enter sends the current draft")
		_check(message_input.text.is_empty(), "successful send clears only the draft")
		_check(chat.composer_visible(), "successful send keeps the composer visible")
		message_input.text = "첫째 줄\n둘째 줄"
		chat._on_text_changed()
		_check(message_input.text == "첫째 줄\n둘째 줄", "multiline draft accepts Shift+Enter newlines")
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
