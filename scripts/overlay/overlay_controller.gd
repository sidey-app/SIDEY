class_name OverlayController
extends Node

signal locked_changed(locked: bool)
signal overlay_visibility_changed(visible: bool)
signal scale_changed(scale: float)

const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const BASE_WINDOW_SIZE := Vector2i(720, 360)
const SCREEN_POLL_INTERVAL := 0.5
const SAVE_DEBOUNCE := 0.35
const EDGE_MARGIN := 24

var _window: Window
var _settings_store: SettingsStore
var _locked := true
var _overlay_visible := true
var _scale := 1.0
var _last_position := Vector2i.ZERO
var _last_size := BASE_WINDOW_SIZE
var _screen_fingerprint := ""
var _poll_elapsed := 0.0
var _save_elapsed := 0.0
var _geometry_dirty := false
var _configured := false
var _headless := false


func configure(window: Window, settings_store: SettingsStore) -> Error:
	_window = window
	_settings_store = settings_store
	_headless = DisplayServer.get_name() == "headless"
	_configure_window_flags()
	_restore_settings()
	_screen_fingerprint = _all_screens_fingerprint()
	_last_position = _window.position
	_last_size = _window.size
	_configured = true
	set_process(true)
	return OK


func is_locked() -> bool:
	return _locked


func is_overlay_visible() -> bool:
	return _overlay_visible


func overlay_scale() -> float:
	return _scale


func set_locked(locked: bool, persist := true) -> void:
	if _locked == locked and _configured:
		return
	_locked = locked
	if not _headless:
		_window.unfocusable = locked
		_window.mouse_passthrough = locked
	if persist and _settings_store != null:
		_report_settings_error(_settings_store.set_overlay_locked(locked), "locked")
	locked_changed.emit(locked)


func toggle_locked() -> void:
	set_locked(not _locked)


func set_overlay_visible(visible: bool, persist := true) -> void:
	_overlay_visible = visible
	_window.visible = visible
	if persist and _settings_store != null:
		_report_settings_error(_settings_store.set_overlay_visible(visible), "visible")
	overlay_visibility_changed.emit(visible)


func toggle_overlay_visible() -> void:
	set_overlay_visible(not _overlay_visible)


func set_overlay_scale(next_scale: float) -> void:
	var clamped_scale := OverlayGeometryScript.clamp_scale(next_scale)
	if is_equal_approx(_scale, clamped_scale):
		return
	var current_size := _window.size
	var next_size := OverlayGeometryScript.scaled_window_size(BASE_WINDOW_SIZE, clamped_scale)
	var next_position := OverlayGeometryScript.centered_scaled_position(
		_window.position,
		current_size,
		next_size,
	)
	_scale = clamped_scale
	_window.size = next_size
	_window.position = _clamp_to_screen(next_position, next_size, _current_screen())
	_mark_geometry_dirty()
	scale_changed.emit(_scale)


func begin_drag() -> void:
	if _locked or not _overlay_visible or _headless:
		return
	_window.start_drag()


func reset_position() -> void:
	var screen := clampi(DisplayServer.get_primary_screen(), 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var position := usable_rect.end - _window.size - Vector2i(EDGE_MARGIN, EDGE_MARGIN)
	_window.current_screen = screen
	_window.position = OverlayGeometryScript.clamp_position(position, _window.size, usable_rect)
	_mark_geometry_dirty()


func ensure_on_screen() -> void:
	var screen := _current_screen()
	_window.position = _clamp_to_screen(_window.position, _window.size, screen)
	_mark_geometry_dirty()


func flush_settings() -> void:
	if _geometry_dirty:
		_save_geometry()


func diagnostic_report() -> Dictionary:
	return {
		"display_server": DisplayServer.get_name(),
		"transparent_supported": DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY),
		"status_indicator_supported": DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR),
		"position": _window.position,
		"size": _window.size,
		"screen": _current_screen(),
		"scale": _scale,
		"locked": _locked,
		"visible": _overlay_visible,
		"borderless": _window.borderless,
		"always_on_top": _window.always_on_top,
		"transparent": _window.transparent,
		"unfocusable": _window.unfocusable,
		"mouse_passthrough": _window.mouse_passthrough,
	}


