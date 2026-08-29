class_name RoomController
extends Node

signal profile_changed(profile: Dictionary)
signal rooms_changed(rooms: Array[Dictionary])
signal active_room_changed(previous_room_id: String, room_id: String)
signal unread_changed(room_id: String, count: int)

const MAX_ROOMS := 5
const MAX_MEMBERS := 5
const MIN_NICKNAME_LENGTH := 2
const MAX_NICKNAME_LENGTH := 12
const MIN_ROOM_NAME_LENGTH := 1
const MAX_ROOM_NAME_LENGTH := 20
const DEMO_INVITE_CODE := "SIDEY-DEMO"
const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")

var _settings_store: SettingsStore
var _profile: Dictionary = {}
var _rooms: Array[Dictionary] = []
var _active_room_id := ""
var _onboarding_complete := false


func configure(settings_store: SettingsStore) -> Error:
	_settings_store = settings_store
	var state := settings_store.local_state()
	_profile = (state.get("profile", {}) as Dictionary).duplicate(true)
	_rooms.clear()
	var saved_rooms: Array = state.get("rooms", []) as Array
	for raw_room in saved_rooms:
		if raw_room is Dictionary and _rooms.size() < MAX_ROOMS:
			var room := (raw_room as Dictionary).duplicate(true)
			if _is_valid_room_cache(room):
				_rooms.append(room)
	_active_room_id = str(state.get("active_room_id", ""))
	if not has_room(_active_room_id):
		_active_room_id = str(_rooms[0].get("id", "")) if not _rooms.is_empty() else ""
	_onboarding_complete = bool(state.get("onboarding_complete", false))
	if not has_profile() or _rooms.is_empty():
		_onboarding_complete = false
	return OK


func has_profile() -> bool:
	return not _profile.is_empty() and validate_nickname(str(_profile.get("nickname", ""))) == OK


func is_onboarding_complete() -> bool:
	return _onboarding_complete


func profile() -> Dictionary:
	return _profile.duplicate(true)


func rooms() -> Array[Dictionary]:
	return _rooms.duplicate(true)


func active_room_id() -> String:
	return _active_room_id


func active_room() -> Dictionary:
	return room_by_id(_active_room_id)


func room_by_id(room_id: String) -> Dictionary:
	for room in _rooms:
		if str(room.get("id", "")) == room_id:
			return room.duplicate(true)
	return {}


func has_room(room_id: String) -> bool:
	return not room_by_id(room_id).is_empty()


func set_profile(nickname: String, character_id: String = "minty_pup") -> Error:
	var nickname_error := validate_nickname(nickname)
	if nickname_error != OK:
		return nickname_error
	if not CharacterCatalogScript.has(character_id):
		return ERR_DOES_NOT_EXIST
	_profile = {
		"user_id": str(_profile.get("user_id", _new_local_id("user"))),
		"nickname": nickname.strip_edges(),
		"character_id": character_id,
	}
	_sync_self_member()
	var save_error := _save()
	if save_error == OK:
		profile_changed.emit(profile())
	return save_error


func create_room(room_name: String) -> Error:
	if not has_profile():
		return ERR_UNCONFIGURED
	var name_error := validate_room_name(room_name)
	if name_error != OK:
		return name_error
	if _rooms.size() >= MAX_ROOMS:
		return ERR_BUSY
	var room_id := _new_local_id("room")
	var room := {
		"id": room_id,
		"name": room_name.strip_edges(),
		"owner_id": str(_profile["user_id"]),
		"members": [_self_member()],
		"unread": 0,
		"joined_at": Time.get_unix_time_from_system(),
	}
	_rooms.append(room)
	var previous_room_id := _active_room_id
	_active_room_id = room_id
	var save_error := _save()
	if save_error == OK:
		rooms_changed.emit(rooms())
		active_room_changed.emit(previous_room_id, room_id)
	return save_error


func join_demo_room(invite_code: String) -> Error:
	if not has_profile():
		return ERR_UNCONFIGURED
	if normalize_invite_code(invite_code) != DEMO_INVITE_CODE:
		return ERR_INVALID_PARAMETER
	if _rooms.size() >= MAX_ROOMS:
		return ERR_BUSY
	if has_room("demo-friends"):
		return ERR_ALREADY_EXISTS
	var friend_names := ["하늘", "모카", "단추", "여름"]
	var members: Array[Dictionary] = [_self_member()]
	for index in friend_names.size():
		members.append({
			"user_id": "demo-user-%d" % (index + 1),
			"nickname": friend_names[index],
			"character_id": "minty_pup",
			"presence": ["online", "typing", "away", "offline"][index],
			"is_self": false,
			"joined_at": index + 1,
		})
	var room := {
		"id": "demo-friends",
		"name": "SIDEY 친구들",
		"owner_id": "demo-user-1",
		"members": members,
		"unread": 0,
		"joined_at": Time.get_unix_time_from_system(),
	}
	_rooms.append(room)
	var previous_room_id := _active_room_id
	_active_room_id = "demo-friends"
	var save_error := _save()
	if save_error == OK:
		rooms_changed.emit(rooms())
		active_room_changed.emit(previous_room_id, _active_room_id)
	return save_error


func set_active_room(room_id: String) -> Error:
	if not has_room(room_id):
		return ERR_DOES_NOT_EXIST
	if room_id == _active_room_id:
		return OK
	var previous_room_id := _active_room_id
	_active_room_id = room_id
	_set_unread_in_memory(room_id, 0)
	var save_error := _save()
	if save_error == OK:
		active_room_changed.emit(previous_room_id, room_id)
		rooms_changed.emit(rooms())
	return save_error


