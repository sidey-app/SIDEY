extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const PlatformBridgeScript := preload("res://scripts/platform/platform_bridge.gd")
const SettingsControllerScript := preload("res://scripts/settings/settings_controller.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")

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
		_check(
			SettingsControllerScript.WINDOW_SIZE == Vector2i(1000, 760),
			"settings requests a spacious default size",
		)
		_check(
			window.size.x >= window.min_size.x and window.size.y >= window.min_size.y,
			"settings respects its minimum size after display clamping",
		)
		var display_scale := SideyThemeScript.standard_window_scale(window.current_screen)
		var expected_min_size := SideyThemeScript.scaled_window_size(Vector2i(860, 640), display_scale)
		_check(window.min_size == expected_min_size, "settings scales its minimum size for HiDPI")
		_check(window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "settings uses application-style content scaling")
		_check(is_equal_approx(window.content_scale_factor, display_scale), "settings content follows the display scale")
		_check(window.theme != null and window.theme.default_font_size >= 20, "settings uses large typography")
		_check(window.find_child("SettingsSidebar", true, false) != null, "settings has a fixed sidebar")
		_check(window.find_children("SettingsNavigation*", "Button", true, false).size() == 3, "settings has three navigation entries")
		_check(window.find_children("*", "ScrollContainer", true, false).size() >= 3, "each settings page can scroll independently")
		_check(window.find_children("*", "PanelContainer", true, false).size() >= 5, "settings uses grouped card sections")
		_check(window.find_children("*", "OptionButton", true, false).size() >= 2, "settings has character and room pickers")
		_check(window.find_children("*", "CheckBox", true, false).size() == 1, "settings has launch-at-login control")
		var button_labels: Array[String] = []
		for button in window.find_children("*", "Button", true, false):
			button_labels.append((button as Button).text)
		_check("재발급" in button_labels, "settings has invite rotation control")
		_check("이 그룹에서 나가기" in button_labels, "settings has room leave control")
		var title := window.find_child("SettingsPageTitle", true, false) as Label
		_check(title != null and title.text == "내 프로필", "settings opens on profile")
		_check(title != null and title.get_theme_font_size("font_size") >= 34, "settings title is prominent")
		var pages := window.find_child("SettingsPages", true, false) as TabContainer
		_check(pages != null and pages.current_tab == 0, "profile page is selected by default")
		var capture_path := _argument_value("--capture=")
		if not capture_path.is_empty():
			await process_frame
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_path) == OK, "settings capture saved")
		var group_navigation := window.find_child("SettingsNavigation1", true, false) as Button
		group_navigation.pressed.emit()
		await process_frame
		_check(pages.current_tab == 1 and title.text == "그룹", "sidebar changes the active settings page")
		_check(group_navigation.theme_type_variation == &"SideyNavigationButtonSelected", "active navigation is highlighted")
		var capture_group_path := _argument_value("--capture-group=")
		if not capture_group_path.is_empty():
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_group_path) == OK, "settings group capture saved")
		var profile_navigation := window.find_child("SettingsNavigation0", true, false) as Button
		profile_navigation.pressed.emit()
		var nickname_edit := window.find_child("NicknameEdit", true, false) as LineEdit
		nickname_edit.text = "한"
		var save_profile_button := window.find_child("SaveProfileButton", true, false) as Button
		save_profile_button.pressed.emit()
		var feedback := window.find_child("SettingsFeedbackBanner", true, false) as PanelContainer
		_check(feedback.visible, "settings shows inline action feedback")
		var capture_min_path := _argument_value("--capture-min=")
		if not capture_min_path.is_empty():
			window.size = window.min_size
			await process_frame
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_min_path) == OK, "settings minimum-size capture saved")
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
