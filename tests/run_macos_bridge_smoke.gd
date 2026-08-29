extends SceneTree

var _failures := 0
var _shortcut_action := StringName()


func _initialize() -> void:
	if OS.get_name() != "macOS":
		print("SIDEY_MACOS_BRIDGE_SMOKE_SKIPPED os=%s" % OS.get_name())
		quit(0)
		return
	_check(ClassDB.class_exists("SideyMacOSBridge"), "native class registered")
	if _failures > 0:
		_finish()
		return
	var instance: Object = ClassDB.instantiate("SideyMacOSBridge")
	_check(instance is Node, "native class creates node")
	if not instance is Node:
		_finish()
		return
	var bridge := instance as Node
	root.add_child(bridge)
	var report: Dictionary = bridge.call("capability_report")
	_check(bool(report.get("secure_storage", false)), "Keychain capability")
	_check(bool(report.get("system_idle_time", false)), "idle capability")
	_check(float(bridge.call("get_idle_seconds")) >= 0.0, "idle seconds non-negative")
	bridge.connect("global_shortcut_pressed", _on_global_shortcut)
	bridge.call("dispatch_hotkey", 1)
	_check(_shortcut_action == &"compose", "hotkey dispatch signal")

	var account := "native-smoke-%d" % OS.get_process_id()
	var secret := "sidey-smoke-secret"
	bridge.call("keychain_delete", account)
	_check(int(bridge.call("keychain_store", account, secret)) == OK, "Keychain write")
	_check(str(bridge.call("keychain_read", account)) == secret, "Keychain read")
	_check(int(bridge.call("keychain_delete", account)) == OK, "Keychain delete")
	_check(str(bridge.call("keychain_read", account)).is_empty(), "Keychain deletion verified")
	bridge.queue_free()
	_finish()


func _on_global_shortcut(action: StringName) -> void:
	_shortcut_action = action


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("MACOS_BRIDGE_TEST_FAILED %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("SIDEY_MACOS_BRIDGE_SMOKE_OK")
		quit(0)
	else:
		push_error("SIDEY_MACOS_BRIDGE_SMOKE_FAILED failures=%d" % _failures)
		quit(1)
