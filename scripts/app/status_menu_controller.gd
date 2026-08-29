class_name StatusMenuController
extends Node

signal compose_requested
signal settings_requested
signal quit_requested
signal quiet_mode_changed(enabled: bool)
signal room_selected(room_id: String)

const ITEM_OVERLAY_VISIBLE := 100
const ITEM_ACTIVE_ROOM := 200
const ITEM_COMPOSE := 300
const ITEM_LOCKED := 400
const ITEM_QUIET := 500
const ITEM_RESET_POSITION := 600
const ITEM_SETTINGS := 700
const ITEM_QUIT := 800
const ITEM_ROOM_BASE := 1000
const STATUS_ICON_PATH := "res://assets/ui/status_icon.svg"

var _overlay_controller: OverlayController
var _settings_store: SettingsStore
var _popup_menu: PopupMenu
var _status_indicator: StatusIndicator
var _quiet_mode := false
var _room_controller: RoomController
var _room_item_ids: Dictionary = {}


func configure(
	overlay_controller: OverlayController,
	settings_store: SettingsStore,
	room_controller: RoomController = null,
) -> Error:
	_overlay_controller = overlay_controller
	_settings_store = settings_store
	_room_controller = room_controller
	_quiet_mode = settings_store.quiet_mode()
	_overlay_controller.locked_changed.connect(_refresh_menu)
	_overlay_controller.overlay_visibility_changed.connect(_refresh_menu)
	if _room_controller != null:
		_room_controller.rooms_changed.connect(_on_rooms_changed)
		_room_controller.active_room_changed.connect(_on_active_room_changed)
		_room_controller.unread_changed.connect(_on_unread_changed)
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return ERR_UNAVAILABLE
	_build_menu()
	_refresh_menu()
	return OK


func is_available() -> bool:
	return is_instance_valid(_status_indicator)


func quiet_mode() -> bool:
	return _quiet_mode


func _build_menu() -> void:
	_popup_menu = PopupMenu.new()
	_popup_menu.name = "StatusMenu"
	add_child(_popup_menu)
	_popup_menu.id_pressed.connect(_on_item_pressed)
	_rebuild_menu_items()

	_status_indicator = StatusIndicator.new()
	_status_indicator.name = "SIDEYStatusIndicator"
	_status_indicator.tooltip = "SIDEY"
	var icon := load(STATUS_ICON_PATH) as Texture2D
	if icon == null:
		push_warning("STATUS_INDICATOR_ICON_MISSING path=%s" % STATUS_ICON_PATH)
	else:
		_status_indicator.icon = icon
	add_child(_status_indicator)
	_status_indicator.menu = _popup_menu.get_path()


func _rebuild_menu_items() -> void:
	_popup_menu.clear()
	_room_item_ids.clear()
	_popup_menu.add_item("SIDEY 숨기기", ITEM_OVERLAY_VISIBLE)
	_popup_menu.add_separator()
	var active_room_name := "그룹 없음"
	if _room_controller != null and not _room_controller.active_room().is_empty():
		active_room_name = str(_room_controller.active_room().get("name", "그룹"))
	_popup_menu.add_item("활성 그룹 · %s" % active_room_name, ITEM_ACTIVE_ROOM)
	_popup_menu.set_item_disabled(_popup_menu.get_item_index(ITEM_ACTIVE_ROOM), true)
	if _room_controller != null:
		var room_list := _room_controller.rooms()
		for index in room_list.size():
			var room := room_list[index]
			var item_id := ITEM_ROOM_BASE + index
			var unread := int(room.get("unread", 0))
			var label := "  %s%s" % [
				str(room.get("name", "그룹")),
				"  (%d)" % unread if unread > 0 else "",
			]
			_popup_menu.add_radio_check_item(label, item_id)
			_popup_menu.set_item_checked(
				_popup_menu.get_item_index(item_id),
				str(room.get("id", "")) == _room_controller.active_room_id(),
			)
			_room_item_ids[item_id] = str(room.get("id", ""))
	_popup_menu.add_separator()
	_popup_menu.add_item("메시지 작성", ITEM_COMPOSE)
	_popup_menu.add_item("상호작용 잠금 해제", ITEM_LOCKED)
	_popup_menu.add_check_item("조용히 모드", ITEM_QUIET)
	_popup_menu.add_separator()
	_popup_menu.add_item("위치 초기화", ITEM_RESET_POSITION)
	_popup_menu.add_item("설정", ITEM_SETTINGS)
	_popup_menu.add_separator()
	_popup_menu.add_item("SIDEY 종료", ITEM_QUIT)


func _on_item_pressed(item_id: int) -> void:
	if _room_item_ids.has(item_id):
		room_selected.emit(str(_room_item_ids[item_id]))
		return
	match item_id:
		ITEM_OVERLAY_VISIBLE:
			_overlay_controller.toggle_overlay_visible()
		ITEM_COMPOSE:
			_overlay_controller.set_overlay_visible(true)
			_overlay_controller.set_locked(false)
			compose_requested.emit()
		ITEM_LOCKED:
			_overlay_controller.toggle_locked()
		ITEM_QUIET:
			_quiet_mode = not _quiet_mode
			var save_error := _settings_store.set_quiet_mode(_quiet_mode)
			if save_error != OK:
				push_warning("STATUS_MENU_SETTINGS_SAVE_FAILED field=quiet_mode error=%d" % save_error)
			quiet_mode_changed.emit(_quiet_mode)
		ITEM_RESET_POSITION:
			_overlay_controller.reset_position()
		ITEM_SETTINGS:
			settings_requested.emit()
		ITEM_QUIT:
			quit_requested.emit()
	_refresh_menu()


func _refresh_menu(_unused: Variant = null) -> void:
	if not is_instance_valid(_popup_menu):
		return
	var overlay_item := _popup_menu.get_item_index(ITEM_OVERLAY_VISIBLE)
	_popup_menu.set_item_text(
		overlay_item,
		"SIDEY 숨기기" if _overlay_controller.is_overlay_visible() else "SIDEY 보이기",
	)
	var locked_item := _popup_menu.get_item_index(ITEM_LOCKED)
	_popup_menu.set_item_text(
		locked_item,
		"상호작용 잠금 해제" if _overlay_controller.is_locked() else "상호작용 잠금",
	)
	_popup_menu.set_item_checked(_popup_menu.get_item_index(ITEM_QUIET), _quiet_mode)


func _on_rooms_changed(_rooms: Array[Dictionary]) -> void:
	if is_instance_valid(_popup_menu):
		_rebuild_menu_items()
		_refresh_menu()


func _on_active_room_changed(_previous_room_id: String, _room_id: String) -> void:
	if is_instance_valid(_popup_menu):
		_rebuild_menu_items()
		_refresh_menu()


func _on_unread_changed(_room_id: String, _count: int) -> void:
	if is_instance_valid(_popup_menu):
		_rebuild_menu_items()
		_refresh_menu()
