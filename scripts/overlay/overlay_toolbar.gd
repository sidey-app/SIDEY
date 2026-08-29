class_name OverlayToolbar
extends Control

signal compose_requested
signal history_requested
signal locked_change_requested(locked: bool)
signal drag_requested
signal scale_requested(scale: float)

const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const INTERACTIVE_RECT := Rect2(66.0, 296.0, 588.0, 62.0)

var _panel: PanelContainer
var _peek: PanelContainer
var _hover_zone: Control
var _edit_row: HBoxContainer
var _lock_button: Button
var _scale_slider: HSlider
var _scale_label: Label
var _hide_timer: Timer
var _locked := true
var _context_active := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hover_zone()
	_build_peek()
	_build_panel()
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = 0.55
	_hide_timer.timeout.connect(_refresh_visibility)
	add_child(_hide_timer)
	_refresh_visibility()


func set_locked(locked: bool) -> void:
	_locked = locked
	_lock_button.text = "잠금 해제" if locked else "편집 완료"
	_edit_row.visible = not locked
	_panel.position = Vector2(182.0, 314.0) if locked else Vector2(42.0, 314.0)
	_panel.size = Vector2(356.0, 44.0) if locked else Vector2(636.0, 44.0)
	_refresh_visibility()


func set_overlay_scale(scale: float) -> void:
	_scale_slider.set_value_no_signal(scale * 100.0)
	_scale_label.text = "%d%%" % roundi(scale * 100.0)


func set_context_active(active: bool) -> void:
	_context_active = active
	_refresh_visibility()


func interactive_rect() -> Rect2:
	return INTERACTIVE_RECT


func reveal() -> void:
	_hide_timer.stop()
	_panel.visible = true
	_peek.visible = false


func _build_hover_zone() -> void:
	_hover_zone = Control.new()
	_hover_zone.name = "HoverZone"
	_hover_zone.position = INTERACTIVE_RECT.position
	_hover_zone.size = INTERACTIVE_RECT.size
	_hover_zone.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hover_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	_hover_zone.mouse_entered.connect(reveal)
	_hover_zone.mouse_exited.connect(_schedule_hide)
	add_child(_hover_zone)


func _build_peek() -> void:
	_peek = PanelContainer.new()
	_peek.position = Vector2(330.0, 334.0)
	_peek.size = Vector2(60.0, 20.0)
	_peek.mouse_filter = Control.MOUSE_FILTER_PASS
	_peek.add_theme_stylebox_override("panel", SideyThemeScript.overlay_panel_style())
	_peek.mouse_entered.connect(reveal)
	add_child(_peek)
	var dots := Label.new()
	dots.text = "•••"
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dots.add_theme_font_size_override("font_size", 13)
	dots.add_theme_color_override("font_color", SideyThemeScript.TEXT_MUTED)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_peek.add_child(dots)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(182.0, 314.0)
	_panel.size = Vector2(356.0, 44.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_theme_stylebox_override("panel", SideyThemeScript.overlay_panel_style())
	_panel.mouse_entered.connect(reveal)
	_panel.mouse_exited.connect(_schedule_hide)
	add_child(_panel)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 8)
	_panel.add_child(action_row)
	action_row.add_child(_action_button("채팅", func() -> void: compose_requested.emit()))
	action_row.add_child(_action_button("기록", func() -> void: history_requested.emit()))

	_edit_row = HBoxContainer.new()
	_edit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_edit_row.add_theme_constant_override("separation", 8)
	action_row.add_child(_edit_row)
	var drag_button := Button.new()
	drag_button.text = "⠿ 이동"
	drag_button.theme_type_variation = &"SideyOverlayButton"
	drag_button.tooltip_text = "캐릭터 전체 위치 이동"
	drag_button.button_down.connect(func() -> void: drag_requested.emit())
	drag_button.mouse_entered.connect(reveal)
	_edit_row.add_child(drag_button)
	_scale_slider = HSlider.new()
	_scale_slider.custom_minimum_size = Vector2(152.0, 24.0)
	_scale_slider.min_value = OverlayGeometry.MIN_SCALE * 100.0
	_scale_slider.max_value = OverlayGeometry.MAX_SCALE * 100.0
	_scale_slider.step = 1.0
	_scale_slider.value_changed.connect(func(value: float) -> void: scale_requested.emit(value / 100.0))
	_edit_row.add_child(_scale_slider)
	_scale_label = Label.new()
	_scale_label.custom_minimum_size = Vector2(54.0, 0.0)
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scale_label.add_theme_font_size_override("font_size", 15)
	_scale_label.add_theme_color_override("font_color", SideyThemeScript.TEXT_SECONDARY)
	_edit_row.add_child(_scale_label)
	_lock_button = _action_button("잠금 해제", func() -> void: locked_change_requested.emit(not _locked))
	action_row.add_child(_lock_button)


func _action_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = &"SideyOverlayButton"
	button.pressed.connect(callback)
	button.mouse_entered.connect(reveal)
	return button


func _schedule_hide() -> void:
	if _locked and not _context_active:
		_hide_timer.start()


func _refresh_visibility() -> void:
	var expanded := not _locked or _context_active or not _hide_timer.is_stopped()
	_panel.visible = expanded
	_peek.visible = not expanded
