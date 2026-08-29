class_name ActivityPresence
extends RefCounted

const DEFAULT_IDLE_THRESHOLD_SECONDS := 300.0


static func state(
	screen_locked: bool,
	system_sleeping: bool,
	idle_seconds: float,
	idle_threshold_seconds := DEFAULT_IDLE_THRESHOLD_SECONDS,
) -> String:
	if screen_locked or system_sleeping or idle_seconds >= idle_threshold_seconds:
		return "away"
	return "online"
