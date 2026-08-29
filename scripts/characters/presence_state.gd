class_name PresenceState
extends RefCounted

enum Value {
	ONLINE,
	AWAY,
	OFFLINE,
	RECONNECTING,
	TYPING,
}


static func from_string(value: String) -> Value:
	match value:
		"online":
			return Value.ONLINE
		"away":
			return Value.AWAY
		"reconnecting":
			return Value.RECONNECTING
		"typing":
			return Value.TYPING
		_:
			return Value.OFFLINE


static func to_string_name(value: Value) -> StringName:
	match value:
		Value.ONLINE:
			return &"online"
		Value.AWAY:
			return &"away"
		Value.RECONNECTING:
			return &"reconnecting"
		Value.TYPING:
			return &"typing"
		_:
			return &"offline"


static func motion_state(value: Value) -> CharacterState.Value:
	if value == Value.ONLINE:
		return CharacterState.Value.ONLINE_IDLE
	if value == Value.TYPING:
		return CharacterState.Value.TYPING
	return CharacterState.Value.OFFLINE_SLEEP


static func indicator_color(value: Value) -> Color:
	match value:
		Value.ONLINE, Value.TYPING:
			return Color("56d89b")
		Value.AWAY:
			return Color("f2ad55")
		_:
			return Color("8c949e")
