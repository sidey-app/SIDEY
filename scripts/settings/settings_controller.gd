class_name SettingsController
extends Node

signal opened
signal closed

const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const WINDOW_SIZE := Vector2i(1000, 760)
const WINDOW_MIN_SIZE := Vector2i(860, 640)

enum SettingsPage {
	PROFILE,
	GROUPS,
	APP,
}

var _room_controller: RoomController
var _platform_bridge: PlatformBridge
var _window: Window
var _nickname_edit: LineEdit
var _character_picker: OptionButton
var _room_picker: OptionButton
var _room_name_edit: LineEdit
var _new_room_edit: LineEdit
var _invite_code_edit: LineEdit
var _launch_at_login: CheckBox
var _feedback: Label
var _invite_code_display: LineEdit
var _copy_invite_button: Button
var _rotate_invite_button: Button
var _leave_room_button: Button
var _members_list: VBoxContainer
var _page_container: TabContainer
var _page_title: Label
var _page_description: Label
var _feedback_panel: PanelContainer
var _navigation_buttons: Array[Button] = []
var _character_ids: Array[String] = []
var _room_ids: Array[String] = []
var _backend_runtime: BackendRuntime
var _active_page := SettingsPage.PROFILE


func configure(
	room_controller: RoomController,
	platform_bridge: PlatformBridge,
	backend_runtime: BackendRuntime = null,
) -> void:
	_room_controller = room_controller
	_platform_bridge = platform_bridge
	_backend_runtime = backend_runtime
	_room_controller.rooms_changed.connect(_on_rooms_changed)
	_room_controller.active_room_changed.connect(_on_active_room_changed)


func open() -> void:
	if not is_instance_valid(_window):
		_build_window()
	_refresh_profile()
	_refresh_rooms()
	_show_settings_page(_active_page)
	opened.emit()
	_window.popup_centered()


func open_groups() -> void:
	_active_page = SettingsPage.GROUPS
	open()


func close() -> void:
	if is_instance_valid(_window):
		_window.hide()
	closed.emit()


func _build_window() -> void:
	_window = Window.new()
	_window.name = "SettingsWindow"
	_window.title = "SIDEY 설정"
	_apply_window_scale(true)
	_window.transparent = false
	_window.borderless = false
	_window.always_on_top = false
	_window.unresizable = false
	_window.transient = false
	_window.theme = SideyThemeScript.create_standard_window_theme()
	_window.close_requested.connect(close)
	_window.dpi_changed.connect(_on_window_dpi_changed)
	add_child(_window)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = SideyThemeScript.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(background)
	var layout := HBoxContainer.new()
	layout.name = "SettingsLayout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	_window.add_child(layout)
	_build_sidebar(layout)
	_build_content(layout)
	_show_settings_page(SettingsPage.PROFILE, false)


func _apply_window_scale(resize_window: bool) -> void:
	var display_scale := SideyThemeScript.standard_window_scale(_window.current_screen)
	_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_window.content_scale_factor = display_scale
	_window.min_size = SideyThemeScript.scaled_window_size(WINDOW_MIN_SIZE, display_scale)
	if resize_window:
		_window.size = SideyThemeScript.scaled_window_size(WINDOW_SIZE, display_scale)


func _on_window_dpi_changed() -> void:
	_apply_window_scale(false)


func _build_sidebar(parent: HBoxContainer) -> void:
	var sidebar := ColorRect.new()
	sidebar.name = "SettingsSidebar"
	sidebar.color = SideyThemeScript.FIELD
	sidebar.custom_minimum_size.x = 240
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(sidebar)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	sidebar.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var brand := Label.new()
	brand.text = "SIDEY"
	brand.add_theme_font_size_override("font_size", 28)
	stack.add_child(brand)
	var section_label := Label.new()
	section_label.text = "설정"
	section_label.add_theme_font_size_override("font_size", 17)
	section_label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	stack.add_child(section_label)
	var nav_spacer := Control.new()
	nav_spacer.custom_minimum_size.y = 16
	stack.add_child(nav_spacer)
	_add_navigation_button(stack, "내 프로필", SettingsPage.PROFILE)
	_add_navigation_button(stack, "그룹", SettingsPage.GROUPS)
	_add_navigation_button(stack, "앱 설정", SettingsPage.APP)
	var flexible_spacer := Control.new()
	flexible_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(flexible_spacer)
	var close_button := Button.new()
	close_button.name = "CloseSettingsButton"
	close_button.text = "닫기"
	close_button.theme_type_variation = &"SideySecondaryButton"
	close_button.custom_minimum_size.y = 54
	close_button.pressed.connect(close)
	stack.add_child(close_button)


