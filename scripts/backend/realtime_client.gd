class_name RealtimeClient
extends Node

signal socket_connected
signal socket_disconnected(code: int, reason: String)
signal channel_joined(room_id: String)
signal channel_error(room_id: String, reason: String)
signal broadcast_received(room_id: String, event_name: String, payload: Dictionary)
signal presence_state_received(room_id: String, state: Dictionary)
signal presence_diff_received(room_id: String, joins: Dictionary, leaves: Dictionary)
signal heartbeat_timed_out
signal reconnect_scheduled(delay_seconds: float)

const RealtimeProtocolScript := preload("res://scripts/backend/realtime_protocol.gd")
const ReconnectBackoffScript := preload("res://scripts/backend/reconnect_backoff.gd")
const MAX_CHANNELS := 5
const HEARTBEAT_INTERVAL_SECONDS := 25.0
const RESPONSE_TIMEOUT_SECONDS := 10.0

var _config: BackendConfig
var _socket: WebSocketPeer
var _backoff: ReconnectBackoff
var _access_token := ""
var _presence_key := ""
var _desired_rooms: Dictionary = {}
var _join_refs: Dictionary = {}
var _pending: Dictionary = {}
var _next_message_ref := 0
var _last_socket_state := WebSocketPeer.STATE_CLOSED
var _last_heartbeat_at := 0.0
var _heartbeat_ref := ""
var _reconnect_at := -1.0
var _manual_disconnect := true


func configure(config: BackendConfig, access_token: String, presence_key: String) -> Error:
	if config == null or not config.is_valid() or access_token.is_empty() or presence_key.is_empty():
		return ERR_INVALID_PARAMETER
	_config = config
	_access_token = access_token
	_presence_key = presence_key
	_backoff = ReconnectBackoffScript.new()
	set_process(true)
	return OK


func subscribe_room(room_id: String, presence_payload: Dictionary = {}) -> Error:
	if room_id.is_empty():
		return ERR_INVALID_PARAMETER
	if not _desired_rooms.has(room_id) and _desired_rooms.size() >= MAX_CHANNELS:
		return ERR_BUSY
	var payload := presence_payload.duplicate(true)
	payload["user_id"] = _presence_key
	_desired_rooms[room_id] = payload
	if is_connected_to_server():
		_join_room(room_id)
	return OK


func unsubscribe_room(room_id: String) -> Error:
	if not _desired_rooms.has(room_id):
		return ERR_DOES_NOT_EXIST
	_desired_rooms.erase(room_id)
	var topic := RealtimeProtocolScript.room_topic(room_id)
	var join_ref := str(_join_refs.get(topic, ""))
	if is_connected_to_server() and not join_ref.is_empty():
		var message_ref := _new_ref()
		_send_text(RealtimeProtocolScript.leave_frame(topic, join_ref, message_ref))
	_join_refs.erase(topic)
	return OK


func connect_realtime() -> Error:
	if _config == null or _access_token.is_empty():
		return ERR_UNCONFIGURED
	if _socket != null and _socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		return OK
	_manual_disconnect = false
	_reconnect_at = -1.0
	return _open_socket()


func disconnect_realtime() -> void:
	_manual_disconnect = true
	_reconnect_at = -1.0
	_pending.clear()
	_join_refs.clear()
	_heartbeat_ref = ""
	if _socket != null and _socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		_socket.close(1000, "client_disconnect")


func reconnect_now() -> Error:
	if _config == null:
		return ERR_UNCONFIGURED
	_manual_disconnect = false
	_reconnect_at = -1.0
	if _socket != null and _socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		_socket.close(1001, "client_reconnect")
	_socket = null
	_last_socket_state = WebSocketPeer.STATE_CLOSED
	return _open_socket()


func update_access_token(access_token: String) -> Error:
	if access_token.is_empty():
		return ERR_INVALID_PARAMETER
	_access_token = access_token
	if not is_connected_to_server():
		return OK
	for topic in _join_refs:
		var message_ref := _new_ref()
		var join_ref := str(_join_refs[topic])
		_send_text(RealtimeProtocolScript.access_token_frame(topic, join_ref, message_ref, _access_token))
	return OK


