extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const OnboardingControllerScript := preload("res://scripts/onboarding/onboarding_controller.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")

var _failures := 0
var _settings_path := ""
var _completed_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings_path = "/tmp/sidey-onboarding-%d.json" % OS.get_process_id()
	var room_controller := RoomControllerScript.new() as RoomController
	root.add_child(room_controller)
	_check(room_controller.configure(SettingsStoreScript.new(_settings_path)) == OK, "room controller configured")
	var onboarding := OnboardingControllerScript.new() as OnboardingController
	root.add_child(onboarding)
	onboarding.completed.connect(func() -> void: _completed_count += 1)
	onboarding.show_onboarding(room_controller)
	var window := onboarding.get_node_or_null("OnboardingWindow") as Window
	_check(window != null, "onboarding creates window")
	if window != null:
		_check(not window.transparent, "onboarding is opaque")
		_check(not window.borderless, "onboarding has normal window frame")
		_check(not window.always_on_top, "onboarding is not an overlay")
		_check(
			OnboardingControllerScript.WINDOW_SIZE == Vector2i(960, 720),
			"onboarding requests a spacious default size",
		)
		_check(
			window.size.x >= window.min_size.x and window.size.y >= window.min_size.y,
			"onboarding respects its minimum size after display clamping",
		)
		var display_scale := SideyThemeScript.standard_window_scale(window.current_screen)
		var expected_min_size := SideyThemeScript.scaled_window_size(Vector2i(820, 620), display_scale)
		_check(window.min_size == expected_min_size, "onboarding scales its minimum size for HiDPI")
		_check(window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "onboarding uses application-style content scaling")
		_check(is_equal_approx(window.content_scale_factor, display_scale), "onboarding content follows the display scale")
		_check(window.theme != null and window.theme.default_font_size >= 20, "onboarding uses large typography")
		_check(window.find_children("*", "ScrollContainer", true, false).size() >= 1, "onboarding scrolls on smaller screens")
		_check(window.find_children("*", "PanelContainer", true, false).size() >= 2, "onboarding uses card sections")
		_check(window.find_children("*", "LineEdit", true, false).size() >= 3, "onboarding has profile and room inputs")
		var title := _find_label(window, "친구들을 화면 곁으로")
		_check(title != null and title.get_theme_font_size("font_size") >= 38, "onboarding title is prominent")
		var steps := window.find_child("OnboardingSteps", true, false) as TabContainer
		var progress := window.find_child("OnboardingProgress", true, false) as Label
		_check(steps != null and steps.current_tab == 0, "onboarding starts on the profile step")
		_check(progress != null and progress.text.begins_with("1 / 2"), "onboarding shows profile progress")
		var capture_path := _argument_value("--capture=")
		if not capture_path.is_empty():
			await process_frame
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_path) == OK, "onboarding capture saved")
		var nickname_edit := window.find_child("NicknameEdit", true, false) as LineEdit
		var next_button := window.find_child("OnboardingNextButton", true, false) as Button
		nickname_edit.text = "한"
		next_button.pressed.emit()
		await process_frame
		_check(steps.current_tab == 0, "invalid profile cannot advance")
		var error_banner := window.find_child("OnboardingErrorBanner", true, false) as PanelContainer
		_check(error_banner.visible, "profile validation uses the inline error banner")
		nickname_edit.text = "민트"
		next_button.pressed.emit()
		await process_frame
		_check(steps.current_tab == 1, "valid profile advances to the group step")
		_check(progress.text.begins_with("2 / 2"), "onboarding shows group progress")
		var group_forms := window.find_child("GroupEntryForms", true, false) as TabContainer
		_check(group_forms != null and group_forms.current_tab == 0, "group creation is selected by default")
		var join_mode_button := window.find_child("JoinGroupModeButton", true, false) as Button
		join_mode_button.pressed.emit()
		await process_frame
		_check(group_forms.current_tab == 1, "group entry tabs switch to invite join")
		var invite_edit := window.find_child("InviteCodeEdit", true, false) as LineEdit
		invite_edit.text = "SIDEY-DEMO"
		var visible_back_button: Button
		for candidate in window.find_children("OnboardingBackButton", "Button", true, false):
			var button := candidate as Button
			if button.is_visible_in_tree():
				visible_back_button = button
				break
		_check(visible_back_button != null, "group step has a visible back button")
		visible_back_button.pressed.emit()
		await process_frame
		_check(steps.current_tab == 0 and nickname_edit.text == "민트", "back keeps the profile draft")
		next_button.pressed.emit()
		await process_frame
		_check(group_forms.current_tab == 1 and invite_edit.text == "SIDEY-DEMO", "group tab and draft survive back navigation")
		var capture_group_path := _argument_value("--capture-step2=")
		if not capture_group_path.is_empty():
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_group_path) == OK, "onboarding group capture saved")
		var capture_min_path := _argument_value("--capture-min=")
		if not capture_min_path.is_empty():
			window.size = window.min_size
			await process_frame
			await RenderingServer.frame_post_draw
			_check(window.get_texture().get_image().save_png(capture_min_path) == OK, "onboarding minimum-size capture saved")
		var group_submit_button := window.find_child("GroupSubmitButton", true, false) as Button
		group_submit_button.pressed.emit()
		await process_frame
		_check(room_controller.is_onboarding_complete(), "group submission completes onboarding")
		_check(_completed_count == 1, "onboarding completion is emitted once")
		_check(onboarding.get_node_or_null("OnboardingWindow") == null, "completed onboarding closes before routing onward")
		onboarding.show_onboarding(room_controller)
		await process_frame
		_check(onboarding.get_node_or_null("OnboardingWindow") == null, "completed onboarding cannot reopen at profile step")
	room_controller.queue_free()
	finish.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ONBOARDING_TEST_FAILED %s" % label)


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


func finish() -> void:
	DirAccess.remove_absolute(_settings_path)
	if _failures == 0:
		print("SIDEY_ONBOARDING_SMOKE_OK")
		quit(0)
	else:
		push_error("SIDEY_ONBOARDING_SMOKE_FAILED failures=%d" % _failures)
		quit(1)