func rename_room(room_id: String, room_name: String) -> Error:
	var name_error := validate_room_name(room_name)
	if name_error != OK:
		return name_error
	var profile_user_id := str(_profile.get("user_id", ""))
	for index in _rooms.size():
		if str(_rooms[index].get("id", "")) != room_id:
			continue
		if str(_rooms[index].get("owner_id", "")) != profile_user_id:
			return ERR_UNAUTHORIZED
		_rooms[index]["name"] = room_name.strip_edges()
		var save_error := _save()
		if save_error == OK:
			rooms_changed.emit(rooms())
		return save_error
	return ERR_DOES_NOT_EXIST


func mark_message_received(room_id: String) -> Error:
	if not has_room(room_id):
		return ERR_DOES_NOT_EXIST
	if room_id == _active_room_id:
		return OK
	var count := unread_count(room_id) + 1
	_set_unread_in_memory(room_id, count)
	var save_error := _save()
	if save_error == OK:
		unread_changed.emit(room_id, count)
		rooms_changed.emit(rooms())
	return save_error


func unread_count(room_id: String) -> int:
	for room in _rooms:
		if str(room.get("id", "")) == room_id:
			return maxi(0, int(room.get("unread", 0)))
	return 0


func complete_onboarding() -> Error:
	if not has_profile() or _rooms.is_empty():
		return ERR_UNCONFIGURED
	_onboarding_complete = true
	return _save()


func replace_server_state(profile: Dictionary, server_rooms: Array[Dictionary]) -> Error:
	if server_rooms.size() > MAX_ROOMS:
		return ERR_INVALID_DATA
	var unread_by_room: Dictionary = {}
	for existing_room in _rooms:
		unread_by_room[str(existing_room.get("id", ""))] = int(existing_room.get("unread", 0))
	var next_rooms: Array[Dictionary] = []
	for raw_room in server_rooms:
		var room := raw_room.duplicate(true)
		room["unread"] = maxi(0, int(unread_by_room.get(str(room.get("id", "")), 0)))
		if not _is_valid_room_cache(room):
			return ERR_INVALID_DATA
		next_rooms.append(room)
	_profile = profile.duplicate(true)
	_rooms = next_rooms
	var previous_room_id := _active_room_id
	if not has_room(_active_room_id):
		_active_room_id = str(_rooms[0].get("id", "")) if not _rooms.is_empty() else ""
	_onboarding_complete = has_profile() and not _rooms.is_empty()
	var save_error := _save()
	if save_error != OK:
		return save_error
	profile_changed.emit(self.profile())
	rooms_changed.emit(rooms())
	if previous_room_id != _active_room_id:
		active_room_changed.emit(previous_room_id, _active_room_id)
	return OK


func debug_replace_rooms(next_rooms: Array[Dictionary], active_room_id: String) -> Error:
	if next_rooms.size() > MAX_ROOMS:
		return ERR_INVALID_PARAMETER
	for room in next_rooms:
		if not _is_valid_room_cache(room):
			return ERR_INVALID_DATA
	_rooms = next_rooms.duplicate(true)
	_active_room_id = active_room_id
	if not _rooms.is_empty() and not has_room(_active_room_id):
		return ERR_DOES_NOT_EXIST
	return _save()


static func validate_nickname(nickname: String) -> Error:
	var cleaned := nickname.strip_edges()
	if "\n" in cleaned or "\r" in cleaned or "\t" in cleaned:
		return ERR_INVALID_PARAMETER
	if cleaned.length() < MIN_NICKNAME_LENGTH or cleaned.length() > MAX_NICKNAME_LENGTH:
		return ERR_INVALID_PARAMETER
	return OK


static func validate_room_name(room_name: String) -> Error:
	var cleaned := room_name.strip_edges()
	if "\n" in cleaned or "\r" in cleaned or "\t" in cleaned:
		return ERR_INVALID_PARAMETER
	if cleaned.length() < MIN_ROOM_NAME_LENGTH or cleaned.length() > MAX_ROOM_NAME_LENGTH:
		return ERR_INVALID_PARAMETER
	return OK


static func normalize_invite_code(invite_code: String) -> String:
	return invite_code.strip_edges().to_upper().replace(" ", "")


func _sync_self_member() -> void:
	for room_index in _rooms.size():
		var room := _rooms[room_index]
		var members: Array = room.get("members", []) as Array
		for member_index in members.size():
			if bool((members[member_index] as Dictionary).get("is_self", false)):
				members[member_index] = _self_member()
		room["members"] = members
		_rooms[room_index] = room


func _self_member() -> Dictionary:
	return {
		"user_id": str(_profile.get("user_id", "local-user")),
		"nickname": str(_profile.get("nickname", "나")),
		"character_id": str(_profile.get("character_id", "minty_pup")),
		"presence": "online",
		"is_self": true,
		"joined_at": 0,
	}


func _set_unread_in_memory(room_id: String, count: int) -> void:
	for index in _rooms.size():
		if str(_rooms[index].get("id", "")) == room_id:
			_rooms[index]["unread"] = maxi(0, count)
			return


func _is_valid_room_cache(room: Dictionary) -> bool:
	if str(room.get("id", "")).is_empty() or validate_room_name(str(room.get("name", ""))) != OK:
		return false
	var members: Array = room.get("members", []) as Array
	if members.is_empty() or members.size() > MAX_MEMBERS:
		return false
	return true


func _save() -> Error:
	if _settings_store == null:
		return OK
	return _settings_store.set_local_state({
		"profile": _profile,
		"rooms": _rooms,
		"active_room_id": _active_room_id,
		"onboarding_complete": _onboarding_complete,
	})


func _new_local_id(prefix: String) -> String:
	return "%s-%d-%d" % [prefix, Time.get_ticks_usec(), randi()]
