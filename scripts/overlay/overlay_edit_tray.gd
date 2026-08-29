class_name OverlayEditTray
extends Control

signal history_requested
signal locked_change_requested(locked: bool)
signal drag_requested
signal scale_requested(scale: float)
signal interactive_rect_changed

const OverlayThemeScript := preload("res://scripts/ui/overlay_theme.gd")
const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const LOCK_CLOSED_ICON := preload("res://assets/ui/lock_closed.svg")
const LOCK_OPEN_ICON := preload("res://assets/ui/lock_open.svg")
const MOVE_ICON := preload("res://assets/ui/move.svg")
const HISTORY_ICON := preload("res://assets/ui/history.svg")
const LOGICAL_WIDTH := 720.0
const EDGE_MARGIN := 8.0
const CONTROL_GAP := 6.0
const FIXED_UI_FACTOR := OverlayGeometryScript.FIXED_UI_FACTOR
const LOCKED_SIZE := Vector2(42.0, 42.0)
const UNLOCKED_SIZE := Vector2(232.0, 42.0)
const REVEAL_SECONDS := 0.18
const FADE_SECONDS := 0.10
const HIDE_GRACE_SECONDS := 0.30

var _panel: Panel
var _row: HBoxContainer
var _lock_button: Button
var _drag_button: Button
var _history_button: Button
var _scale_slider: HSlider
var _hide_timer: Timer
var _animation: Tween
var _locked := true
var _available := true
var _composer_hovered := false
var _panel_hovered := false
var _place_right := true
var _composer_rect := Rect2(Vector2(248.0, 322.0), Vector2(179.2, 33.6))
var _layout_composer_rect := _composer_rect
var _scale_dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = HIDE_GRACE_SECONDS
	_hide_timer.timeout.connect(_hide_lock_if_idle)
	add_child(_hide_timer)
	_refresh_layout(false)


func set_locked(locked: bool) -> void:
	_locked = locked
	_lock_button.icon = LOCK_CLOSED_ICON if locked else LOCK_OPEN_ICON
	_lock_button.tooltip_text = "위치 편집 잠금 해제" if locked else "위치 편집 잠금"
	if not locked:
		_cancel_hide()
		_set_edit_controls_visible(true)
		_panel.visible = _available
		_animate_panel(UNLOCKED_SIZE, 1.0, REVEAL_SECONDS)
		return
	if not _panel.visible:
		_set_edit_controls_visible(false)
		_refresh_layout(false)
		return
	_animate_panel(LOCKED_SIZE, 1.0, REVEAL_SECONDS, func() -> void:
		_set_edit_controls_visible(false)
		_schedule_hide_if_idle()
	)


func set_available(available: bool) -> void:
	_available = available
	_kill_animation()
	if not available:
		_cancel_hide()
		_panel.visible = false
	elif not _locked:
		_panel.visible = true
		_panel.modulate.a = 1.0
		_refresh_layout(false)
	interactive_rect_changed.emit()


func set_character_anchor(_anchor_x: float, composer_rect: Rect2) -> void:
	_composer_rect = composer_rect
	if _scale_dragging:
		return
	_layout_composer_rect = composer_rect
	_refresh_layout(false)


func set_composer_hovered(hovered: bool) -> void:
	_composer_hovered = hovered
	if not _locked:
		return
	if hovered:
		_cancel_hide()
		_show_lock()
	else:
		_schedule_hide_if_idle()


func set_overlay_scale(scale: float) -> void:
	if is_instance_valid(_scale_slider):
		_scale_slider.set_value_no_signal(scale * 100.0)


func interactive_rect() -> Rect2:
	if not _available or not is_instance_valid(_panel) or not _panel.visible:
		return Rect2()
	return Rect2(_panel.position, _panel.size * FIXED_UI_FACTOR)


func is_available() -> bool:
	return _available


func _build_panel() -> void:
	_panel = Panel.new()
	_panel.name = "EditTrayPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	_panel.scale = Vector2.ONE * FIXED_UI_FACTOR
	_panel.size = LOCKED_SIZE
	_panel.modulate.a = 0.0
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", OverlayThemeScript.tray_style())
	_panel.mouse_entered.connect(func() -> void:
		_panel_hovered = true
		_cancel_hide()
	)
	_panel.mouse_exited.connect(func() -> void:
		_panel_hovered = false
		_schedule_hide_if_idle()
	)
	add_child(_panel)

	_row = HBoxContainer.new()
	_row.name = "EditTrayRow"
	_row.position = Vector2(6.0, 6.0)
	_row.size = Vector2(220.0, 30.0)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 8)
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
	_scale_slider.min_value = OverlayGeometryScript.MIN_SCALE * 100.0
	_scale_slider.max_value = OverlayGeometryScript.MAX_SCALE * 100.0
	_scale_slider.step = 1.0
	_scale_slider.tooltip_text = "캐릭터와 닉네임 크기 150~200%"
	_scale_slider.value_changed.connect(func(value: float) -> void: scale_requested.emit(value / 100.0))
	_scale_slider.drag_started.connect(func() -> void:
		_scale_dragging = true
		_layout_composer_rect = _composer_rect
	)
	_scale_slider.drag_ended.connect(func(_value_changed: bool) -> void:
		_scale_dragging = false
		_layout_composer_rect = _composer_rect
		_refresh_layout(true)
	)
	_row.add_child(_scale_slider)
	_set_edit_controls_visible(false)


