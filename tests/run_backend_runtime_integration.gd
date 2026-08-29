extends SceneTree

const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const BackendRuntimeScript := preload("res://scripts/backend/backend_runtime.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")

var _failures := 0
var _settings_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := BackendConfigScript.from_environment()
	if not config.is_valid():
		push_error("BACKEND_RUNTIME_CONFIG_MISSING")
		quit(2)
		return
	_settings_path = "/tmp/sidey-backend-runtime-%d.json" % OS.get_process_id()
	var rooms := RoomControllerScript.new() as RoomController
	root.add_child(rooms)
	_check(rooms.configure(SettingsStoreScript.new(_settings_path)) == OK, "local cache configured")
	var runtime := BackendRuntimeScript.new() as BackendRuntime
	root.add_child(runtime)
	_check(runtime.configure(config, null, rooms, "runtime-%d" % OS.get_process_id()) == OK, "backend runtime configured")
	var boot: Dictionary = await runtime.start()
	_check(bool(boot.get("ok", false)), "backend runtime booted")
	_check(bool(boot.get("onboarding_required", false)), "new anonymous user requires onboarding")
	var onboarded: Dictionary = await runtime.onboard_create("런타임테스트", "minty_pup", "첫 런타임 방")
	_check(bool(onboarded.get("ok", false)), "remote onboarding created profile and room")
	_check(rooms.is_onboarding_complete(), "remote snapshot completes onboarding")
	_check(rooms.rooms().size() == 1, "remote room is in local display cache")
	var first_room_id := rooms.active_room_id()
	var renamed: Dictionary = await runtime.rename_room(first_room_id, "이름 바뀐 방")
	_check(bool(renamed.get("ok", false)), "remote room renamed")
	_check(str(rooms.room_by_id(first_room_id).get("name", "")) == "이름 바뀐 방", "renamed room resynchronized")
	var second_room: Dictionary = await runtime.create_room("두 번째 방")
	_check(bool(second_room.get("ok", false)), "second remote room created")
	_check(rooms.rooms().size() == 2, "two remote rooms are cached")
	var room_ids: Array[String] = []
	for room in rooms.rooms():
		room_ids.append(str(room.get("id", "")))
	for room_id in room_ids:
		var left: Dictionary = await runtime.leave_room(room_id)
		_check(bool(left.get("ok", false)), "integration room removed")
	_check(rooms.rooms().is_empty(), "removed rooms disappear from cache")
	runtime.queue_free()
	rooms.queue_free()
	_finish.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("BACKEND_RUNTIME_INTEGRATION_FAILED %s" % label)


func _finish() -> void:
	DirAccess.remove_absolute(_settings_path)
	if _failures == 0:
		print("SIDEY_BACKEND_RUNTIME_INTEGRATION_OK")
		quit(0)
	else:
		push_error("SIDEY_BACKEND_RUNTIME_INTEGRATION_FAILED failures=%d" % _failures)
		quit(1)
