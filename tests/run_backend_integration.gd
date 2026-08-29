extends SceneTree

const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const BackendClientScript := preload("res://scripts/backend/backend_client.gd")
const BackendRepositoryScript := preload("res://scripts/backend/backend_repository.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := BackendConfigScript.from_environment()
	if not config.is_valid():
		push_error("BACKEND_INTEGRATION_CONFIG_MISSING")
		quit(2)
		return
	var backend := BackendClientScript.new() as BackendClient
	root.add_child(backend)
	_check(backend.configure(config, null, "integration-%d" % OS.get_process_id()) == OK, "backend configured")
	var auth: Dictionary = await backend.create_anonymous_session()
	_check(bool(auth.get("ok", false)), "anonymous auth succeeds")
	if not bool(auth.get("ok", false)):
		push_error("BACKEND_AUTH_ERROR status=%d code=%s message=%s" % [
			int(auth.get("status", 0)),
			str(auth.get("error_code", "unknown")),
			str(auth.get("error_message", "")),
		])
		backend.queue_free()
		_finish.call_deferred()
		return
	_check(not backend.user_id().is_empty(), "anonymous user has id")
	var first_refresh_token := str(backend.session().get("refresh_token", ""))
	var refresh: Dictionary = await backend.refresh_session()
	_check(bool(refresh.get("ok", false)), "session refresh succeeds")
	_check(not str(backend.session().get("refresh_token", "")).is_empty(), "refresh rotates or retains token")
	_check(not first_refresh_token.is_empty(), "initial refresh token exists")
	var profile: Dictionary = await backend.upsert_profile("통합테스트", "minty_pup")
	_check(bool(profile.get("ok", false)), "profile RPC succeeds")
	var created: Dictionary = await backend.create_room("통합 테스트")
	_check(bool(created.get("ok", false)), "room RPC succeeds")
	var created_rows: Array = created.get("data", []) as Array if created.get("data") is Array else []
	var room_id := ""
	if not created_rows.is_empty():
		room_id = str((created_rows[0] as Dictionary).get("room_id", ""))
	_check(not room_id.is_empty(), "created room has id")
	_check(not backend.read_invite_code(room_id).is_empty(), "invite plaintext retained only by client store")
	var message_id := _uuid_v4()
	var sent: Dictionary = await backend.send_message(message_id, room_id, "로컬 Supabase 연결 확인")
	_check(bool(sent.get("ok", false)), "message RPC succeeds")
	var messages: Dictionary = await backend.recent_messages(room_id)
	_check(bool(messages.get("ok", false)), "messages query succeeds")
	_check(_contains_message(messages.get("data", []) as Array, message_id), "stored message is queryable")
	var snapshot: Dictionary = await BackendRepositoryScript.new().load_snapshot(backend)
	_check(bool(snapshot.get("ok", false)), "room snapshot query succeeds")
	_check((snapshot.get("rooms", []) as Array).size() == 1, "room snapshot contains joined room")
	_check(str((snapshot.get("profile", {}) as Dictionary).get("nickname", "")) == "통합테스트", "room snapshot contains profile")
	var leave: Dictionary = await backend.call_rpc("leave_room", {"p_room_id": room_id})
	_check(bool(leave.get("ok", false)), "integration room is removed")
	backend.queue_free()
	_finish.call_deferred()


func _contains_message(messages: Array, message_id: String) -> bool:
	for message in messages:
		if message is Dictionary and str((message as Dictionary).get("id", "")) == message_id:
			return true
	return false


func _uuid_v4() -> String:
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


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BACKEND_INTEGRATION_FAILED %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("SIDEY_BACKEND_INTEGRATION_OK")
		quit(0)
	else:
		push_error("SIDEY_BACKEND_INTEGRATION_FAILED failures=%d" % _failures)
		quit(1)
