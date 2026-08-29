class_name BackendRuntime
extends Node

signal boot_completed(onboarding_required: bool)
signal boot_failed(code: String, message: String)
signal snapshot_applied
signal snapshot_sync_finished(result: Dictionary)
signal message_received(message: Dictionary, replayed: bool)
signal typing_changed(room_id: String, user_id: String, typing: bool)
signal presence_changed(room_id: String, user_id: String, presence: String)
signal connection_state_changed(state: String)

const BackendClientScript := preload("res://scripts/backend/backend_client.gd")
const BackendRepositoryScript := preload("res://scripts/backend/backend_repository.gd")
const RealtimeClientScript := preload("res://scripts/backend/realtime_client.gd")
const PresenceRosterScript := preload("res://scripts/backend/presence_roster.gd")
const TYPING_EXPIRY_SECONDS := 4.0

var _config: BackendConfig
var _platform_bridge: PlatformBridge
var _room_controller: RoomController
var _backend: BackendClient
var _repository: BackendRepository
var _realtime: RealtimeClient
var _presence_roster: RefCounted
var _session_profile := "default"
var _local_presence := "online"
var _typing_expiry: Dictionary = {}
var _started := false
var _realtime_configured := false
var _sync_in_progress := false
var _sync_requested := false


func configure(
	config: BackendConfig,
	platform_bridge: PlatformBridge,
	room_controller: RoomController,
	session_profile := "default",
) -> Error:
	if config == null or not config.is_valid() or room_controller == null:
		return ERR_INVALID_PARAMETER
	_config = config
	_platform_bridge = platform_bridge
	_room_controller = room_controller
	_session_profile = session_profile
	_backend = BackendClientScript.new()
	_backend.name = "BackendClient"
	add_child(_backend)
	var backend_error := _backend.configure(_config, _platform_bridge, _session_profile)
	if backend_error != OK:
		return backend_error
	_backend.session_changed.connect(_on_session_changed)
	_repository = BackendRepositoryScript.new()
	_realtime = RealtimeClientScript.new()
	_realtime.name = "RealtimeClient"
	add_child(_realtime)
	_realtime.channel_joined.connect(_on_channel_joined)
	_realtime.socket_connected.connect(func() -> void: connection_state_changed.emit("online"))
	_realtime.socket_disconnected.connect(_on_socket_disconnected)
	_realtime.broadcast_received.connect(_on_broadcast_received)
	_realtime.presence_state_received.connect(_on_presence_state)
	_realtime.presence_diff_received.connect(_on_presence_diff)
	_presence_roster = PresenceRosterScript.new()
	set_process(true)
	return OK


func start() -> Dictionary:
	if _started:
		return {"ok": true, "onboarding_required": not _room_controller.is_onboarding_complete()}
	_started = true
	connection_state_changed.emit("reconnecting")
	var auth: Dictionary = await _backend.restore_or_create_session()
	if not bool(auth.get("ok", false)):
		_started = false
		_emit_boot_failure(auth)
		return auth
	var synced: Dictionary = await sync_snapshot()
	if not bool(synced.get("ok", false)):
		_started = false
		_emit_boot_failure(synced)
		return synced
	var realtime_error := _configure_realtime_if_needed()
	if realtime_error != OK:
		var failure := _failure("realtime_config_failed", error_string(realtime_error))
		_emit_boot_failure(failure)
		return failure
	_sync_realtime_rooms()
	if not _room_controller.rooms().is_empty():
		_realtime.connect_realtime()
	var onboarding_required := not _room_controller.is_onboarding_complete()
	boot_completed.emit(onboarding_required)
	return {"ok": true, "onboarding_required": onboarding_required}


func sync_snapshot() -> Dictionary:
	if _sync_in_progress:
		await snapshot_sync_finished
		return await sync_snapshot()
	_sync_in_progress = true
	var snapshot: Dictionary = await _repository.load_snapshot(_backend)
	if bool(snapshot.get("ok", false)):
		var apply_error := _room_controller.replace_server_state(
			snapshot.get("profile", {}) as Dictionary,
			_typed_dictionaries(snapshot.get("rooms", [])),
		)
		if apply_error != OK:
			snapshot = _failure("snapshot_apply_failed", error_string(apply_error))
		else:
			_sync_realtime_rooms()
			snapshot_applied.emit()
	_sync_in_progress = false
	snapshot_sync_finished.emit(snapshot)
	if _sync_requested:
		_sync_requested = false
		sync_snapshot.call_deferred()
	return snapshot