func update_presence(room_id: String, payload: Dictionary) -> Error:
	if not _desired_rooms.has(room_id):
		return ERR_DOES_NOT_EXIST
	var stored := payload.duplicate(true)
	stored["user_id"] = _presence_key
	_desired_rooms[room_id] = stored
	if not is_room_joined(room_id):
		return OK
	return _send_presence(room_id)


func send_broadcast(room_id: String, event_name: String, payload: Dictionary) -> Error:
	if event_name.is_empty() or not is_room_joined(room_id):
		return ERR_UNCONFIGURED
	var topic := RealtimeProtocolScript.room_topic(room_id)
	var message_ref := _new_ref()
	_pending[message_ref] = {"kind": "broadcast", "room_id": room_id, "sent_at": _now()}
	return _send_text(RealtimeProtocolScript.broadcast_frame(
		topic,
		str(_join_refs[topic]),
		message_ref,
		event_name,
		payload,
	))


func is_connected_to_server() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func is_room_joined(room_id: String) -> bool:
	return _join_refs.has(RealtimeProtocolScript.room_topic(room_id))


func subscribed_room_ids() -> Array[String]:
	var room_ids: Array[String] = []
	for room_id in _desired_rooms:
		room_ids.append(str(room_id))
	return room_ids


func _process(_delta: float) -> void:
	var now := _now()
	if _socket == null:
		if not _manual_disconnect and _reconnect_at >= 0.0 and now >= _reconnect_at:
			_open_socket()
		return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if _last_socket_state != WebSocketPeer.STATE_OPEN:
			_on_socket_opened(now)
		_drain_packets()
		_poll_heartbeat(now)
		_poll_response_timeouts(now)
	elif state == WebSocketPeer.STATE_CLOSED and _last_socket_state != WebSocketPeer.STATE_CLOSED:
		var code := _socket.get_close_code()
		var reason := _socket.get_close_reason()
		_on_socket_closed(code, reason)
	_last_socket_state = state


func _open_socket() -> Error:
	_socket = WebSocketPeer.new()
	var error := _socket.connect_to_url(_config.realtime_url())
	_last_socket_state = _socket.get_ready_state()
	if error != OK:
		_socket = null
		_schedule_reconnect()
	return error


func _on_socket_opened(now: float) -> void:
	_backoff.reset()
	_reconnect_at = -1.0
	_pending.clear()
	_join_refs.clear()
	_heartbeat_ref = ""
	_last_heartbeat_at = now
	socket_connected.emit()
	for room_id in _desired_rooms:
		_join_room(str(room_id))


func _on_socket_closed(code: int, reason: String) -> void:
	_pending.clear()
	_join_refs.clear()
	_heartbeat_ref = ""
	_socket = null
	socket_disconnected.emit(code, reason)
	if not _manual_disconnect:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	if _manual_disconnect:
		return
	var delay := _backoff.next_delay()
	_reconnect_at = _now() + delay
	reconnect_scheduled.emit(delay)


func _join_room(room_id: String) -> void:
	var topic := RealtimeProtocolScript.room_topic(room_id)
	if _join_refs.has(topic):
		return
	var join_ref := _new_ref()
	_pending[join_ref] = {"kind": "join", "room_id": room_id, "sent_at": _now()}
	_send_text(RealtimeProtocolScript.join_frame(topic, join_ref, _access_token, _presence_key, true))


func _send_presence(room_id: String) -> Error:
	var topic := RealtimeProtocolScript.room_topic(room_id)
	if not _join_refs.has(topic):
		return ERR_UNCONFIGURED
	var message_ref := _new_ref()
	_pending[message_ref] = {"kind": "presence", "room_id": room_id, "sent_at": _now()}
	return _send_text(RealtimeProtocolScript.presence_frame(
		topic,
		str(_join_refs[topic]),
		message_ref,
		_desired_rooms[room_id],
	))


func _send_text(frame: String) -> Error:
	if not is_connected_to_server():
		return ERR_UNAVAILABLE
	return _socket.send_text(frame)


