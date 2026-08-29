class_name PresenceRoster
extends RefCounted

var _rooms: Dictionary = {}


func apply_state(room_id: String, state: Dictionary) -> Array[String]:
	var room_state: Dictionary = {}
	for user_key in state:
		var entry := state[user_key] as Dictionary
		room_state[str(user_key)] = _metas(entry.get("metas", []))
	_rooms[room_id] = room_state
	return _string_keys(room_state)


func apply_diff(room_id: String, joins: Dictionary, leaves: Dictionary) -> Array[String]:
	var room_state: Dictionary = _rooms.get(room_id, {}) as Dictionary
	var changed: Dictionary = {}
	for user_key in joins:
		var user_id := str(user_key)
		var current: Array = room_state.get(user_id, []) as Array
		var joining := _metas((joins[user_key] as Dictionary).get("metas", []))
		for meta in joining:
			var reference := str((meta as Dictionary).get("phx_ref", ""))
			if not _has_reference(current, reference):
				current.append((meta as Dictionary).duplicate(true))
		room_state[user_id] = current
		changed[user_id] = true
	for user_key in leaves:
		var user_id := str(user_key)
		var current: Array = room_state.get(user_id, []) as Array
		var leaving := _metas((leaves[user_key] as Dictionary).get("metas", []))
		for meta in leaving:
			_remove_reference(current, str((meta as Dictionary).get("phx_ref", "")))
		if current.is_empty():
			room_state.erase(user_id)
		else:
			room_state[user_id] = current
		changed[user_id] = true
	_rooms[room_id] = room_state
	return _string_keys(changed)


func presence(room_id: String, user_id: String) -> String:
	var room_state: Dictionary = _rooms.get(room_id, {}) as Dictionary
	var metas: Array = room_state.get(user_id, []) as Array
	if metas.is_empty():
		return "offline"
	for meta in metas:
		if str((meta as Dictionary).get("state", "online")) == "online":
			return "online"
	for meta in metas:
		if str((meta as Dictionary).get("state", "online")) == "away":
			return "away"
	return "offline"


func clear_room(room_id: String) -> void:
	_rooms.erase(room_id)


static func _metas(value: Variant) -> Array:
	var result: Array = []
	if not value is Array:
		return result
	for meta in value as Array:
		if meta is Dictionary:
			result.append((meta as Dictionary).duplicate(true))
	return result


static func _has_reference(metas: Array, reference: String) -> bool:
	if reference.is_empty():
		return false
	for meta in metas:
		if str((meta as Dictionary).get("phx_ref", "")) == reference:
			return true
	return false


static func _remove_reference(metas: Array, reference: String) -> void:
	for index in range(metas.size() - 1, -1, -1):
		if str((metas[index] as Dictionary).get("phx_ref", "")) == reference:
			metas.remove_at(index)


static func _string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key in values:
		result.append(str(key))
	return result
