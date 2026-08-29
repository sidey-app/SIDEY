extends SceneTree

const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const BackendRuntimeScript := preload("res://scripts/backend/backend_runtime.gd")
const ChatControllerScript := preload("res://scripts/chat/chat_controller.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")

var _failures := 0
var _settings_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := BackendConfigScript.from_environment()
	if not config.is_valid():
		push_error("BACKEND_RUNTIME_CONFIG_MISSING")
		quit(2)
		return
	_settings_path = "/tmp/sidey-backend-runtime-%d.json" % OS.get_process_id()
	var rooms := RoomControllerScript.new() as RoomController
	root.add_child(rooms)
	_check(rooms.configure(SettingsStoreScript.new(_settings_path)) == OK, "local cache configured")
	var runtime := BackendRuntimeScript.new() as BackendRuntime
	root.add_child(runtime)
	_check(runtime.configure(config, null, rooms, "runtime-%d" % OS.get_process_id()) == OK, "backend runtime configured")
	var boot: Dictionary = await runtime.start()
	_check(bool(boot.get("ok", false)), "backend runtime booted")
	_check(bool(boot.get("onboarding_required", false)), "new anonymous user requires onboarding")
	var onboarded: Dictionary = await runtime.onboard_create("런타임테스트", "minty_pup", "첫 런타임 방")
	_check(bool(onboarded.get("ok", false)), "remote onboarding created profile and room")
	_check(rooms.is_onboarding_complete(), "remote snapshot completes onboarding")
	_check(rooms.rooms().size() == 1, "remote room is in local display cache")
	var first_room_id := rooms.active_room_id()
	var self_user_id := str(rooms.profile().get("user_id", ""))
	await _wait_until(func() -> bool: return _member_presence(rooms.room_by_id(first_room_id), self_user_id) == "online")
	_check(_member_presence(rooms.room_by_id(first_room_id), self_user_id) == "online", "active room receives own online Presence")
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var chat := ChatControllerScript.new() as ChatController
	root.add_child(chat)
	chat.configure(rooms, canvas, runtime)
	chat.set_session(rooms.active_room(), rooms.profile())
	var optimistic_messages: Array[Dictionary] = []
	chat.message_accepted.connect(func(message: Dictionary, active: bool) -> void:
		if active and str(message.get("delivery_state", "")) == "pending":
			optimistic_messages.append(message)
	)
	var message_input := canvas.find_child("MessageInput", true, false) as TextEdit
	message_input.text = "낙관적 전송 통합 확인"
	chat._on_text_changed()
	chat._send_current_message()
	_check(optimistic_messages.size() == 1, "remote chat emits optimistic message before awaiting Supabase")
	_check(chat.recent_messages(first_room_id).size() == 1, "optimistic message enters local history immediately")
	_check(message_input.text.is_empty(), "optimistic message clears composer immediately")
	await _wait_until(func() -> bool: return not chat._send_in_progress)
	_check(not chat.recent_messages(first_room_id)[0].has("delivery_state"), "Supabase response reconciles optimistic message")
	var stored_messages: Dictionary = await runtime.backend_client().recent_messages(first_room_id)
	_check(
		_contains_message(
			stored_messages.get("data", []) as Array,
			str(optimistic_messages[0].get("id", "")),
		),
		"optimistic UUID is the Postgres message id",
	)
	var original_invite_code := runtime.read_invite_code(first_room_id)
	_check(not original_invite_code.is_empty(), "owner invite code is available from secure client store")
	var rotated: Dictionary = await runtime.rotate_invite_code(first_room_id)
	_check(bool(rotated.get("ok", false)), "owner invite code rotates")
	_check(runtime.read_invite_code(first_room_id) != original_invite_code, "rotated invite code replaces plaintext client copy")
	var renamed: Dictionary = await runtime.rename_room(first_room_id, "이름 바뀐 방")
	_check(bool(renamed.get("ok", false)), "remote room renamed")
	_check(str(rooms.room_by_id(first_room_id).get("name", "")) == "이름 바뀐 방", "renamed room resynchronized")
	var second_room: Dictionary = await runtime.create_room("두 번째 방")
	_check(bool(second_room.get("ok", false)), "second remote room created")
	_check(rooms.rooms().size() == 2, "two remote rooms are cached")
	var second_room_id := ""
	for room in rooms.rooms():
		var candidate_room_id := str(room.get("id", ""))
		if candidate_room_id != first_room_id:
			second_room_id = candidate_room_id
	_check(not second_room_id.is_empty(), "second room id resolved")
	_check(_member_presence(rooms.room_by_id(first_room_id), self_user_id) == "online", "snapshot refresh preserves active-room Presence")
	_check(_member_presence(rooms.room_by_id(second_room_id), self_user_id) == "offline", "new inactive room starts offline")
	_check(rooms.set_active_room(second_room_id) == OK, "second room activated")
	_check(_member_presence(rooms.room_by_id(first_room_id), self_user_id) == "offline", "previous room becomes offline immediately")
	_check(_member_presence(rooms.room_by_id(second_room_id), self_user_id) == "online", "new active room becomes online immediately")
	_check(rooms.set_active_room(first_room_id) == OK, "first room reactivated")
	_check(_member_presence(rooms.room_by_id(first_room_id), self_user_id) == "online", "reactivated room becomes online immediately")
	_check(_member_presence(rooms.room_by_id(second_room_id), self_user_id) == "offline", "inactive second room becomes offline immediately")
	var room_ids: Array[String] = []
	for room in rooms.rooms():
		room_ids.append(str(room.get("id", "")))
	for room_id in room_ids:
		var left: Dictionary = await runtime.leave_room(room_id)
		_check(bool(left.get("ok", false)), "integration room removed")
	_check(rooms.rooms().is_empty(), "removed rooms disappear from cache")
	chat.queue_free()
	canvas.queue_free()
	runtime.queue_free()
	rooms.queue_free()
	_finish.call_deferred()


func _wait_until(predicate: Callable, timeout_seconds := 8.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout


func _member_presence(room: Dictionary, user_id: String) -> String:
	for member in room.get("members", []) as Array:
		if str((member as Dictionary).get("user_id", "")) == user_id:
			return str((member as Dictionary).get("presence", "offline"))
	return "offline"


func _contains_message(messages: Array, message_id: String) -> bool:
	for message in messages:
		if message is Dictionary and str((message as Dictionary).get("id", "")) == message_id:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BACKEND_RUNTIME_INTEGRATION_FAILED %s" % label)


func _finish() -> void:
	DirAccess.remove_absolute(_settings_path)
	if _failures == 0:
		print("SIDEY_BACKEND_RUNTIME_INTEGRATION_OK")
		quit(0)
	else:
		push_error("SIDEY_BACKEND_RUNTIME_INTEGRATION_FAILED failures=%d" % _failures)
		quit(1)
