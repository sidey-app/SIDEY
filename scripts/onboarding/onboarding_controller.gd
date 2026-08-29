class_name OnboardingController
extends Node

signal completed

const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const WINDOW_SIZE := Vector2i(960, 720)
const WINDOW_MIN_SIZE := Vector2i(820, 620)

enum OnboardingStep {
	PROFILE,
	GROUP,
}

enum GroupEntryMode {
	CREATE,
	JOIN,
}

var _room_controller: RoomController
var _window: Window
var _nickname_edit: LineEdit
var _character_picker: OptionButton
var _room_name_edit: LineEdit
var _invite_code_edit: LineEdit
var _error_label: Label
var _character_ids: Array[String] = []
var _backend_runtime: BackendRuntime
var _next_button: Button
var _back_button: Button
var _group_submit_button: Button
var _create_mode_button: Button
var _join_mode_button: Button
var _step_container: TabContainer
var _group_form_container: TabContainer
var _progress_label: Label
var _title_label: Label
var _body_label: Label
var _error_panel: PanelContainer


func show_onboarding(room_controller: RoomController, backend_runtime: BackendRuntime = null) -> void:
	_room_controller = room_controller
	_backend_runtime = backend_runtime
	if _room_controller.is_onboarding_complete():
		close()
		return
	if is_instance_valid(_window):
		_window.popup_centered()
		return
	_build_window()
	_window.popup_centered()


func close() -> void:
	if is_instance_valid(_window):
		_window.queue_free()
	_window = null


func show_blocking_error(message: String) -> void:
	if not is_instance_valid(_window):
		_build_window()
	_set_busy(true)
	_show_error(message)
	_window.popup_centered()


func _build_window() -> void:
	_window = Window.new()
	_window.name = "OnboardingWindow"
	_window.title = "SIDEY 시작하기"
	_apply_window_scale(true)
	_window.transparent = false
	_window.borderless = false
	_window.always_on_top = false
	_window.unresizable = false
	_window.transient = false
	_window.theme = SideyThemeScript.create_standard_window_theme()
	_window.close_requested.connect(func() -> void: get_tree().quit(0))
	_window.dpi_changed.connect(_on_window_dpi_changed)
	add_child(_window)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = SideyThemeScript.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.add_child(background)
	var scroll := ScrollContainer.new()
	scroll.name = "OnboardingScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_window.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	_progress_label = Label.new()
	_progress_label.name = "OnboardingProgress"
	_progress_label.add_theme_font_size_override("font_size", 17)
	_progress_label.add_theme_color_override("font_color", SideyThemeScript.BLUE)
	content.add_child(_progress_label)
	_title_label = Label.new()
	_title_label.name = "OnboardingTitle"
	_title_label.add_theme_font_size_override("font_size", 38)
	content.add_child(_title_label)
	_body_label = Label.new()
	_body_label.name = "OnboardingDescription"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 19)
	_body_label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	_body_label.add_theme_constant_override("line_spacing", 5)
	content.add_child(_body_label)
	_build_error_banner(content)
	_step_container = TabContainer.new()
	_step_container.name = "OnboardingSteps"
	_step_container.tabs_visible = false
	content.add_child(_step_container)
	_build_profile_step()
	_build_group_step()
	_show_step(OnboardingStep.PROFILE, false)
	_show_group_entry_mode(GroupEntryMode.CREATE, false)


func _apply_window_scale(resize_window: bool) -> void:
	var display_scale := SideyThemeScript.standard_window_scale(_window.current_screen)
	_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_window.content_scale_factor = display_scale
	_window.min_size = SideyThemeScript.scaled_window_size(WINDOW_MIN_SIZE, display_scale)
	if resize_window:
		_window.size = SideyThemeScript.scaled_window_size(WINDOW_SIZE, display_scale)


func _on_window_dpi_changed() -> void:
	_apply_window_scale(false)


func _build_error_banner(parent: VBoxContainer) -> void:
	_error_panel = PanelContainer.new()
	_error_panel.name = "OnboardingErrorBanner"
	_error_panel.theme_type_variation = &"SideyFeedbackDanger"
	_error_panel.visible = false
	parent.add_child(_error_panel)
	_error_label = Label.new()
	_error_label.name = "OnboardingError"
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", SideyThemeScript.DANGER)
	_error_panel.add_child(_error_label)


func _build_profile_step() -> void:
	var page := VBoxContainer.new()
	page.name = "ProfileStep"
	_step_container.add_child(page)
	var profile_card := _add_card(page, "내 프로필", "모든 그룹에서 친구들에게 똑같이 보여요.")
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
	_next_button = Button.new()
	_next_button.name = "OnboardingNextButton"
	_next_button.text = "다음"
	_next_button.custom_minimum_size = Vector2(150, 58)
	_next_button.pressed.connect(_continue_to_group)
	action_row.add_child(_next_button)


