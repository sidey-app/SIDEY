class_name ReconnectBackoff
extends RefCounted

const BASE_DELAYS := [1.0, 2.0, 4.0, 8.0, 15.0]
const JITTER_MIN := 0.85
const JITTER_MAX := 1.15

var _attempt := 0


func next_delay(jitter_unit := -1.0) -> float:
	var base_delay: float = BASE_DELAYS[mini(_attempt, BASE_DELAYS.size() - 1)]
	_attempt += 1
	var unit := randf() if jitter_unit < 0.0 else clampf(jitter_unit, 0.0, 1.0)
	return base_delay * lerpf(JITTER_MIN, JITTER_MAX, unit)


func reset() -> void:
	_attempt = 0


func attempt() -> int:
	return _attempt