func _add_navigation_button(parent: VBoxContainer, text: String, page: SettingsPage) -> void:
	var button := Button.new()
	button.name = "SettingsNavigation%d" % page
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 54
	button.theme_type_variation = &"SideyNavigationButton"
	button.pressed.connect(_show_settings_page.bind(page))
	parent.add_child(button)
	_navigation_buttons.append(button)


func _build_content(parent: HBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.name = "SettingsContent"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	parent.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)
	_page_title = Label.new()
	_page_title.name = "SettingsPageTitle"
	_page_title.add_theme_font_size_override("font_size", 34)
	stack.add_child(_page_title)
	_page_description = Label.new()
	_page_description.name = "SettingsPageDescription"
	_page_description.add_theme_font_size_override("font_size", 18)
	_page_description.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	stack.add_child(_page_description)
	_build_feedback_banner(stack)
	_page_container = TabContainer.new()
	_page_container.name = "SettingsPages"
	_page_container.tabs_visible = false
	_page_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_page_container)
	_build_profile_page()
	_build_groups_page()
	_build_app_page()


func _build_feedback_banner(parent: VBoxContainer) -> void:
	_feedback_panel = PanelContainer.new()
	_feedback_panel.name = "SettingsFeedbackBanner"
	_feedback_panel.visible = false
	parent.add_child(_feedback_panel)
	_feedback = Label.new()
	_feedback.name = "SettingsFeedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_panel.add_child(_feedback)


func _build_profile_page() -> void:
	var content := _add_page_scroll("ProfilePage")
	var profile_card := _add_card(content, "프로필 정보", "모든 그룹에 같은 프로필이 표시돼요.")
	profile_card.add_child(_field_label("닉네임"))
	_nickname_edit = LineEdit.new()
	_nickname_edit.name = "NicknameEdit"
	_nickname_edit.placeholder_text = "2~12자로 입력해주세요"
	_nickname_edit.max_length = RoomController.MAX_NICKNAME_LENGTH
	_nickname_edit.custom_minimum_size.y = 58
	profile_card.add_child(_nickname_edit)
	profile_card.add_child(_field_label("캐릭터"))
	_character_picker = OptionButton.new()
	_character_picker.name = "CharacterPicker"
	_character_ids.clear()
	for entry in CharacterCatalogScript.all():
		_character_ids.append(str(entry["id"]))
		_character_picker.add_item(str(entry["display_name"]))
	_character_picker.custom_minimum_size.y = 58
	profile_card.add_child(_character_picker)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_END
	profile_card.add_child(action_row)
	var save_profile_button := Button.new()
	save_profile_button.name = "SaveProfileButton"
	save_profile_button.text = "저장"
	save_profile_button.custom_minimum_size = Vector2(132, 58)
	save_profile_button.pressed.connect(_save_profile)
	action_row.add_child(save_profile_button)