func _drain_packets() -> void:
	while _socket != null and _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var frame := RealtimeProtocolScript.decode_frame(packet.get_string_from_utf8()) \
			if _socket.was_string_packet() \
			else RealtimeProtocolScript.decode_binary_frame(packet)
		if frame.has("error"):
			continue
		_handle_frame(frame)


func _handle_frame(frame: Dictionary) -> void:
	var event_name := str(frame.get("event", ""))
	var wire_topic := str(frame.get("topic", ""))
	var topic := RealtimeProtocolScript.client_topic(wire_topic)
	var room_id := topic.trim_prefix("room:")
	var payload := frame.get("payload", {}) as Dictionary
	match event_name:
		"phx_reply":
			_handle_reply(str(frame.get("ref", "")), payload)
		"phx_error", "phx_close":
			_join_refs.erase(topic)
			channel_error.emit(room_id, event_name)
			if _socket != null:
				_socket.close(1011, event_name)
		"system":
			if str(payload.get("status", "ok")) != "ok":
				channel_error.emit(room_id, str(payload.get("message", "system_error")))
				if _socket != null:
					_socket.close(1011, "system_error")
		"broadcast":
			broadcast_received.emit(
				room_id,
				str(payload.get("event", "")),
				(payload.get("payload", {}) as Dictionary).duplicate(true),
			)
		"presence_state":
			presence_state_received.emit(room_id, payload.duplicate(true))
		"presence_diff":
			presence_diff_received.emit(
				room_id,
				(payload.get("joins", {}) as Dictionary).duplicate(true),
				(payload.get("leaves", {}) as Dictionary).duplicate(true),
			)


func _handle_reply(message_ref: String, payload: Dictionary) -> void:
	if message_ref.is_empty() or not _pending.has(message_ref):
		return
	var pending := _pending[message_ref] as Dictionary
	_pending.erase(message_ref)
	if message_ref == _heartbeat_ref:
		_heartbeat_ref = ""
	var status := str(payload.get("status", "error"))
	var kind := str(pending.get("kind", ""))
	var room_id := str(pending.get("room_id", ""))
	if status != "ok":
		if kind == "join":
			channel_error.emit(room_id, str(payload.get("response", payload)))
		return
	if kind == "join":
		var topic := RealtimeProtocolScript.room_topic(room_id)
		_join_refs[topic] = message_ref
		channel_joined.emit(room_id)
		_send_presence(room_id)


func _poll_heartbeat(now: float) -> void:
	if not _heartbeat_ref.is_empty():
		var pending := _pending.get(_heartbeat_ref, {}) as Dictionary
		if response_timed_out(float(pending.get("sent_at", now)), now):
			heartbeat_timed_out.emit()
			_socket.close(1001, "heartbeat_timeout")
		return
	if now - _last_heartbeat_at < HEARTBEAT_INTERVAL_SECONDS:
		return
	_heartbeat_ref = _new_ref()
	_pending[_heartbeat_ref] = {"kind": "heartbeat", "sent_at": now}
	_last_heartbeat_at = now
	_send_text(RealtimeProtocolScript.heartbeat_frame(_heartbeat_ref))


func _poll_response_timeouts(now: float) -> void:
	var timed_out_refs: Array[String] = []
	for message_ref in _pending:
		if str(message_ref) == _heartbeat_ref:
			continue
		var pending := _pending[message_ref] as Dictionary
		if response_timed_out(float(pending.get("sent_at", now)), now):
			timed_out_refs.append(str(message_ref))
	for message_ref in timed_out_refs:
		var pending := _pending[message_ref] as Dictionary
		_pending.erase(message_ref)
		if str(pending.get("kind", "")) == "join":
			channel_error.emit(str(pending.get("room_id", "")), "join_timeout")


func _new_ref() -> String:
	_next_message_ref += 1
	return str(_next_message_ref)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func response_timed_out(sent_at: float, now: float) -> bool:
	return now - sent_at >= RESPONSE_TIMEOUT_SECONDS