func _process(delta: float) -> void:
	if not _configured:
		return
	_poll_elapsed += delta
	if _geometry_dirty:
		_save_elapsed += delta
		if _save_elapsed >= SAVE_DEBOUNCE:
			_save_geometry()
	if _poll_elapsed < SCREEN_POLL_INTERVAL:
		return
	_poll_elapsed = 0.0
	var fingerprint := _all_screens_fingerprint()
	if fingerprint != _screen_fingerprint:
		_screen_fingerprint = fingerprint
		_recover_after_screen_change()
	if _window.position != _last_position or _window.size != _last_size:
		_last_position = _window.position
		_last_size = _window.size
		_mark_geometry_dirty()


func _configure_window_flags() -> void:
	Engine.max_fps = 30
	RenderingServer.set_default_clear_color(Color(0.0, 0.0, 0.0, 0.0))
	if _headless:
		return
	_window.borderless = true
	_window.always_on_top = true
	_window.unresizable = true
	if DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY):
		_window.transparent = true


func _restore_settings() -> void:
	var overlay_settings := _settings_store.overlay()
	_scale = OverlayGeometryScript.clamp_scale(float(overlay_settings.get("scale", 1.0)))
	_locked = bool(overlay_settings.get("locked", true))
	_overlay_visible = bool(overlay_settings.get("visible", true))
	var screens := _screen_snapshots()
	var screen := OverlayGeometryScript.resolve_screen(
		int(overlay_settings.get("screen", -1)),
		str(overlay_settings.get("screen_signature", "")),
		screens,
		DisplayServer.get_primary_screen(),
	)
	var size := OverlayGeometryScript.scaled_window_size(BASE_WINDOW_SIZE, _scale)
	_window.size = size
	_window.current_screen = screen
	var saved_position := overlay_settings.get("position", [0, 0]) as Array
	var position := Vector2i.ZERO
	if saved_position.size() >= 2:
		position = Vector2i(int(saved_position[0]), int(saved_position[1]))
	if int(overlay_settings.get("screen", -1)) < 0:
		var usable_rect := DisplayServer.screen_get_usable_rect(screen)
		position = usable_rect.end - size - Vector2i(EDGE_MARGIN, EDGE_MARGIN)
	_window.position = _clamp_to_screen(position, size, screen)
	set_locked(_locked, false)
	set_overlay_visible(_overlay_visible, false)


func _recover_after_screen_change() -> void:
	var screen_count := DisplayServer.get_screen_count()
	if screen_count <= 0:
		return
	var screen := _current_screen()
	if screen < 0 or screen >= screen_count:
		screen = clampi(DisplayServer.get_primary_screen(), 0, screen_count - 1)
		_window.current_screen = screen
	_window.position = _clamp_to_screen(_window.position, _window.size, screen)
	_mark_geometry_dirty()


func _clamp_to_screen(position: Vector2i, size: Vector2i, screen: int) -> Vector2i:
	var safe_screen := clampi(screen, 0, maxi(0, DisplayServer.get_screen_count() - 1))
	return OverlayGeometryScript.clamp_position(
		position,
		size,
		DisplayServer.screen_get_usable_rect(safe_screen),
	)


func _current_screen() -> int:
	if _headless:
		return 0
	return _window.current_screen


func _screen_snapshots() -> Array[Dictionary]:
	var screens: Array[Dictionary] = []
	for screen in DisplayServer.get_screen_count():
		screens.append({
			"index": screen,
			"signature": OverlayGeometryScript.screen_signature(
				DisplayServer.screen_get_size(screen),
				DisplayServer.screen_get_scale(screen),
			),
		})
	return screens


func _all_screens_fingerprint() -> String:
	var parts := PackedStringArray()
	for screen in DisplayServer.get_screen_count():
		parts.append("%d:%s:%s" % [
			screen,
			DisplayServer.screen_get_usable_rect(screen),
			OverlayGeometryScript.screen_signature(
				DisplayServer.screen_get_size(screen),
				DisplayServer.screen_get_scale(screen),
			),
		])
	return "|".join(parts)


func _mark_geometry_dirty() -> void:
	_geometry_dirty = true
	_save_elapsed = 0.0


func _save_geometry() -> void:
	_geometry_dirty = false
	_save_elapsed = 0.0
	_last_position = _window.position
	_last_size = _window.size
	var screen := _current_screen()
	var signature := OverlayGeometryScript.screen_signature(
		DisplayServer.screen_get_size(screen),
		DisplayServer.screen_get_scale(screen),
	)
	_report_settings_error(
		_settings_store.set_overlay_geometry(_window.position, _scale, screen, signature),
		"geometry",
	)


func _report_settings_error(error: Error, field: String) -> void:
	if error != OK:
		push_warning("OVERLAY_SETTINGS_SAVE_FAILED field=%s error=%d" % [field, error])
