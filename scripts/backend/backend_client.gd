class_name BackendClient
extends Node

signal session_changed(session: Dictionary)
signal session_lost(reason: String)

const BackendHttpScript := preload("res://scripts/backend/backend_http.gd")
const REFRESH_EXPIRY_MARGIN_SECONDS := 30
const REFRESH_TOKEN_ACCOUNT_PREFIX := "supabase-refresh"
const INVITE_CODE_ACCOUNT_PREFIX := "room-invite"

var _config: BackendConfig
var _platform_bridge: PlatformBridge
var _http: BackendHttp
var _session_profile := "default"
var _session: Dictionary = {}
var _memory_refresh_token := ""
var _memory_invite_codes: Dictionary = {}


func configure(
	config: BackendConfig,
	platform_bridge: PlatformBridge = null,
	session_profile := "default",
) -> Error:
	if config == null or not config.is_valid():
		return ERR_INVALID_PARAMETER
	_config = config
	_platform_bridge = platform_bridge
	_session_profile = _sanitize_account_part(session_profile)
	_http = BackendHttpScript.new()
	_http.name = "BackendHttp"
	add_child(_http)
	return OK


func session() -> Dictionary:
	return _session.duplicate(true)


func user_id() -> String:
	return str((_session.get("user", {}) as Dictionary).get("id", ""))


func access_token() -> String:
	return str(_session.get("access_token", ""))


func has_session() -> bool:
	return not user_id().is_empty() and not access_token().is_empty()


func restore_or_create_session() -> Dictionary:
	var refresh_token := _load_refresh_token()
	if not refresh_token.is_empty():
		var restored: Dictionary = await _request_auth_session(
			"token?grant_type=refresh_token",
			{"refresh_token": refresh_token},
		)
		if bool(restored.get("ok", false)):
			return restored
		_delete_refresh_token()
	return await create_anonymous_session()


func create_anonymous_session() -> Dictionary:
	return await _request_auth_session("signup", {"data": {}})


func refresh_session() -> Dictionary:
	var refresh_token := str(_session.get("refresh_token", ""))
	if refresh_token.is_empty():
		refresh_token = _load_refresh_token()
	if refresh_token.is_empty():
		return _session_failure("refresh_token_missing", "No refresh token is available")
	var result: Dictionary = await _request_auth_session(
		"token?grant_type=refresh_token",
		{"refresh_token": refresh_token},
	)
	if not bool(result.get("ok", false)):
		_session.clear()
		_delete_refresh_token()
		session_lost.emit(str(result.get("error_code", "refresh_failed")))
	return result


func ensure_access_token() -> Dictionary:
	if not has_session():
		return _session_failure("session_missing", "No authenticated session is available")
	var expires_at := int(_session.get("expires_at", 0))
	if expires_at > int(Time.get_unix_time_from_system()) + REFRESH_EXPIRY_MARGIN_SECONDS:
		return {"ok": true, "access_token": access_token()}
	var refreshed: Dictionary = await refresh_session()
	if not bool(refreshed.get("ok", false)):
		return refreshed
	return {"ok": true, "access_token": access_token()}


func call_rpc(function_name: String, arguments: Dictionary = {}) -> Dictionary:
	return await _authorized_request(
		HTTPClient.METHOD_POST,
		_config.rest_url("rpc/%s" % function_name.uri_encode()),
		arguments,
	)


func select_rows(table_name: String, query := "") -> Dictionary:
	var url := _config.rest_url(table_name.uri_encode())
	if not query.is_empty():
		url += "?%s" % query
	return await _authorized_request(HTTPClient.METHOD_GET, url)


func upsert_profile(nickname: String, character_id: String) -> Dictionary:
	return await call_rpc("upsert_profile", {"p_nickname": nickname, "p_character_id": character_id})


func create_room(room_name: String) -> Dictionary:
	var result: Dictionary = await call_rpc("create_room", {"p_name": room_name})
	if bool(result.get("ok", false)) and result.get("data") is Array and not (result.data as Array).is_empty():
		var row := (result.data as Array)[0] as Dictionary
		var room_id := str(row.get("room_id", ""))
		var invite_code := str(row.get("invite_code", ""))
		if not room_id.is_empty() and not invite_code.is_empty():
			store_invite_code(room_id, invite_code)
	return result


func join_room(invite_code: String) -> Dictionary:
	return await call_rpc("join_room", {"p_invite_code": invite_code})


func send_message(message_id: String, room_id: String, body: String) -> Dictionary:
	return await call_rpc("send_message", {
		"p_id": message_id,
		"p_room_id": room_id,
		"p_body": body,
	})


func recent_messages(room_id: String, limit := 50) -> Dictionary:
	var query := "select=*&room_id=eq.%s&order=created_at.desc&limit=%d" % [
		room_id.uri_encode(),
		clampi(limit, 1, 50),
	]
	return await select_rows("messages", query)


