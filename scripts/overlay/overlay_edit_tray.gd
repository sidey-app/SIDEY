class_name OverlayEditTray
extends Control

signal history_requested
signal locked_change_requested(locked: bool)
signal drag_requested
signal scale_requested(scale: float)

const OverlayThemeScript := preload("res://scripts/ui/overlay_theme.gd")
const LOCK_CLOSED_ICON := preload("res://assets/ui/lock_closed.svg")
const LOCK_OPEN_ICON := preload("res://assets/ui/lock_open.svg")
const MOVE_ICON := preload("res://assets/ui/move.svg")
const HISTORY_ICON := preload("res://assets/ui/history.svg")
const LOGICAL_WIDTH := 720.0
const EDGE_MARGIN := 8.0
const CONTROL_GAP := 6.0
const LOCKED_SIZE := Vector2(42.0, 42.0)
const UNLOCKED_SIZE := Vector2(238.0, 42.0)

var _panel: PanelContainer
var _row: HBoxContainer
var _lock_button: Button
var _drag_button: Button
var _history_button: Button
var _scale_slider: HSlider
var _locked := true
var _available := true
var _anchor_x := LOGICAL_WIDTH * 0.5
var _composer_rect := Rect2(Vector2(248.0, 320.0), Vector2(224.0, 42.0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	_refresh_layout()


func set_locked(locked: bool) -> void:
	_locked = locked
	_lock_button.icon = LOCK_CLOSED_ICON if locked else LOCK_OPEN_ICON
	_lock_button.tooltip_text = "위치 편집 잠금 해제" if locked else "위치 편집 잠금"
	_drag_button.visible = not locked
	_history_button.visible = not locked
	_scale_slider.visible = not locked
	_refresh_layout()


func set_available(available: bool) -> void:
	_available = available
	if is_instance_valid(_panel):
		_panel.visible = available


func set_character_anchor(anchor_x: float, composer_rect: Rect2) -> void:
	_anchor_x = clampf(anchor_x, 0.0, LOGICAL_WIDTH)
	_composer_rect = composer_rect
	_refresh_layout()


func set_overlay_scale(scale: float) -> void:
	if is_instance_valid(_scale_slider):
		_scale_slider.set_value_no_signal(scale * 100.0)


func interactive_rect() -> Rect2:
	if not _available or not is_instance_valid(_panel):
		return Rect2()
	return Rect2(_panel.position, _panel.size)


func is_available() -> bool:
	return _available


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "EditTrayPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", OverlayThemeScript.tray_style())
	add_child(_panel)
	_row = HBoxContainer.new()
	_row.name = "EditTrayRow"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 4)
	_panel.add_child(_row)
	_lock_button = _icon_button(LOCK_CLOSED_ICON, "위치 편집 잠금 해제")
	_lock_button.name = "LockButton"
	_lock_button.pressed.connect(func() -> void: locked_change_requested.emit(not _locked))
	_row.add_child(_lock_button)
	_drag_button = _icon_button(MOVE_ICON, "캐릭터 전체 위치 이동")
	_drag_button.name = "MoveButton"
	_drag_button.button_down.connect(func() -> void: drag_requested.emit())
	_row.add_child(_drag_button)
	_history_button = _icon_button(HISTORY_ICON, "최근 메시지")
	_history_button.name = "HistoryButton"
	_history_button.pressed.connect(func() -> void: history_requested.emit())
	_row.add_child(_history_button)
	_scale_slider = HSlider.new()
	_scale_slider.name = "ScaleSlider"
	_scale_slider.custom_minimum_size = Vector2(112.0, 24.0)
	_scale_slider.min_value = OverlayGeometry.MIN_SCALE * 100.0
	_scale_slider.max_value = OverlayGeometry.MAX_SCALE * 100.0
	_scale_slider.step = 1.0
	_scale_slider.tooltip_text = "오버레이 크기 150~200%"
	_scale_slider.value_changed.connect(func(value: float) -> void: scale_requested.emit(value / 100.0))
	_row.add_child(_scale_slider)


func _icon_button(icon: Texture2D, tooltip: String) -> Button:
	var button := Button.new()
	button.text = ""
	button.icon = icon
	button.expand_icon = true
	button.custom_minimum_size = Vector2(30.0, 30.0)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	OverlayThemeScript.style_icon_button(button)
	return button


func _refresh_layout() -> void:
	if not is_instance_valid(_panel):
		return
	var panel_size := LOCKED_SIZE if _locked else UNLOCKED_SIZE
	var right_x := _composer_rect.end.x + CONTROL_GAP
	var place_right := right_x + panel_size.x <= LOGICAL_WIDTH - EDGE_MARGIN
	var left := right_x if place_right else _composer_rect.position.x - CONTROL_GAP - panel_size.x
	_panel.position = Vector2(clampf(left, EDGE_MARGIN, LOGICAL_WIDTH - EDGE_MARGIN - panel_size.x), _composer_rect.position.y)
	_panel.custom_minimum_size = panel_size
	_panel.size = panel_size
	_panel.visible = _available
	if place_right:
		_row.move_child(_lock_button, 0)
		_row.move_child(_drag_button, 1)
		_row.move_child(_history_button, 2)
		_row.move_child(_scale_slider, 3)
	else:
		_row.move_child(_scale_slider, 0)
		_row.move_child(_history_button, 1)
		_row.move_child(_drag_button, 2)
		_row.move_child(_lock_button, 3)
