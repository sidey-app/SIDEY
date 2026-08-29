class_name BackendRepository
extends RefCounted


func load_snapshot(backend: BackendClient) -> Dictionary:
	if backend == null or not backend.has_session():
		return _failure("session_missing", "Cannot load rooms without a session")
	var profile_result: Dictionary = await backend.select_rows(
		"profiles",
		"select=*&id=eq.%s" % backend.user_id().uri_encode(),
	)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var rooms_result: Dictionary = await backend.select_rows("rooms", "select=*&order=created_at.asc")
	if not bool(rooms_result.get("ok", false)):
		return rooms_result
	var members_result: Dictionary = await backend.select_rows("room_members", "select=*&order=joined_at.asc")
	if not bool(members_result.get("ok", false)):
		return members_result
	var profiles_result: Dictionary = await backend.select_rows("profiles", "select=*")
	if not bool(profiles_result.get("ok", false)):
		return profiles_result
	return map_snapshot(
		backend.user_id(),
		_as_rows(profile_result.get("data")),
		_as_rows(rooms_result.get("data")),
		_as_rows(members_result.get("data")),
		_as_rows(profiles_result.get("data")),
	)


static func map_snapshot(
	current_user_id: String,
	profile_rows: Array,
	room_rows: Array,
	membership_rows: Array,
	visible_profile_rows: Array,
) -> Dictionary:
	if current_user_id.is_empty():
		return _failure("invalid_user", "Snapshot requires a current user")
	var profiles_by_id: Dictionary = {}
	for row in visible_profile_rows:
		if row is Dictionary:
			profiles_by_id[str((row as Dictionary).get("id", ""))] = (row as Dictionary).duplicate(true)
	var current_profile := {"user_id": current_user_id}
	if not profile_rows.is_empty() and profile_rows[0] is Dictionary:
		current_profile = _map_profile(profile_rows[0] as Dictionary, current_user_id)
	var members_by_room: Dictionary = {}
	for raw_membership in membership_rows:
		if not raw_membership is Dictionary:
			continue
		var membership := raw_membership as Dictionary
		var room_id := str(membership.get("room_id", ""))
		var user_id := str(membership.get("user_id", ""))
		if room_id.is_empty() or user_id.is_empty():
			continue
		var profile := profiles_by_id.get(user_id, {}) as Dictionary
		var room_members: Array = members_by_room.get(room_id, []) as Array
		room_members.append({
			"user_id": user_id,
			"nickname": str(profile.get("nickname", "친구")),
			"character_id": str(profile.get("character_id", "minty_pup")),
			"presence": "offline",
			"is_self": user_id == current_user_id,
			"joined_at": str(membership.get("joined_at", "")),
		})
		members_by_room[room_id] = room_members
	var mapped_rooms: Array[Dictionary] = []
	for raw_room in room_rows:
		if not raw_room is Dictionary:
			continue
		var room := raw_room as Dictionary
		var room_id := str(room.get("id", ""))
		var room_members: Array = members_by_room.get(room_id, []) as Array
		var typed_members: Array[Dictionary] = []
		for member in room_members:
			typed_members.append((member as Dictionary).duplicate(true))
		mapped_rooms.append({
			"id": room_id,
			"name": str(room.get("name", "그룹")),
			"owner_id": str(room.get("owner_id", "")),
			"invite_code_hint": str(room.get("invite_code_hint", "")),
			"invite_version": int(room.get("invite_version", 1)),
			"created_at": str(room.get("created_at", "")),
			"members": typed_members,
			"unread": 0,
		})
	return {"ok": true, "profile": current_profile, "rooms": mapped_rooms}


static func _map_profile(row: Dictionary, fallback_user_id: String) -> Dictionary:
	return {
		"user_id": str(row.get("id", fallback_user_id)),
		"nickname": str(row.get("nickname", "")),
		"character_id": str(row.get("character_id", "minty_pup")),
		"created_at": str(row.get("created_at", "")),
		"updated_at": str(row.get("updated_at", "")),
	}


static func _as_rows(value: Variant) -> Array:
	return value as Array if value is Array else []


static func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": 0,
		"data": null,
		"error_code": code,
		"error_message": message,
	}