func store_invite_code(room_id: String, invite_code: String) -> Error:
	if room_id.is_empty() or invite_code.is_empty():
		return ERR_INVALID_PARAMETER
	_memory_invite_codes[room_id] = invite_code
	if is_instance_valid(_platform_bridge) and _platform_bridge.is_native_available():
		return _platform_bridge.store_secret(_invite_account(room_id), invite_code)
	return OK


func read_invite_code(room_id: String) -> String:
	if is_instance_valid(_platform_bridge) and _platform_bridge.is_native_available():
		var stored := _platform_bridge.read_secret(_invite_account(room_id))
		if not stored.is_empty():
			return stored
	return str(_memory_invite_codes.get(room_id, ""))


func delete_invite_code(room_id: String) -> Error:
	_memory_invite_codes.erase(room_id)
	if is_instance_valid(_platform_bridge) and _platform_bridge.is_native_available():
		var error := _platform_bridge.delete_secret(_invite_account(room_id))
		return OK if error == ERR_DOES_NOT_EXIST else error
	return OK


func clear_session() -> Error:
	_session.clear()
	_memory_refresh_token = ""
	return _delete_refresh_token()


func _request_auth_session(path: String, body: Dictionary) -> Dictionary:
	var result: Dictionary = await _http.request_json(
		HTTPClient.METHOD_POST,
		_config.auth_url(path),
		_base_headers(false),
		body,
	)
	if not bool(result.get("ok", false)):
		return result
	if not result.get("data") is Dictionary:
		return _session_failure("invalid_auth_response", "Auth response is not an object")
	var data := result.data as Dictionary
	if str(data.get("access_token", "")).is_empty() or str(data.get("refresh_token", "")).is_empty():
		return _session_failure("invalid_auth_response", "Auth response is missing tokens")
	var user: Dictionary = data.get("user", {}) as Dictionary
	if str(user.get("id", "")).is_empty():
		return _session_failure("invalid_auth_response", "Auth response is missing a user")
	_session = data.duplicate(true)
	_session["expires_at"] = int(Time.get_unix_time_from_system()) + int(data.get("expires_in", 3600))
	var refresh_token := str(data.get("refresh_token", ""))
	_memory_refresh_token = refresh_token
	var store_error := _store_refresh_token(refresh_token)
	_session["secure_storage_error"] = store_error
	session_changed.emit(session())
	return {"ok": true, "status": int(result.get("status", 200)), "data": session()}


func _authorized_request(method: HTTPClient.Method, url: String, body: Variant = null) -> Dictionary:
	var token_result: Dictionary = await ensure_access_token()
	if not bool(token_result.get("ok", false)):
		return token_result
	return await _http.request_json(method, url, _base_headers(true), body)


func _base_headers(authenticated: bool) -> PackedStringArray:
	var headers := PackedStringArray([
		"apikey: %s" % _config.publishable_key,
		"Content-Type: application/json",
		"Accept: application/json",
	])
	if authenticated:
		headers.append("Authorization: Bearer %s" % access_token())
	return headers


func _store_refresh_token(refresh_token: String) -> Error:
	if is_instance_valid(_platform_bridge) and _platform_bridge.is_native_available():
		return _platform_bridge.store_secret(_refresh_account(), refresh_token)
	return ERR_UNAVAILABLE


func _load_refresh_token() -> String:
	if is_instance_valid(_platform_bridge) and _platform_bridge.is_native_available():
		var stored := _platform_bridge.read_secret(_refresh_account())
		if not stored.is_empty():
			return stored
	return _memory_refresh_token


func _delete_refresh_token() -> Error:
	if is_instance_valid(_platform_bridge) and _platform_bridge.is_native_available():
		var error := _platform_bridge.delete_secret(_refresh_account())
		return OK if error == ERR_DOES_NOT_EXIST else error
	return OK


func _refresh_account() -> String:
	return "%s:%s:%s" % [REFRESH_TOKEN_ACCOUNT_PREFIX, _backend_fingerprint(), _session_profile]


func _invite_account(room_id: String) -> String:
	return "%s:%s:%s:%s" % [
		INVITE_CODE_ACCOUNT_PREFIX,
		_backend_fingerprint(),
		_session_profile,
		_sanitize_account_part(room_id),
	]


func _backend_fingerprint() -> String:
	return _config.url.sha256_text().left(16)


static func _sanitize_account_part(value: String) -> String:
	var cleaned := value.strip_edges().validate_node_name().replace(" ", "-")
	return "default" if cleaned.is_empty() else cleaned.left(64)


static func _session_failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": 0,
		"data": null,
		"error_code": code,
		"error_message": message,
	}