func _icon_button(icon: Texture2D, tooltip: String) -> Button:
	var button := Button.new()
	button.text = ""
	button.icon = icon
	button.expand_icon = true
	button.custom_minimum_size = Vector2(28.0, 28.0)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	OverlayThemeScript.style_icon_button(button)
	return button


func _show_lock() -> void:
	if not _available:
		return
	_set_edit_controls_visible(false)
	_panel.visible = true
	_animate_panel(LOCKED_SIZE, 1.0, FADE_SECONDS)


func _hide_lock_if_idle() -> void:
	if not _locked or _composer_hovered or _panel_hovered:
		return
	_animate_panel(LOCKED_SIZE, 0.0, FADE_SECONDS, func() -> void:
		if _locked and not _composer_hovered and not _panel_hovered:
			_panel.visible = false
			interactive_rect_changed.emit()
	)


func _schedule_hide_if_idle() -> void:
	if not _locked or _composer_hovered or _panel_hovered or not _panel.visible:
		return
	_hide_timer.start()


func _cancel_hide() -> void:
	if is_instance_valid(_hide_timer):
		_hide_timer.stop()


func _set_edit_controls_visible(visible: bool) -> void:
	_drag_button.visible = visible
	_history_button.visible = visible
	_scale_slider.visible = visible
	_row.size = Vector2(220.0 if visible else 30.0, 30.0)


func _refresh_layout(animate: bool) -> void:
	if not is_instance_valid(_panel):
		return
	_place_right = _can_place_right(UNLOCKED_SIZE)
	_order_controls()
	var target_size := UNLOCKED_SIZE if not _locked else LOCKED_SIZE
	if animate:
		_animate_panel(target_size, 1.0, REVEAL_SECONDS)
	else:
		_panel.size = target_size
		_panel.position = _panel_position(target_size)
		interactive_rect_changed.emit()


func _can_place_right(panel_size: Vector2) -> bool:
	var rendered_width := panel_size.x * FIXED_UI_FACTOR
	return _layout_composer_rect.end.x + CONTROL_GAP + rendered_width <= LOGICAL_WIDTH - EDGE_MARGIN


func _panel_position(panel_size: Vector2) -> Vector2:
	var rendered_size := panel_size * FIXED_UI_FACTOR
	var left := _layout_composer_rect.end.x + CONTROL_GAP if _place_right \
		else _layout_composer_rect.position.x - CONTROL_GAP - rendered_size.x
	return Vector2(
		clampf(left, EDGE_MARGIN, LOGICAL_WIDTH - EDGE_MARGIN - rendered_size.x),
		_layout_composer_rect.position.y,
	)


func _order_controls() -> void:
	if _place_right:
		_row.move_child(_lock_button, 0)
		_row.move_child(_drag_button, 1)
		_row.move_child(_history_button, 2)
		_row.move_child(_scale_slider, 3)
	else:
		_row.move_child(_scale_slider, 0)
		_row.move_child(_history_button, 1)
		_row.move_child(_drag_button, 2)
		_row.move_child(_lock_button, 3)


func _animate_panel(
	target_size: Vector2,
	target_alpha: float,
	duration: float,
	finished := Callable(),
) -> void:
	_kill_animation()
	_place_right = _can_place_right(UNLOCKED_SIZE)
	_order_controls()
	var start_size := _panel.size
	var start_position := _panel.position
	var start_alpha := _panel.modulate.a
	var target_position := _panel_position(target_size)
	_panel.visible = _available
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_animation.tween_method(func(progress: float) -> void:
		_panel.size = start_size.lerp(target_size, progress)
		_panel.position = start_position.lerp(target_position, progress)
		_panel.modulate.a = lerpf(start_alpha, target_alpha, progress)
		interactive_rect_changed.emit()
	, 0.0, 1.0, duration)
	if finished.is_valid():
		_animation.tween_callback(finished)


func _kill_animation() -> void:
	if is_instance_valid(_animation):
		_animation.kill()
	_animation = null