func _build_group_step() -> void:
	var page := VBoxContainer.new()
	page.name = "GroupStep"
	_step_container.add_child(page)
	var room_card := _add_card(page, "친구 그룹 연결", "새 그룹을 만들거나 받은 초대 코드로 들어가세요.")
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	room_card.add_child(mode_row)
	_create_mode_button = Button.new()
	_create_mode_button.name = "CreateGroupModeButton"
	_create_mode_button.text = "새 그룹 만들기"
	_create_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_mode_button.custom_minimum_size.y = 52
	_create_mode_button.pressed.connect(_show_group_entry_mode.bind(GroupEntryMode.CREATE))
	mode_row.add_child(_create_mode_button)
	_join_mode_button = Button.new()
	_join_mode_button.name = "JoinGroupModeButton"
	_join_mode_button.text = "초대 코드로 참여"
	_join_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_mode_button.custom_minimum_size.y = 52
	_join_mode_button.pressed.connect(_show_group_entry_mode.bind(GroupEntryMode.JOIN))
	mode_row.add_child(_join_mode_button)
	_group_form_container = TabContainer.new()
	_group_form_container.name = "GroupEntryForms"
	_group_form_container.tabs_visible = false
	room_card.add_child(_group_form_container)
	_build_create_group_form()
	_build_join_group_form()
	_build_group_action_row(room_card)


func _build_create_group_form() -> void:
	var form := VBoxContainer.new()
	form.name = "CreateGroupForm"
	form.add_theme_constant_override("separation", 12)
	_group_form_container.add_child(form)
	form.add_child(_field_label("그룹 이름"))
	_room_name_edit = LineEdit.new()
	_room_name_edit.name = "RoomNameEdit"
	_room_name_edit.placeholder_text = "그룹 이름 · 1~20자"
	_room_name_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_room_name_edit.custom_minimum_size.y = 58
	form.add_child(_room_name_edit)


func _build_join_group_form() -> void:
	var form := VBoxContainer.new()
	form.name = "JoinGroupForm"
	form.add_theme_constant_override("separation", 12)
	_group_form_container.add_child(form)
	form.add_child(_field_label("초대 코드"))
	_invite_code_edit = LineEdit.new()
	_invite_code_edit.name = "InviteCodeEdit"
	_invite_code_edit.placeholder_text = "7KM4-NP2Q"
	_invite_code_edit.custom_minimum_size.y = 58
	form.add_child(_invite_code_edit)
	if OS.is_debug_build():
		var demo_help := Label.new()
		demo_help.text = "개발용 5인 검증 코드: SIDEY-DEMO"
		demo_help.add_theme_font_size_override("font_size", 16)
		demo_help.add_theme_color_override("font_color", SideyThemeScript.SUCCESS)
		form.add_child(demo_help)


