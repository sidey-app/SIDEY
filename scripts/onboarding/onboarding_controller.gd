class_name OnboardingController
extends Node

signal completed

const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")

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
	_window.size = Vector2i(500, 480)
	_window.min_size = Vector2i(460, 440)
	_window.transparent = false
	_window.borderless = false
	_window.always_on_top = false
	_window.unresizable = false
	_window.transient = false
	_window.close_requested.connect(func() -> void: get_tree().quit(0))
	add_child(_window)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	_window.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var title := Label.new()
	title.text = "친구들을 화면 곁으로 불러오기"
	title.add_theme_font_size_override("font_size", 24)
	content.add_child(title)
	var body := Label.new()
	body.text = "로그인 화면은 없음. 닉네임과 캐릭터는 모든 그룹에서 동일하게 사용됨."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", Color("aebbc4"))
	content.add_child(body)
	content.add_child(_field_label("닉네임 · 2~12자"))
	_nickname_edit = LineEdit.new()
	_nickname_edit.placeholder_text = "예: 민트"
	_nickname_edit.max_length = RoomController.MAX_NICKNAME_LENGTH
	content.add_child(_nickname_edit)
	content.add_child(_field_label("캐릭터"))
	_character_picker = OptionButton.new()
	for entry in CharacterCatalogScript.all():
		_character_ids.append(str(entry["id"]))
		_character_picker.add_item(str(entry["display_name"]))
	content.add_child(_character_picker)
	var separator := HSeparator.new()
	content.add_child(separator)
	content.add_child(_field_label("새 그룹 만들기 · 1~20자"))
	var create_row := HBoxContainer.new()
	_room_name_edit = LineEdit.new()
	_room_name_edit.placeholder_text = "그룹 이름"
	_room_name_edit.max_length = RoomController.MAX_ROOM_NAME_LENGTH
	_room_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_room_name_edit)
	_create_button = Button.new()
	_create_button.text = "만들고 시작"
	_create_button.pressed.connect(_create_room)
	create_row.add_child(_create_button)
	content.add_child(create_row)
	content.add_child(_field_label("또는 초대 코드로 참여"))
	var join_row := HBoxContainer.new()
	_invite_code_edit = LineEdit.new()
	_invite_code_edit.placeholder_text = "7KM4-NP2Q"
	_invite_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_invite_code_edit)
	_join_button = Button.new()
	_join_button.text = "참여하고 시작"
	_join_button.pressed.connect(_join_room)
	join_row.add_child(_join_button)
	content.add_child(join_row)
	if OS.is_debug_build():
		var demo_help := Label.new()
		demo_help.text = "개발용 5인 검증 코드: SIDEY-DEMO"
		demo_help.add_theme_font_size_override("font_size", 12)
		demo_help.add_theme_color_override("font_color", Color("75cdb5"))
		content.add_child(demo_help)
	_error_label = Label.new()
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_color_override("font_color", Color("ff837a"))
	content.add_child(_error_label)


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
	label.add_theme_font_size_override("font_size", 13)
	return label
