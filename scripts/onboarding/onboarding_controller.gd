class_name OnboardingController
extends Node

signal completed

const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")

var _room_controller: RoomController
var _window: Window
var _nickname_edit: LineEdit
var _character_picker: OptionButton
var _room_name_edit: LineEdit
var _invite_code_edit: LineEdit
var _error_label: Label
var _character_ids: Array[String] = []
var _backend_runtime: BackendRuntime
var _create_button: Button
var _join_button: Button


func show_onboarding(room_controller: RoomController, backend_runtime: BackendRuntime = null) -> void:
	_room_controller = room_controller
	_backend_runtime = backend_runtime
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
	_error_label.text = message
	_window.popup_centered()


func _build_window() -> void:
	_window = Window.new()
	_window.name = "OnboardingWindow"
	_window.title = "SIDEY 시작하기"
	_window.size = Vector2i(720, 840)
	_window.min_size = Vector2i(640, 720)
	_window.transparent = false
	_window.borderless = false
	_window.always_on_top = false
	_window.unresizable = false
	_window.transient = false
	_window.theme = SideyThemeScript.create()
	_window.close_requested.connect(func() -> void: get_tree().quit(0))
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
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_bottom", 38)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	var title := Label.new()
	title.text = "친구들을 화면 곁으로"
	title.add_theme_font_size_override("font_size", 36)
	content.add_child(title)
	var body := Label.new()
	body.text = "로그인 없이 바로 시작할 수 있어요.\n내 프로필은 참여한 모든 그룹에서 똑같이 보여요."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	body.add_theme_constant_override("line_spacing", 5)
	content.add_child(body)
	var profile_card := _add_card(
		content,
		"내 프로필",
		"닉네임과 캐릭터는 나중에 설정에서 바꿀 수 있어요.",
	)
	profile_card.add_child(_field_label("닉네임"))
	_nickname_edit = LineEdit.new()
	_nickname_edit.placeholder_text = "2~12자로 입력해주세요"
	_nickname_edit.max_length = RoomController.MAX_NICKNAME_LENGTH
	_nickname_edit.custom_minimum_size.y = 54
	profile_card.add_child(_nickname_edit)
	profile_card.add_child(_field_label("캐릭터"))
	_character_picker = OptionButton.new()
	for entry in CharacterCatalogScript.all():
		_character_ids.append(str(entry["id"]))
		_character_picker.add_item(str(entry["display_name"]))
	_character_picker.custom_minimum_size.y = 54
	profile_card.add_child(_character_picker)
	var room_card := _add_card(
		content,
		"친구와 시작하기",
		"새 그룹을 만들거나 받은 초대 코드로 들어가세요.",
	)
	room_card.add_child(_field_label("새 그룹 만들기"))
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 10)
	_room_name_edit = LineEdit.new()
	_room_name_edit.placeholder_text = "그룹 이름 · 1~20자"
	_room_name_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_room_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_name_edit.custom_minimum_size.y = 54
	create_row.add_child(_room_name_edit)
	_create_button = Button.new()
	_create_button.text = "그룹 만들기"
	_create_button.custom_minimum_size = Vector2(150, 54)
	_create_button.pressed.connect(_create_room)
	create_row.add_child(_create_button)
	room_card.add_child(create_row)
	room_card.add_child(_field_label("초대 코드로 참여"))
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	_invite_code_edit = LineEdit.new()
	_invite_code_edit.placeholder_text = "7KM4-NP2Q"
	_invite_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_code_edit.custom_minimum_size.y = 54
	join_row.add_child(_invite_code_edit)
	_join_button = Button.new()
	_join_button.text = "코드로 참여"
	_join_button.custom_minimum_size = Vector2(150, 54)
	_join_button.pressed.connect(_join_room)
	join_row.add_child(_join_button)
	room_card.add_child(join_row)
	if OS.is_debug_build():
		var demo_help := Label.new()
		demo_help.text = "개발용 5인 검증 코드: SIDEY-DEMO"
		demo_help.add_theme_font_size_override("font_size", 15)
		demo_help.add_theme_color_override("font_color", SideyThemeScript.SUCCESS)
		room_card.add_child(demo_help)
	_error_label = Label.new()
	_error_label.custom_minimum_size.y = 24
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", SideyThemeScript.DANGER)
	room_card.add_child(_error_label)


func _create_room() -> void:
	if is_instance_valid(_backend_runtime):
		_create_remote_room.call_deferred()
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
	if RoomController.validate_nickname(_nickname_edit.text) != OK:
		_show_error("닉네임은 줄바꿈 없이 2~12자로 입력해줘.")
		return false
	if creating and RoomController.validate_room_name(_room_name_edit.text) != OK:
		_show_error("그룹 이름은 1~20자로 입력해줘.")
		return false
	if not creating and _invite_code_edit.text.strip_edges().is_empty():
		_show_error("초대 코드를 입력해줘.")
		return false
	return true


func _set_busy(busy: bool) -> void:
	_create_button.disabled = busy
	_join_button.disabled = busy
	_nickname_edit.editable = not busy
	_character_picker.disabled = busy
	_room_name_edit.editable = not busy
	_invite_code_edit.editable = not busy
	_error_label.text = "서버에 연결 중…" if busy else ""


func _show_backend_error(result: Dictionary) -> void:
	_show_error("처리하지 못했음: %s" % str(result.get("error_code", "unknown")))


func _validate_and_save_profile() -> Error:
	if RoomController.validate_nickname(_nickname_edit.text) != OK:
		_show_error("닉네임은 줄바꿈 없이 2~12자로 입력해줘.")
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
	completed.emit()
	close()


func _show_error(message: String) -> void:
	_error_label.text = message


func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	return label


func _add_card(parent: VBoxContainer, title_text: String, subtitle_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	parent.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	card.add_child(stack)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 23)
	stack.add_child(title)
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	stack.add_child(subtitle)
	return stack
