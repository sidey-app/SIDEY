class_name CharacterState
extends RefCounted

enum Value {
	ONLINE_IDLE,
	TYPING,
	OFFLINE_SLEEP,
}


static func label(state: Value) -> StringName:
	match state:
		Value.ONLINE_IDLE:
			return &"ONLINE_IDLE"
		Value.TYPING:
			return &"TYPING"
		Value.OFFLINE_SLEEP:
			return &"OFFLINE_SLEEP"
		_:
			return &"UNKNOWN"