func onboard_create(nickname: String, character_id: String, room_name: String) -> Dictionary:
	var profile: Dictionary = await _backend.upsert_profile(nickname, character_id)
	if not bool(profile.get("ok", false)):
		return profile
	var created: Dictionary = await _backend.create_room(room_name)
	if not bool(created.get("ok", false)):
		return created
	return await _sync_after_mutation(created)


func onboard_join(nickname: String, character_id: String, invite_code: String) -> Dictionary:
	var profile: Dictionary = await _backend.upsert_profile(nickname, character_id)
	if not bool(profile.get("ok", false)):
		return profile
	var joined: Dictionary = await _backend.join_room(invite_code)
	var business_error := _business_error(joined)
	if not business_error.is_empty():
		return _failure(business_error, business_error)
	if not bool(joined.get("ok", false)):
		return joined
	return await _sync_after_mutation(joined)


func update_profile(nickname: String, character_id: String) -> Dictionary:
	return await _sync_after_mutation(await _backend.upsert_profile(nickname, character_id))


func create_room(room_name: String) -> Dictionary:
	return await _sync_after_mutation(await _backend.create_room(room_name))


func join_room(invite_code: String) -> Dictionary:
	var result: Dictionary = await _backend.join_room(invite_code)
	var business_error := _business_error(result)
	if not business_error.is_empty():
		return _failure(business_error, business_error)
	return await _sync_after_mutation(result)


func rename_room(room_id: String, room_name: String) -> Dictionary:
	return await _sync_after_mutation(await _backend.call_rpc(
		"rename_room",
		{"p_room_id": room_id, "p_name": room_name},
	))


func rotate_invite_code(room_id: String) -> Dictionary:
	var result: Dictionary = await _backend.call_rpc("rotate_invite_code", {"p_room_id": room_id})
	if bool(result.get("ok", false)):
		var invite_code := str(result.get("data", ""))
		if not invite_code.is_empty():
			_backend.store_invite_code(room_id, invite_code)
		await sync_snapshot()
	return result


func leave_room(room_id: String) -> Dictionary:
	var result: Dictionary = await _backend.call_rpc("leave_room", {"p_room_id": room_id})
	if bool(result.get("ok", false)):
		_backend.delete_invite_code(room_id)
	return await _sync_after_mutation(result)


func remove_room_member(room_id: String, user_id: String) -> Dictionary:
	return await _sync_after_mutation(await _backend.call_rpc(
		"remove_room_member",
		{"p_room_id": room_id, "p_user_id": user_id},
	))


func send_message(message_id: String, room_id: String, body: String) -> Dictionary:
	return await _backend.send_message(message_id, room_id, body)


func send_typing(room_id: String, action: StringName) -> Error:
	return _realtime.send_broadcast(room_id, str(action), {"user_id": _backend.user_id()})


func set_local_presence(presence: String) -> void:
	_local_presence = "away" if presence == "away" else "online"
	if _realtime_configured:
		for room_id in _realtime.subscribed_room_ids():
			_realtime.update_presence(room_id, _presence_payload())


func reconnect_after_resume() -> Error:
	if not _realtime_configured or _room_controller.rooms().is_empty():
		return OK
	connection_state_changed.emit("reconnecting")
	return _realtime.reconnect_now()


func backend_client() -> BackendClient:
	return _backend


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var expired: Array[String] = []
	for key in _typing_expiry:
		if now >= float(_typing_expiry[key]):
			expired.append(str(key))
	for key in expired:
		_typing_expiry.erase(key)
		var parts := key.split("|", false, 1)
		if parts.size() == 2:
			typing_changed.emit(parts[0], parts[1], false)


func _configure_realtime_if_needed() -> Error:
	if _realtime_configured:
		return OK
	var error := _realtime.configure(_config, _backend.access_token(), _backend.user_id())
	if error == OK:
		_realtime_configured = true
	return error


func _sync_realtime_rooms() -> void:
	if not _realtime_configured:
		return
	var desired: Dictionary = {}
	for room in _room_controller.rooms():
		desired[str(room.get("id", ""))] = true
	for subscribed_room_id in _realtime.subscribed_room_ids():
		if not desired.has(subscribed_room_id):
			_realtime.unsubscribe_room(subscribed_room_id)
			_presence_roster.clear_room(subscribed_room_id)
	for room_id in desired:
		if room_id not in _realtime.subscribed_room_ids():
			_realtime.subscribe_room(str(room_id), _presence_payload())
	if not desired.is_empty() and not _realtime.is_connected_to_server():
		_realtime.connect_realtime()


