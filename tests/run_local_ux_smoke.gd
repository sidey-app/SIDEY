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
	chat.set_session(rooms.active_room(), rooms.profile())
	chat.message_accepted.connect(func(_message: Dictionary, active: bool) -> void: _accepted_active_flags.append(active))
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
