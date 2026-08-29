class_name PlatformBridge
extends Node

signal screen_lock_changed(locked: bool)
signal system_sleep_changed(sleeping: bool)
signal system_resumed
signal global_shortcut_pressed(action: StringName)


func capability_report() -> Dictionary:
	return {
		"native_bridge": false,
		"secure_storage": false,
		"system_idle_time": false,
		"screen_lock_events": false,
		"global_shortcuts": false,
		"launch_at_login": false,
		"all_spaces_window_policy": false,
		"dockless_activation_policy": false,
	}


func set_overlay_runtime_mode(_enabled: bool) -> Error:
	return ERR_UNAVAILABLE


func set_all_spaces_window_policy(_enabled: bool) -> Error:
	return ERR_UNAVAILABLE