func _presence_payload() -> Dictionary:
	return {
		"state": _local_presence,
		"online_at": Time.get_datetime_string_from_system(true),
	}


func _on_session_changed(_session: Dictionary) -> void:
	if _realtime_configured:
		_realtime.update_access_token(_backend.access_token())


func _on_socket_disconnected(_code: int, _reason: String) -> void:
	connection_state_changed.emit("reconnecting")
	for room in _room_controller.rooms():
		for member in room.get("members", []) as Array:
			_emit_presence(str(room.get("id", "")), str((member as Dictionary).get("user_id", "")), "reconnecting")


func _on_channel_joined(room_id: String) -> void:
	_sync_recent_messages.call_deferred(room_id)


func _sync_recent_messages(room_id: String) -> void:
	var result: Dictionary = await _backend.recent_messages(room_id, 50)
	if not bool(result.get("ok", false)) or not result.get("data") is Array:
		return
	var rows := result.data as Array
	rows.reverse()
	for row in rows:
		if row is Dictionary:
			message_received.emit((row as Dictionary).duplicate(true), true)


func _on_broadcast_received(room_id: String, event_name: String, payload: Dictionary) -> void:
	if event_name in ["typing_start", "typing_keepalive", "typing_stop"]:
		var user_id := str(payload.get("user_id", ""))
		if user_id.is_empty() or user_id == _backend.user_id():
			return
		var key := "%s|%s" % [room_id, user_id]
		if event_name == "typing_stop":
			_typing_expiry.erase(key)
			typing_changed.emit(room_id, user_id, false)
		else:
			_typing_expiry[key] = Time.get_ticks_msec() / 1000.0 + TYPING_EXPIRY_SECONDS
			typing_changed.emit(room_id, user_id, true)
		return
	var table_name := str(payload.get("table", ""))
	if table_name == "messages" and event_name == "INSERT":
		var record := payload.get("record", {}) as Dictionary
		if not record.is_empty():
			message_received.emit(record.duplicate(true), false)
	elif table_name in ["profiles", "rooms", "room_members"]:
		_request_snapshot_sync()


func _on_presence_state(room_id: String, state: Dictionary) -> void:
	for user_id in _presence_roster.apply_state(room_id, state):
		_emit_presence(room_id, user_id, _presence_roster.presence(room_id, user_id))
	_emit_missing_members_offline(room_id, state)


func _on_presence_diff(room_id: String, joins: Dictionary, leaves: Dictionary) -> void:
	for user_id in _presence_roster.apply_diff(room_id, joins, leaves):
		_emit_presence(room_id, user_id, _presence_roster.presence(room_id, user_id))


func _emit_missing_members_offline(room_id: String, state: Dictionary) -> void:
	for member in _room_controller.room_by_id(room_id).get("members", []) as Array:
		var user_id := str((member as Dictionary).get("user_id", ""))
		if not state.has(user_id):
			_emit_presence(room_id, user_id, "offline")


func _emit_presence(room_id: String, user_id: String, presence: String) -> void:
	_room_controller.set_cached_member_presence(room_id, user_id, presence)
	presence_changed.emit(room_id, user_id, presence)


func _request_snapshot_sync() -> void:
	_sync_requested = true
	if not _sync_in_progress:
		_sync_requested = false
		sync_snapshot.call_deferred()


func _sync_after_mutation(result: Dictionary) -> Dictionary:
	if not bool(result.get("ok", false)):
		return result
	var synced: Dictionary = await sync_snapshot()
	return result if bool(synced.get("ok", false)) else synced


static func _business_error(result: Dictionary) -> String:
	if not bool(result.get("ok", false)) or not result.get("data") is Array:
		return ""
	var rows := result.data as Array
	if rows.is_empty() or not rows[0] is Dictionary:
		return ""
	return str((rows[0] as Dictionary).get("error_code", ""))


static func _typed_dictionaries(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value as Array:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result


func _emit_boot_failure(result: Dictionary) -> void:
	boot_failed.emit(str(result.get("error_code", "unknown")), str(result.get("error_message", "")))


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "status": 0, "data": null, "error_code": code, "error_message": message}
