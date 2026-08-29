extends SceneTree

const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const BackendClientScript := preload("res://scripts/backend/backend_client.gd")
const PlatformBridgeScript := preload("res://scripts/platform/platform_bridge.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.get_name() != "macOS":
		print("SIDEY_BACKEND_KEYCHAIN_SKIPPED os=%s" % OS.get_name())
		quit(0)
		return
	var config := BackendConfigScript.from_environment()
	if not config.is_valid():
		push_error("BACKEND_KEYCHAIN_CONFIG_MISSING")
		quit(2)
		return
	var platform := PlatformBridgeScript.new() as PlatformBridge
	root.add_child(platform)
	_check(platform.is_native_available(), "native Keychain bridge is available")
	var profile_name := "keychain-integration-%d" % OS.get_process_id()
	var first := BackendClientScript.new() as BackendClient
	root.add_child(first)
	_check(first.configure(config, platform, profile_name) == OK, "first client configured")
	first.clear_session()
	var created: Dictionary = await first.create_anonymous_session()
	_check(bool(created.get("ok", false)), "anonymous session created")
	var original_user_id := first.user_id()
	_check(not original_user_id.is_empty(), "created session has user id")
	var restored_client := BackendClientScript.new() as BackendClient
	root.add_child(restored_client)
	_check(restored_client.configure(config, platform, profile_name) == OK, "restore client configured")
	var restored: Dictionary = await restored_client.restore_or_create_session()
	_check(bool(restored.get("ok", false)), "Keychain refresh token restores session")
	_check(restored_client.user_id() == original_user_id, "restored session keeps anonymous user identity")
	_check(restored_client.clear_session() == OK, "Keychain refresh token deleted")
	var replacement_client := BackendClientScript.new() as BackendClient
	root.add_child(replacement_client)
	_check(replacement_client.configure(config, platform, profile_name) == OK, "replacement client configured")
	var replacement: Dictionary = await replacement_client.restore_or_create_session()
	_check(bool(replacement.get("ok", false)), "new anonymous session created after token deletion")
	_check(replacement_client.user_id() != original_user_id, "deleted refresh token cannot recover old identity")
	replacement_client.clear_session()
	first.queue_free()
	restored_client.queue_free()
	replacement_client.queue_free()
	platform.queue_free()
	_finish.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BACKEND_KEYCHAIN_INTEGRATION_FAILED %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("SIDEY_BACKEND_KEYCHAIN_INTEGRATION_OK")
		quit(0)
	else:
		push_error("SIDEY_BACKEND_KEYCHAIN_INTEGRATION_FAILED failures=%d" % _failures)
		quit(1)
