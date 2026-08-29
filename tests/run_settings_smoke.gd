extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const PlatformBridgeScript := preload("res://scripts/platform/platform_bridge.gd")
const SettingsControllerScript := preload("res://scripts/settings/settings_controller.gd")

var _failures := 0
var _settings_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings_path = "/tmp/sidey-settings-ui-%d.json" % OS.get_process_id()
	var store := SettingsStoreScript.new(_settings_path)
	var rooms := RoomControllerScript.new() as RoomController
	root.add_child(rooms)
	_check(rooms.configure(store) == OK, "room controller configured")
	_check(rooms.set_profile("민트") == OK, "profile created")
	_check(rooms.create_room("설정 테스트") == OK, "room created")
	var platform := PlatformBridgeScript.new() as PlatformBridge
	root.add_child(platform)
	var settings := SettingsControllerScript.new() as SettingsController
	root.add_child(settings)
	settings.configure(rooms, platform)
	settings.open()
	var window := settings.get_node_or_null("SettingsWindow") as Window
	_check(window != null, "settings creates window")
	if window != null:
		_check(not window.transparent, "settings is opaque")
		_check(not window.borderless, "settings has normal window frame")
		_check(not window.always_on_top, "settings is not overlay")
		_check(window.size.x >= 640 and window.size.y >= 720, "settings has a readable layout size")
		_check(window.theme != null and window.theme.default_font_size >= 18, "settings uses large typography")
		_check(window.find_children("*", "ScrollContainer", true, false).size() >= 1, "settings scrolls on smaller screens")
		_check(window.find_children("*", "PanelContainer", true, false).size() >= 5, "settings uses grouped card sections")
		_check(window.find_children("*", "OptionButton", true, false).size() >= 2, "settings has character and room pickers")
		_check(window.find_children("*", "CheckBox", true, false).size() == 1, "settings has launch-at-login control")
		var button_labels: Array[String] = []
		for button in window.find_children("*", "Button", true, false):
			button_labels.append((button as Button).text)
		_check("재발급" in button_labels, "settings has invite rotation control")
		_check("이 그룹에서 나가기" in button_labels, "settings has room leave control")
		var title := _find_label(window, "SIDEY 설정")
		_check(title != null and title.get_theme_font_size("font_size") >= 32, "settings title is prominent")
		var capture_path := _argument_value("--capture=")
		if not capture_path.is_empty():
			await process_frame
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_path) == OK, "settings capture saved")
	settings.close()
	settings.queue_free()
	platform.queue_free()
	rooms.queue_free()
	_finish.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("SETTINGS_UI_TEST_FAILED %s" % label)


func _find_label(window: Window, text: String) -> Label:
	for node in window.find_children("*", "Label", true, false):
		var label := node as Label
		if label.text == text:
			return label
	return null


func _argument_value(prefix: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _finish() -> void:
	DirAccess.remove_absolute(_settings_path)
	if _failures == 0:
		print("SIDEY_SETTINGS_SMOKE_OK")
		quit(0)
	else:
		push_error("SIDEY_SETTINGS_SMOKE_FAILED failures=%d" % _failures)
		quit(1)
