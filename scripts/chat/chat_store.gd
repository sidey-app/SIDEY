class_name ChatStore
extends RefCounted

const MAX_BODY_LENGTH := 200
const MAX_BODY_LINES := 3
const RECENT_MESSAGE_LIMIT := 50

var _messages_by_room: Dictionary = {}
var _message_ids: Dictionary = {}


func insert(message: Dictionary) -> Error:
	var message_id := str(message.get("id", ""))
	var room_id := str(message.get("room_id", ""))
	var body := str(message.get("body", ""))
	if message_id.is_empty() or room_id.is_empty() or str(message.get("sender_id", "")).is_empty():
		return ERR_INVALID_DATA
	var body_error := validate_body(body)
	if body_error != OK:
		return body_error
	if _message_ids.has(message_id):
		return ERR_ALREADY_EXISTS
	var stored := message.duplicate(true)
	stored["body"] = body.strip_edges()
	_message_ids[message_id] = room_id
	var room_messages: Array = _messages_by_room.get(room_id, []) as Array
	room_messages.append(stored)
	room_messages.sort_custom(_sort_messages)
	if room_messages.size() > RECENT_MESSAGE_LIMIT:
		room_messages = room_messages.slice(room_messages.size() - RECENT_MESSAGE_LIMIT)
	_messages_by_room[room_id] = room_messages
	return OK


func replace(message: Dictionary) -> Error:
	var message_id := str(message.get("id", ""))
	var room_id := str(message.get("room_id", ""))
	var body := str(message.get("body", ""))
	if message_id.is_empty() or room_id.is_empty() or str(message.get("sender_id", "")).is_empty():
		return ERR_INVALID_DATA
	if validate_body(body) != OK:
		return ERR_INVALID_DATA
	if not _message_ids.has(message_id):
		return ERR_DOES_NOT_EXIST
	if str(_message_ids[message_id]) != room_id:
		return ERR_INVALID_DATA
	var room_messages: Array = _messages_by_room.get(room_id, []) as Array
	for index in room_messages.size():
		if str((room_messages[index] as Dictionary).get("id", "")) != message_id:
			continue
		var stored := message.duplicate(true)
		stored["body"] = body.strip_edges()
		room_messages[index] = stored
		room_messages.sort_custom(_sort_messages)
		_messages_by_room[room_id] = room_messages
		return OK
	return ERR_DOES_NOT_EXIST


func remove(message_id: String) -> Error:
	if not _message_ids.has(message_id):
		return ERR_DOES_NOT_EXIST
	var room_id := str(_message_ids[message_id])
	var room_messages: Array = _messages_by_room.get(room_id, []) as Array
	for index in room_messages.size():
		if str((room_messages[index] as Dictionary).get("id", "")) != message_id:
			continue
		room_messages.remove_at(index)
		_message_ids.erase(message_id)
		if room_messages.is_empty():
			_messages_by_room.erase(room_id)
		else:
			_messages_by_room[room_id] = room_messages
		return OK
	_message_ids.erase(message_id)
	return ERR_DOES_NOT_EXIST


func recent(room_id: String, limit := RECENT_MESSAGE_LIMIT) -> Array[Dictionary]:
	var stored: Array = _messages_by_room.get(room_id, []) as Array
	var start := maxi(0, stored.size() - clampi(limit, 0, RECENT_MESSAGE_LIMIT))
	var result: Array[Dictionary] = []
	for message in stored.slice(start):
		result.append((message as Dictionary).duplicate(true))
	return result


func has_message(message_id: String) -> bool:
	return _message_ids.has(message_id)


func clear_room(room_id: String) -> void:
	var stored: Array = _messages_by_room.get(room_id, []) as Array
	for message in stored:
		_message_ids.erase(str((message as Dictionary).get("id", "")))
	_messages_by_room.erase(room_id)


static func validate_body(body: String) -> Error:
	var cleaned := body.strip_edges()
	if cleaned.is_empty() or validate_draft(body) != OK:
		return ERR_INVALID_PARAMETER
	return OK


static func validate_draft(body: String) -> Error:
	if body.length() > MAX_BODY_LENGTH:
		return ERR_INVALID_PARAMETER
	if body.split("\n", true).size() > MAX_BODY_LINES:
		return ERR_INVALID_PARAMETER
	return OK


static func _sort_messages(left: Dictionary, right: Dictionary) -> bool:
	var left_created := _created_time(left.get("created_at", 0.0))
	var right_created := _created_time(right.get("created_at", 0.0))
	if absf(left_created - right_created) < 0.000001:
		return str(left.get("id", "")) < str(right.get("id", ""))
	return left_created < right_created


static func _created_time(value: Variant) -> float:
	if value is String and (value as String).contains("T"):
		var timestamp := value as String
		var base := timestamp.left(19)
		var unix_time := float(Time.get_unix_time_from_datetime_string(base))
		var offset_start := maxi(timestamp.find("+", 19), timestamp.find("-", 19))
		if offset_start >= 0:
			var offset_parts := timestamp.substr(offset_start + 1, 5).split(":")
			if offset_parts.size() == 2:
				var offset_seconds := int(offset_parts[0]) * 3600 + int(offset_parts[1]) * 60
				unix_time += offset_seconds if timestamp[offset_start] == "-" else -offset_seconds
		return unix_time
	return float(value)