func _build_group_action_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_back_button = Button.new()
	_back_button.name = "OnboardingBackButton"
	_back_button.text = "이전"
	_back_button.theme_type_variation = &"SideySecondaryButton"
	_back_button.custom_minimum_size = Vector2(120, 58)
	_back_button.pressed.connect(_show_step.bind(OnboardingStep.PROFILE))
	row.add_child(_back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_group_submit_button = Button.new()
	_group_submit_button.name = "GroupSubmitButton"
	_group_submit_button.custom_minimum_size = Vector2(170, 58)
	_group_submit_button.pressed.connect(_submit_group)
	row.add_child(_group_submit_button)


func _submit_group() -> void:
	if _group_form_container.current_tab == GroupEntryMode.CREATE:
		_create_room()
	else:
		_join_room()


func _continue_to_group() -> void:
	if not _validate_profile_fields():
		return
	_show_step(OnboardingStep.GROUP)


func _show_step(step: OnboardingStep, clear_error := true) -> void:
	if is_instance_valid(_step_container):
		_step_container.current_tab = step
	if not is_instance_valid(_progress_label):
		return
	if step == OnboardingStep.PROFILE:
		_progress_label.text = "1 / 2 · 내 프로필"
		_title_label.text = "친구들을 화면 곁으로"
		_body_label.text = "먼저 친구들에게 보일 이름과 캐릭터를 골라주세요."
	else:
		_progress_label.text = "2 / 2 · 친구 그룹"
		_title_label.text = "친구와 연결하기"
		_body_label.text = "그룹을 만들거나 받은 초대 코드로 참여하면 준비가 끝나요."
	if clear_error:
		_clear_error()


func _show_group_entry_mode(mode: GroupEntryMode, clear_error := true) -> void:
	if is_instance_valid(_group_form_container):
		_group_form_container.current_tab = mode
	if is_instance_valid(_create_mode_button):
		_create_mode_button.theme_type_variation = (
			&"SideySegmentButtonSelected" if mode == GroupEntryMode.CREATE else &"SideySegmentButton"
		)
		_join_mode_button.theme_type_variation = (
			&"SideySegmentButtonSelected" if mode == GroupEntryMode.JOIN else &"SideySegmentButton"
		)
		_group_submit_button.text = "그룹 만들기" if mode == GroupEntryMode.CREATE else "코드로 참여"
	if clear_error:
		_clear_error()


func _create_room() -> void:
	if is_instance_valid(_backend_runtime):
		_create_remote_room.call_deferred()
		return
	if not _validate_group_fields(true):
		return
	var profile_error := _validate_and_save_profile()
	if profile_error != OK:
		return
	var error := _room_controller.create_room(_room_name_edit.text)
	if error != OK:
		_show_error("그룹 이름은 1~20자로 입력해줘.")
		return
	_finish()


func _join_room() -> void:
	if is_instance_valid(_backend_runtime):
		_join_remote_room.call_deferred()
		return
	if not _validate_group_fields(false):
		return
	var profile_error := _validate_and_save_profile()
	if profile_error != OK:
		return
	var error := _room_controller.join_demo_room(_invite_code_edit.text)
	if error != OK:
		_show_error("로컬 검증에서는 SIDEY-DEMO 코드만 사용할 수 있음.")
		return
	_finish()


func _create_remote_room() -> void:
	if not _validate_remote_fields(true):
		return
	_set_busy(true)
	var result: Dictionary = await _backend_runtime.onboard_create(
		_nickname_edit.text,
		_character_ids[_character_picker.selected],
		_room_name_edit.text,
	)
	_set_busy(false)
	if not bool(result.get("ok", false)):
		_show_backend_error(result)
		return
	_finish()


func _join_remote_room() -> void:
	if not _validate_remote_fields(false):
		return
	_set_busy(true)
	var result: Dictionary = await _backend_runtime.onboard_join(
		_nickname_edit.text,
		_character_ids[_character_picker.selected],
		_invite_code_edit.text,
	)
	_set_busy(false)
	if not bool(result.get("ok", false)):
		_show_backend_error(result)
		return
	_finish()


func _validate_remote_fields(creating: bool) -> bool:
	if not _validate_profile_fields():
		return false
	return _validate_group_fields(creating)


func _validate_profile_fields() -> bool:
	if RoomController.validate_nickname(_nickname_edit.text) != OK:
		_show_error("닉네임은 줄바꿈 없이 2~12자로 입력해줘.")
		return false
	if _character_picker.selected < 0 or _character_picker.selected >= _character_ids.size():
		_show_error("캐릭터를 선택해줘.")
		return false
	return true


func _validate_group_fields(creating: bool) -> bool:
	if creating and RoomController.validate_room_name(_room_name_edit.text) != OK:
		_show_error("그룹 이름은 1~20자로 입력해줘.")
		return false
	if not creating and _invite_code_edit.text.strip_edges().is_empty():
		_show_error("초대 코드를 입력해줘.")
		return false
	return true


func _set_busy(busy: bool) -> void:
	_next_button.disabled = busy
	_back_button.disabled = busy
	_group_submit_button.disabled = busy
	_create_mode_button.disabled = busy
	_join_mode_button.disabled = busy
	_nickname_edit.editable = not busy
	_character_picker.disabled = busy
	_room_name_edit.editable = not busy
	_invite_code_edit.editable = not busy
	if busy:
		_error_panel.theme_type_variation = &"SideyFeedbackSuccess"
		_error_label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
		_error_label.text = "서버에 연결 중…"
		_error_panel.visible = true
	else:
		_clear_error()


func _show_backend_error(result: Dictionary) -> void:
	_show_error("처리하지 못했음: %s" % str(result.get("error_code", "unknown")))


func _validate_and_save_profile() -> Error:
	if not _validate_profile_fields():
		return ERR_INVALID_PARAMETER
	var character_id := _character_ids[_character_picker.selected]
	var error := _room_controller.set_profile(_nickname_edit.text, character_id)
	if error != OK:
		_show_error("프로필을 저장하지 못했음 (오류 %d)." % error)
	return error


func _finish() -> void:
	var error := _room_controller.complete_onboarding()
	if error != OK:
		_show_error("온보딩 상태를 저장하지 못했음 (오류 %d)." % error)
		return
	close()
	completed.emit()


func _show_error(message: String) -> void:
	_error_panel.theme_type_variation = &"SideyFeedbackDanger"
	_error_label.add_theme_color_override("font_color", SideyThemeScript.DANGER)
	_error_label.text = message
	_error_panel.visible = true


func _clear_error() -> void:
	if not is_instance_valid(_error_panel):
		return
	_error_label.text = ""
	_error_panel.visible = false


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	return label


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
