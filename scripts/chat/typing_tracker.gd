class_name TypingTracker
extends RefCounted

const KEEPALIVE_SECONDS := 2.0
const EXPIRE_SECONDS := 4.0

var _active := false
var _last_input_at := 0.0
var _last_sent_at := 0.0


func note_input(now: float) -> StringName:
	_last_input_at = now
	if _active:
		return &""
	_active = true
	_last_sent_at = now
	return &"typing_start"


func poll(now: float) -> StringName:
	if not _active:
		return &""
	if now - _last_input_at >= EXPIRE_SECONDS:
		_active = false
		return &"typing_stop"
	if now - _last_sent_at >= KEEPALIVE_SECONDS:
		_last_sent_at = now
		return &"typing_keepalive"
	return &""


func stop() -> bool:
	var was_active := _active
	_active = false
	return was_active


func is_active() -> bool:
	return _active
