extends SceneTree

const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const BackendClientScript := preload("res://scripts/backend/backend_client.gd")
const RealtimeClientScript := preload("res://scripts/backend/realtime_client.gd")

const WAIT_TIMEOUT_SECONDS := 8.0

var _failures := 0
var _joined := false
var _typing_received := false
var _presence_received := false
var _database_message_received := false
var _expected_message_id := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := BackendConfigScript.from_environment()
	if not config.is_valid():
		push_error("REALTIME_INTEGRATION_CONFIG_MISSING")
		quit(2)
		return
	var backend := BackendClientScript.new() as BackendClient
	root.add_child(backend)
	_check(backend.configure(config, null, "realtime-%d" % OS.get_process_id()) == OK, "backend configured")
	var auth: Dictionary = await backend.create_anonymous_session()
	if not bool(auth.get("ok", false)):
		_fail("anonymous auth", auth)
		return
	var profile: Dictionary = await backend.upsert_profile("실시간테스트", "minty_pup")
	if not bool(profile.get("ok", false)):
		_fail("profile RPC", profile)
		return
	var created: Dictionary = await backend.create_room("실시간 테스트")
	if not bool(created.get("ok", false)):
		_fail("room RPC", created)
		return
	var room_id := str(((created.get("data", []) as Array)[0] as Dictionary).get("room_id", ""))
	var realtime := RealtimeClientScript.new() as RealtimeClient
	root.add_child(realtime)
	_check(realtime.configure(config, backend.access_token(), backend.user_id()) == OK, "Realtime configured")
	realtime.channel_joined.connect(func(joined_room_id: String) -> void: _joined = joined_room_id == room_id)
	realtime.broadcast_received.connect(_on_broadcast.bind(room_id))
	realtime.presence_state_received.connect(func(received_room_id: String, _state: Dictionary) -> void: _presence_received = received_room_id == room_id)
	realtime.presence_diff_received.connect(func(received_room_id: String, _joins: Dictionary, _leaves: Dictionary) -> void: _presence_received = received_room_id == room_id)
	_check(realtime.subscribe_room(room_id, {"state": "online"}) == OK, "private room subscribed")
	_check(realtime.connect_realtime() == OK, "Realtime socket started")
	await _wait_until(func() -> bool: return _joined)
	_check(_joined, "private room joined")
	if _joined:
		var refreshed: Dictionary = await backend.refresh_session()
		_check(bool(refreshed.get("ok", false)), "access token refreshed while channel is open")
		_check(realtime.update_access_token(backend.access_token()) == OK, "Realtime token updated in-band")
		_check(realtime.send_broadcast(room_id, "typing_start", {"user_id": backend.user_id()}) == OK, "typing broadcast sent")
		await _wait_until(func() -> bool: return _typing_received)
		_check(_typing_received, "typing broadcast received")
		await _wait_until(func() -> bool: return _presence_received)
		_check(_presence_received, "Presence state or diff received")
		_expected_message_id = _uuid_v4()
		var sent: Dictionary = await backend.send_message(_expected_message_id, room_id, "DB Broadcast 확인")
		_check(bool(sent.get("ok", false)), "database message inserted")
		await _wait_until(func() -> bool: return _database_message_received)
		_check(_database_message_received, "database insert broadcast received")
		_joined = false
		_check(realtime.reconnect_now() == OK, "Realtime reconnect starts immediately after resume")
		await _wait_until(func() -> bool: return _joined)
		_check(_joined, "private room rejoins after reconnect")
	realtime.disconnect_realtime()
	var leave: Dictionary = await backend.call_rpc("leave_room", {"p_room_id": room_id})
	_check(bool(leave.get("ok", false)), "Realtime test room removed")
	realtime.queue_free()
	backend.queue_free()
	_finish.call_deferred()


func _on_broadcast(received_room_id: String, event_name: String, payload: Dictionary, expected_room_id: String) -> void:
	if received_room_id != expected_room_id:
		return
	if event_name == "typing_start":
		_typing_received = true
	elif event_name == "INSERT":
		var record: Dictionary = payload.get("record", {}) as Dictionary
		_database_message_received = str(record.get("id", "")) == _expected_message_id


func _wait_until(predicate: Callable) -> void:
	var deadline := Time.get_ticks_msec() + int(WAIT_TIMEOUT_SECONDS * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout


func _fail(label: String, result: Dictionary) -> void:
	push_error("REALTIME_SETUP_FAILED %s status=%d code=%s message=%s" % [
		label,
		int(result.get("status", 0)),
		str(result.get("error_code", "unknown")),
		str(result.get("error_message", "")),
	])
	quit(1)


func _uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("REALTIME_INTEGRATION_FAILED %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("SIDEY_REALTIME_INTEGRATION_OK")
		quit(0)
	else:
		push_error("SIDEY_REALTIME_INTEGRATION_FAILED failures=%d" % _failures)
		quit(1)
