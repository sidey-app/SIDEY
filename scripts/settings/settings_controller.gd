class_name SettingsController
extends Node

signal opened
signal closed

const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")

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
var _character_ids: Array[String] = []
var _room_ids: Array[String] = []
var _backend_runtime: BackendRuntime


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
	opened.emit()
	_window.popup_centered()


func close() -> void:
	if is_instance_valid(_window):
		_window.hide()
	closed.emit()


func _build_window() -> void:
	_window = Window.new()
	_window.name = "SettingsWindow"
	_window.title = "SIDEY 설정"
	_window.size = Vector2i(560, 760)
	_window.min_size = Vector2i(520, 680)
	_window.transparent = false
	_window.borderless = false
	_window.always_on_top = false
	_window.transient = false
	_window.close_requested.connect(close)
	add_child(_window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_window.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	var title := Label.new()
	title.text = "SIDEY 설정"
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)
	content.add_child(_section_label("내 프로필"))
	var profile_row := HBoxContainer.new()
	_nickname_edit = LineEdit.new()
	_nickname_edit.placeholder_text = "닉네임 · 2~12자"
	_nickname_edit.max_length = RoomController.MAX_NICKNAME_LENGTH
	_nickname_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_row.add_child(_nickname_edit)
	_character_picker = OptionButton.new()
	for entry in CharacterCatalogScript.all():
		_character_ids.append(str(entry["id"]))
		_character_picker.add_item(str(entry["display_name"]))
	profile_row.add_child(_character_picker)
	var save_profile_button := Button.new()
	save_profile_button.text = "저장"
	save_profile_button.pressed.connect(_save_profile)
	profile_row.add_child(save_profile_button)
	content.add_child(profile_row)
	content.add_child(HSeparator.new())
	content.add_child(_section_label("활성 그룹"))
	_room_picker = OptionButton.new()
	_room_picker.item_selected.connect(_select_room)
	content.add_child(_room_picker)
	var rename_row := HBoxContainer.new()
	_room_name_edit = LineEdit.new()
	_room_name_edit.placeholder_text = "그룹 이름 · 방장만 변경 가능"
	_room_name_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_room_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_row.add_child(_room_name_edit)
	var rename_button := Button.new()
	rename_button.text = "이름 변경"
	rename_button.pressed.connect(_rename_active_room)
	rename_row.add_child(rename_button)
	content.add_child(rename_row)
	content.add_child(_section_label("그룹 추가 · 사용자당 최대 5개"))
	var create_row := HBoxContainer.new()
	_new_room_edit = LineEdit.new()
	_new_room_edit.placeholder_text = "새 그룹 이름"
	_new_room_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_new_room_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_new_room_edit)
	var create_button := Button.new()
	create_button.text = "만들기"
	create_button.pressed.connect(_create_room)
	create_row.add_child(create_button)
	content.add_child(create_row)
	var join_row := HBoxContainer.new()
	_invite_code_edit = LineEdit.new()
	_invite_code_edit.placeholder_text = "초대 코드"
	_invite_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_invite_code_edit)
	var join_button := Button.new()
	join_button.text = "코드로 참여"
	join_button.pressed.connect(_join_room)
	join_row.add_child(join_button)
	content.add_child(join_row)
	if OS.is_debug_build():
		var demo_help := Label.new()
		demo_help.text = "개발용 코드: SIDEY-DEMO"
		demo_help.add_theme_font_size_override("font_size", 12)
		demo_help.add_theme_color_override("font_color", Color("75cdb5"))
		content.add_child(demo_help)
	content.add_child(HSeparator.new())
	content.add_child(_section_label("그룹 관리"))
	var invite_row := HBoxContainer.new()
	_invite_code_display = LineEdit.new()
	_invite_code_display.placeholder_text = "초대 코드 원문 없음"
	_invite_code_display.editable = false
	_invite_code_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_row.add_child(_invite_code_display)
	_copy_invite_button = Button.new()
	_copy_invite_button.text = "복사"
	_copy_invite_button.pressed.connect(_copy_invite_code)
	invite_row.add_child(_copy_invite_button)
	_rotate_invite_button = Button.new()
	_rotate_invite_button.text = "재발급"
	_rotate_invite_button.pressed.connect(_rotate_remote_invite)
	invite_row.add_child(_rotate_invite_button)
	content.add_child(invite_row)
	_members_list = VBoxContainer.new()
	_members_list.add_theme_constant_override("separation", 4)
	content.add_child(_members_list)
	_leave_room_button = Button.new()
	_leave_room_button.text = "이 그룹에서 나가기"
	_leave_room_button.pressed.connect(_leave_remote_room)
	content.add_child(_leave_room_button)
	content.add_child(HSeparator.new())
	_launch_at_login = CheckBox.new()
	_launch_at_login.text = "로그인할 때 SIDEY 자동 실행"
	_launch_at_login.disabled = not _platform_bridge.is_native_available()
	_launch_at_login.toggled.connect(_toggle_launch_at_login)
	content.add_child(_launch_at_login)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_color_override("font_color", Color("ff9d91"))
	content.add_child(_feedback)
	var close_button := Button.new()
	close_button.text = "닫기"
	close_button.pressed.connect(close)
	content.add_child(close_button)


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
	_feedback.text = success if ok else "처리하지 못했음: %s" % str(result.get("error_code", "unknown"))
	_feedback.add_theme_color_override("font_color", Color("75cdb5") if ok else Color("ff9d91"))


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
			remove_button.pressed.connect(_remove_remote_member.bind(str(member_data.get("user_id", ""))))
			row.add_child(remove_button)
		_members_list.add_child(row)


func _copy_invite_code() -> void:
	if _invite_code_display.text.is_empty():
		return
	DisplayServer.clipboard_set(_invite_code_display.text)
	_feedback.text = "초대 코드를 클립보드에 복사했음."
	_feedback.add_theme_color_override("font_color", Color("75cdb5"))


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
	_feedback.text = success if error == OK else "%s (오류 %d)" % [failure, error]
	_feedback.add_theme_color_override("font_color", Color("75cdb5") if error == OK else Color("ff9d91"))


func _on_rooms_changed(_rooms: Array[Dictionary]) -> void:
	_refresh_rooms()


func _on_active_room_changed(_previous_room_id: String, _room_id: String) -> void:
	_refresh_rooms()


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("c9e5df"))
	return label