func _build_groups_page() -> void:
	var content := _add_page_scroll("GroupsPage")
	var active_card := _add_card(content, "현재 그룹", "오버레이에는 선택한 그룹의 친구만 보여요.")
	active_card.add_child(_field_label("지금 볼 그룹"))
	_room_picker = OptionButton.new()
	_room_picker.name = "RoomPicker"
	_room_picker.custom_minimum_size.y = 58
	_room_picker.item_selected.connect(_select_room)
	active_card.add_child(_room_picker)
	active_card.add_child(_field_label("그룹 이름"))
	var rename_row := HBoxContainer.new()
	rename_row.add_theme_constant_override("separation", 10)
	_room_name_edit = LineEdit.new()
	_room_name_edit.name = "RoomNameEdit"
	_room_name_edit.placeholder_text = "방장만 변경할 수 있어요"
	_room_name_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_room_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_name_edit.custom_minimum_size.y = 58
	rename_row.add_child(_room_name_edit)
	var rename_button := Button.new()
	rename_button.text = "이름 변경"
	rename_button.theme_type_variation = &"SideySecondaryButton"
	rename_button.custom_minimum_size = Vector2(132, 58)
	rename_button.pressed.connect(_rename_active_room)
	rename_row.add_child(rename_button)
	active_card.add_child(rename_row)
	var add_card := _add_card(content, "새 그룹 추가", "그룹은 최대 5개까지 참여할 수 있어요.")
	add_card.add_child(_field_label("새 그룹 만들기"))
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 10)
	_new_room_edit = LineEdit.new()
	_new_room_edit.name = "NewRoomEdit"
	_new_room_edit.placeholder_text = "새 그룹 이름"
	_new_room_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_new_room_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_room_edit.custom_minimum_size.y = 58
	create_row.add_child(_new_room_edit)
	var create_button := Button.new()
	create_button.text = "만들기"
	create_button.custom_minimum_size = Vector2(132, 58)
	create_button.pressed.connect(_create_room)
	create_row.add_child(create_button)
	add_card.add_child(create_row)
	add_card.add_child(_field_label("초대 코드로 참여"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_invite_code_edit = LineEdit.new()
	_invite_code_edit.name = "InviteCodeEdit"
	_invite_code_edit.placeholder_text = "초대 코드"
	_invite_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_code_edit.custom_minimum_size.y = 58
	join_row.add_child(_invite_code_edit)
	var join_button := Button.new()
	join_button.text = "코드로 참여"
	join_button.theme_type_variation = &"SideySecondaryButton"
	join_button.custom_minimum_size = Vector2(132, 58)
	join_button.pressed.connect(_join_room)
	join_row.add_child(join_button)
	add_card.add_child(join_row)
	if OS.is_debug_build():
		var demo_help := Label.new()
		demo_help.text = "개발용 코드: SIDEY-DEMO"
		demo_help.add_theme_font_size_override("font_size", 15)
		demo_help.add_theme_color_override("font_color", SideyThemeScript.SUCCESS)
		add_card.add_child(demo_help)
	var manage_card := _add_card(content, "초대와 멤버", "초대 코드는 방장만 새로 발급할 수 있어요.")
	manage_card.add_child(_field_label("현재 초대 코드"))
	var invite_row := HBoxContainer.new()
	invite_row.add_theme_constant_override("separation", 10)
	_invite_code_display = LineEdit.new()
	_invite_code_display.placeholder_text = "초대 코드 원문 없음"
	_invite_code_display.editable = false
	_invite_code_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_code_display.custom_minimum_size.y = 58
	invite_row.add_child(_invite_code_display)
	_copy_invite_button = Button.new()
	_copy_invite_button.text = "복사"
	_copy_invite_button.theme_type_variation = &"SideySecondaryButton"
	_copy_invite_button.custom_minimum_size = Vector2(88, 58)
	_copy_invite_button.pressed.connect(_copy_invite_code)
	invite_row.add_child(_copy_invite_button)
	_rotate_invite_button = Button.new()
	_rotate_invite_button.text = "재발급"
	_rotate_invite_button.theme_type_variation = &"SideySecondaryButton"
	_rotate_invite_button.custom_minimum_size = Vector2(104, 58)
	_rotate_invite_button.pressed.connect(_rotate_remote_invite)
	invite_row.add_child(_rotate_invite_button)
	manage_card.add_child(invite_row)
	_members_list = VBoxContainer.new()
	_members_list.name = "MembersList"
	_members_list.add_theme_constant_override("separation", 8)
	manage_card.add_child(_members_list)
	_leave_room_button = Button.new()
	_leave_room_button.text = "이 그룹에서 나가기"
	_leave_room_button.theme_type_variation = &"SideyDangerButton"
	_leave_room_button.custom_minimum_size.y = 56
	_leave_room_button.pressed.connect(_leave_remote_room)
	manage_card.add_child(_leave_room_button)


func _build_app_page() -> void:
	var content := _add_page_scroll("AppPage")
	var preference_card := _add_card(content, "시작 설정", "컴퓨터를 켰을 때 SIDEY를 자동으로 시작할 수 있어요.")
	_launch_at_login = CheckBox.new()
	_launch_at_login.name = "LaunchAtLoginCheckBox"
	_launch_at_login.text = "로그인할 때 SIDEY 자동 실행"
	_launch_at_login.custom_minimum_size.y = 52
	_launch_at_login.disabled = not _platform_bridge.is_native_available()
	_launch_at_login.toggled.connect(_toggle_launch_at_login)
	preference_card.add_child(_launch_at_login)


func _add_page_scroll(page_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = page_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_container.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	return content


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	return label


func _show_settings_page(page: SettingsPage, clear_feedback := true) -> void:
	_active_page = page
	if is_instance_valid(_page_container):
		_page_container.current_tab = page
	for index in _navigation_buttons.size():
		_navigation_buttons[index].theme_type_variation = (
			&"SideyNavigationButtonSelected" if index == page else &"SideyNavigationButton"
		)
	if not is_instance_valid(_page_title):
		return
	match page:
		SettingsPage.PROFILE:
			_page_title.text = "내 프로필"
			_page_description.text = "친구들에게 보이는 내 이름과 캐릭터를 관리해요."
		SettingsPage.GROUPS:
			_page_title.text = "그룹"
			_page_description.text = "지금 볼 그룹을 고르고 초대와 멤버를 관리해요."
		SettingsPage.APP:
			_page_title.text = "앱 설정"
			_page_description.text = "SIDEY가 실행되는 방식을 설정해요."
	if clear_feedback:
		_clear_feedback()


func _clear_feedback() -> void:
	if not is_instance_valid(_feedback_panel):
		return
	_feedback.text = ""
	_feedback_panel.visible = false


func _refresh_profile() -> void:
	var profile := _room_controller.profile()
	_nickname_edit.text = str(profile.get("nickname", ""))
	var character_id := str(profile.get("character_id", "minty_pup"))
	_character_picker.select(maxi(0, _character_ids.find(character_id)))
	_launch_at_login.set_pressed_no_signal(_platform_bridge.is_launch_at_login_enabled())


func _refresh_rooms() -> void:
	if not is_instance_valid(_room_picker):
		return
	_room_picker.clear()
	_room_ids.clear()
	var active_index := 0
	for room in _room_controller.rooms():
		var room_id := str(room.get("id", ""))
		_room_ids.append(room_id)
		_room_picker.add_item(str(room.get("name", "그룹")))
		if room_id == _room_controller.active_room_id():
			active_index = _room_ids.size() - 1
	_room_picker.select(active_index)
	_refresh_active_room_name()


func _refresh_active_room_name() -> void:
	if is_instance_valid(_room_name_edit):
		_room_name_edit.text = str(_room_controller.active_room().get("name", ""))
	_refresh_group_management()


func _save_profile() -> void:
	if is_instance_valid(_backend_runtime):
		_save_remote_profile.call_deferred()
		return
	var error := _room_controller.set_profile(
		_nickname_edit.text,
		_character_ids[_character_picker.selected],
	)
	_show_result(error, "프로필을 저장했음.", "닉네임은 공백을 제외하고 2~12자로 입력해줘.")


func _select_room(index: int) -> void:
	if index < 0 or index >= _room_ids.size():
		return
	var error := _room_controller.set_active_room(_room_ids[index])
	_show_result(error, "활성 그룹을 바꿨음.", "그룹을 바꾸지 못했음.")
	_refresh_active_room_name()


func _rename_active_room() -> void:
	if is_instance_valid(_backend_runtime):
		_rename_remote_room.call_deferred()
		return
	var error := _room_controller.rename_room(_room_controller.active_room_id(), _room_name_edit.text)
	_show_result(error, "그룹 이름을 바꿨음.", "방장 권한과 1~20자 이름을 확인해줘.")


func _create_room() -> void:
	if is_instance_valid(_backend_runtime):
		_create_remote_room.call_deferred()
		return
	var error := _room_controller.create_room(_new_room_edit.text)
	_show_result(error, "새 그룹을 만들었음.", "그룹 이름 또는 최대 5개 제한을 확인해줘.")
	if error == OK:
		_new_room_edit.text = ""


func _join_room() -> void:
	if is_instance_valid(_backend_runtime):
		_join_remote_room.call_deferred()
		return
	var error := _room_controller.join_demo_room(_invite_code_edit.text)
	_show_result(error, "그룹에 참여했음.", "코드가 틀렸거나 이미 참여했거나 그룹이 5개임.")
	if error == OK:
		_invite_code_edit.text = ""


func _save_remote_profile() -> void:
	var result: Dictionary = await _backend_runtime.update_profile(
		_nickname_edit.text,
		_character_ids[_character_picker.selected],
	)
	_show_backend_result(result, "프로필을 저장했음.")


func _rename_remote_room() -> void:
	var result: Dictionary = await _backend_runtime.rename_room(
		_room_controller.active_room_id(),
		_room_name_edit.text,
	)
	_show_backend_result(result, "그룹 이름을 바꿨음.")


func _create_remote_room() -> void:
	var result: Dictionary = await _backend_runtime.create_room(_new_room_edit.text)
	_show_backend_result(result, "새 그룹을 만들었음.")
	if bool(result.get("ok", false)):
		_new_room_edit.text = ""


func _join_remote_room() -> void:
	var result: Dictionary = await _backend_runtime.join_room(_invite_code_edit.text)
	_show_backend_result(result, "그룹에 참여했음.")
	if bool(result.get("ok", false)):
		_invite_code_edit.text = ""


func _show_backend_result(result: Dictionary, success: String) -> void:
	var ok := bool(result.get("ok", false))
	_show_feedback(
		ok,
		success if ok else "처리하지 못했음: %s" % str(result.get("error_code", "unknown")),
	)


func _refresh_group_management() -> void:
	if not is_instance_valid(_invite_code_display):
		return
	var room := _room_controller.active_room()
	var has_room := not room.is_empty()
	var is_owner := has_room and str(room.get("owner_id", "")) == str(_room_controller.profile().get("user_id", ""))
	var invite_code := ""
	if is_owner and is_instance_valid(_backend_runtime):
		invite_code = _backend_runtime.read_invite_code(str(room.get("id", "")))
	_invite_code_display.text = invite_code
	_invite_code_display.placeholder_text = str(room.get("invite_code_hint", "초대 코드 원문 없음")) \
		if has_room else "활성 그룹 없음"
	_copy_invite_button.disabled = invite_code.is_empty()
	_rotate_invite_button.disabled = not is_owner or not is_instance_valid(_backend_runtime)
	_leave_room_button.disabled = not has_room or not is_instance_valid(_backend_runtime)
	_rebuild_member_management(room, is_owner)


func _rebuild_member_management(room: Dictionary, is_owner: bool) -> void:
	for child in _members_list.get_children():
		child.queue_free()
	for member in room.get("members", []) as Array:
		var member_data := member as Dictionary
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s%s" % [
			str(member_data.get("nickname", "친구")),
			" · 나" if bool(member_data.get("is_self", false)) else "",
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if is_owner and not bool(member_data.get("is_self", false)) and is_instance_valid(_backend_runtime):
			var remove_button := Button.new()
			remove_button.text = "내보내기"
			remove_button.theme_type_variation = &"SideyDangerButton"
			remove_button.pressed.connect(_remove_remote_member.bind(str(member_data.get("user_id", ""))))
			row.add_child(remove_button)
		_members_list.add_child(row)


func _copy_invite_code() -> void:
	if _invite_code_display.text.is_empty():
		return
	DisplayServer.clipboard_set(_invite_code_display.text)
	_show_feedback(true, "초대 코드를 클립보드에 복사했음.")


func _rotate_remote_invite() -> void:
	var result: Dictionary = await _backend_runtime.rotate_invite_code(_room_controller.active_room_id())
	_show_backend_result(result, "기존 코드를 폐기하고 새 초대 코드를 발급했음.")
	_refresh_group_management()


func _leave_remote_room() -> void:
	var room_id := _room_controller.active_room_id()
	var result: Dictionary = await _backend_runtime.leave_room(room_id)
	_show_backend_result(result, "그룹에서 나왔음.")
	_refresh_rooms()


func _remove_remote_member(user_id: String) -> void:
	var result: Dictionary = await _backend_runtime.remove_room_member(
		_room_controller.active_room_id(),
		user_id,
	)
	_show_backend_result(result, "멤버를 그룹에서 내보냈음.")
	_refresh_group_management()


func _toggle_launch_at_login(enabled: bool) -> void:
	var error := _platform_bridge.set_launch_at_login(enabled)
	_show_result(error, "자동 실행 설정을 바꿨음.", "자동 실행 설정을 변경하지 못했음.")
	if error != OK:
		_launch_at_login.set_pressed_no_signal(not enabled)


func _show_result(error: Error, success: String, failure: String) -> void:
	_show_feedback(
		error == OK,
		success if error == OK else "%s (오류 %d)" % [failure, error],
	)


func _show_feedback(success: bool, message: String) -> void:
	_feedback.text = message
	_feedback.add_theme_color_override(
		"font_color",
		SideyThemeScript.SUCCESS if success else SideyThemeScript.DANGER,
	)
	_feedback_panel.theme_type_variation = (
		&"SideyFeedbackSuccess" if success else &"SideyFeedbackDanger"
	)
	_feedback_panel.visible = true


func _on_rooms_changed(_rooms: Array[Dictionary]) -> void:
	_refresh_rooms()


func _on_active_room_changed(_previous_room_id: String, _room_id: String) -> void:
	_refresh_rooms()


func _add_card(parent: VBoxContainer, title_text: String, subtitle_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	parent.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	card.add_child(stack)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 24)
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	stack.add_child(subtitle)
	return stack
