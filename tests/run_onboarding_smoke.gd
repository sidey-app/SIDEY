extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const OnboardingControllerScript := preload("res://scripts/onboarding/onboarding_controller.gd")

var _failures := 0
var _settings_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings_path = "/tmp/sidey-onboarding-%d.json" % OS.get_process_id()
	var room_controller := RoomControllerScript.new() as RoomController
	root.add_child(room_controller)
	_check(room_controller.configure(SettingsStoreScript.new(_settings_path)) == OK, "room controller configured")
	var onboarding := OnboardingControllerScript.new() as OnboardingController
	root.add_child(onboarding)
	onboarding.show_onboarding(room_controller)
	var window := onboarding.get_node_or_null("OnboardingWindow") as Window
	_check(window != null, "onboarding creates window")
	if window != null:
		_check(not window.transparent, "onboarding is opaque")
		_check(not window.borderless, "onboarding has normal window frame")
		_check(not window.always_on_top, "onboarding is not an overlay")
		_check(window.size.x >= 460 and window.size.y >= 440, "onboarding minimum layout size")
		_check(window.find_children("*", "LineEdit", true, false).size() >= 3, "onboarding has profile and room inputs")
	onboarding.close()
	room_controller.queue_free()
	finish.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ONBOARDING_TEST_FAILED %s" % label)


func finish() -> void:
	DirAccess.remove_absolute(_settings_path)
	if _failures == 0:
		print("SIDEY_ONBOARDING_SMOKE_OK")
		quit(0)
	else:
		push_error("SIDEY_ONBOARDING_SMOKE_FAILED failures=%d" % _failures)
		quit(1)
