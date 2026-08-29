class_name PlatformBridge
extends Node

signal screen_lock_changed(locked: bool)
signal system_sleep_changed(sleeping: bool)
signal system_resumed
signal global_shortcut_pressed(action: StringName)
signal local_enter_pressed(shift_pressed: bool)

var _native_bridge: Node


func _ready() -> void:
	if OS.get_name() != "macOS" or not ClassDB.class_exists("SideyMacOSBridge"):
		return
	var instance: Object = ClassDB.instantiate("SideyMacOSBridge")
	if not instance is Node:
		push_warning("PLATFORM_BRIDGE_INVALID_NATIVE_CLASS")
		return
	_native_bridge = instance as Node
	_native_bridge.name = "SideyMacOSBridge"
	add_child(_native_bridge)
	_native_bridge.connect("screen_lock_changed", _forward_screen_lock)
	_native_bridge.connect("system_sleep_changed", _forward_system_sleep)
	_native_bridge.connect("system_resumed", _forward_system_resumed)
	_native_bridge.connect("global_shortcut_pressed", _forward_global_shortcut)
	_native_bridge.connect("local_enter_pressed", _forward_local_enter)


func is_native_available() -> bool:
	return is_instance_valid(_native_bridge)


func capability_report() -> Dictionary:
	var report := {
		"native_bridge": false,
		"secure_storage": false,
		"system_idle_time": false,
		"screen_lock_events": false,
		"sleep_wake_events": false,
		"global_shortcuts": false,
		"launch_at_login": false,
		"all_spaces_window_policy": false,
		"dockless_activation_policy": false,
		"local_enter_events": false,
	}
	if is_native_available():
		report.merge(_native_bridge.call("capability_report"), true)
	return report


func store_secret(account: String, secret: String) -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("keychain_store", account, secret))


func read_secret(account: String) -> String:
	if not is_native_available():
		return ""
	return str(_native_bridge.call("keychain_read", account))


func delete_secret(account: String) -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("keychain_delete", account))


func get_idle_seconds() -> float:
	if not is_native_available():
		return 0.0
	return float(_native_bridge.call("get_idle_seconds"))


func is_screen_locked() -> bool:
	if not is_native_available():
		return false
	return bool(_native_bridge.call("is_screen_locked"))


func register_default_hotkeys() -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("register_default_hotkeys"))


func unregister_hotkeys() -> void:
	if is_native_available():
		_native_bridge.call("unregister_hotkeys")


func set_overlay_runtime_mode(_enabled: bool) -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("set_overlay_runtime_mode", _enabled))


func set_all_spaces_window_policy(_enabled: bool) -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("set_all_spaces_window_policy", _enabled))


func set_ignores_mouse_events(enabled: bool) -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("set_ignores_mouse_events", enabled))


func set_launch_at_login(enabled: bool) -> Error:
	if not is_native_available():
		return ERR_UNAVAILABLE
	return int(_native_bridge.call("set_launch_at_login", enabled))


func is_launch_at_login_enabled() -> bool:
	if not is_native_available():
		return false
	return bool(_native_bridge.call("is_launch_at_login_enabled"))


func supports_local_enter_events() -> bool:
	return bool(capability_report().get("local_enter_events", false))


func set_local_enter_monitor_enabled(enabled: bool) -> void:
	if is_native_available() and supports_local_enter_events():
		_native_bridge.call("set_local_enter_monitor_enabled", enabled)


func _forward_screen_lock(locked: bool) -> void:
	screen_lock_changed.emit(locked)


func _forward_system_sleep(sleeping: bool) -> void:
	system_sleep_changed.emit(sleeping)


func _forward_system_resumed() -> void:
	system_resumed.emit()


func _forward_global_shortcut(action: StringName) -> void:
	global_shortcut_pressed.emit(action)


func _forward_local_enter(shift_pressed: bool) -> void:
	local_enter_pressed.emit(shift_pressed)
