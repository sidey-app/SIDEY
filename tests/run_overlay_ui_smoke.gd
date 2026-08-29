extends SceneTree

const CharacterHudScript := preload("res://scripts/characters/character_hud.gd")
const OverlayEditTrayScript := preload("res://scripts/overlay/overlay_edit_tray.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const OverlayControllerScript := preload("res://scripts/overlay/overlay_controller.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const StatusMenuControllerScript := preload("res://scripts/app/status_menu_controller.gd")

var _failures := 0
var _history_requested := false
var _lock_request: Variant = null
var _drag_requested := false
var _menu_compose_requested := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 360)
	root.theme = SideyThemeScript.create()
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	var hud := CharacterHudScript.new() as CharacterHud
	hud.name = "CharacterHud"
	canvas.add_child(hud)
	hud.configure_room(_demo_room())
	hud.show_message("friend-0", "오늘 저녁 뭐 먹을래?")
	var tray := OverlayEditTrayScript.new() as OverlayEditTray
	tray.name = "OverlayEditTray"
	canvas.add_child(tray)
	tray.history_requested.connect(func() -> void: _history_requested = true)
	tray.locked_change_requested.connect(func(locked: bool) -> void: _lock_request = locked)
	tray.drag_requested.connect(func() -> void: _drag_requested = true)
	await process_frame

	var labels := hud.find_children("*", "Label", true, false)
	_check(_label_count(labels, "친구 모임") == 0, "room name is absent from overlay")
	_check(_nickname_count(labels) == 5, "five nicknames are shown")
	_check(_label_count(labels, "나") == 1, "self identity is shown once")
	for label_node in labels:
		var label := label_node as Label
		if label.text.begins_with("친구") and label.text != "친구 모임":
			_check(label.get_theme_font_size("font_size") >= 16, "nickname text is readable")
	var identity_panel := hud.find_child("Identity_friend-0", true, false) as PanelContainer
	_check(identity_panel != null, "self identity pill exists")
	if identity_panel != null:
		var identity_style := identity_panel.get_theme_stylebox("panel") as StyleBoxFlat
		_check(identity_style != null, "identity pill has a flat style")
		if identity_style != null:
			_check(identity_style.bg_color.a >= 0.7, "identity pill uses dark translucent background")
	_check(hud.self_anchor_x() < 100.0, "self anchor follows the left-most character")
	_check(_same_rgb(hud.presence_color("friend-0"), PresenceState.indicator_color(PresenceState.Value.ONLINE)), "online dot is green")
	hud.set_presence("friend-0", PresenceState.Value.TYPING)
	_check(_same_rgb(hud.presence_color("friend-0"), PresenceState.indicator_color(PresenceState.Value.TYPING)), "typing dot is green")
	hud.set_presence("friend-0", PresenceState.Value.AWAY)
	_check(_same_rgb(hud.presence_color("friend-0"), PresenceState.indicator_color(PresenceState.Value.AWAY)), "away dot is orange")
	hud.set_presence("friend-0", PresenceState.Value.OFFLINE)
	_check(_same_rgb(hud.presence_color("friend-0"), PresenceState.indicator_color(PresenceState.Value.OFFLINE)), "offline dot is gray")
	hud.set_presence("friend-0", PresenceState.Value.RECONNECTING)
	var reconnect_alpha := hud.presence_dot_alpha("friend-0")
	hud._process(CharacterHud.RECONNECT_BLINK_SECONDS + 0.01)
	_check(not is_equal_approx(reconnect_alpha, hud.presence_dot_alpha("friend-0")), "reconnecting dot blinks")
	var first_bubble_rect := hud.bubble_rect("friend-0")
	var second_bubble_rect := hud.bubble_rect("friend-1")
	_check(first_bubble_rect.position.y != second_bubble_rect.position.y, "multi-member bubbles alternate between two lanes")
	_check(first_bubble_rect.position.x >= 0.0 and first_bubble_rect.end.x <= 720.0, "left bubble stays inside the overlay")
	_check(hud.bubble_rect("friend-4").end.x <= 720.0, "right bubble stays inside the overlay")

	var visible_bubble := hud.find_child("Bubble", true, false) as PanelContainer
	_check(visible_bubble != null, "message bubble becomes visible")
	if visible_bubble != null:
		var bubble_style := visible_bubble.get_theme_stylebox("panel") as StyleBoxFlat
		_check(bubble_style != null, "message bubble has a flat style")
		if bubble_style != null:
			_check(
				bubble_style.bg_color.r > 0.97 and bubble_style.bg_color.g > 0.97 and bubble_style.bg_color.b > 0.97,
				"message bubble is white",
			)

	var composer_rect := Rect2(8.0, 320.0, 224.0, 42.0)
	tray.set_character_anchor(hud.self_anchor_x(), composer_rect)
	tray.set_locked(true)
	var buttons := tray.find_children("*", "Button", true, false)
	_check(buttons.size() == 3, "edit tray has only lock, move, and history icon buttons")
	for node in buttons:
		var button := node as Button
		_check(button.text.is_empty(), "edit tray buttons have no text")
		_check(button.icon != null, "edit tray buttons use SVG icons")
	var lock_button := tray.find_child("LockButton", true, false) as Button
	var move_button := tray.find_child("MoveButton", true, false) as Button
	var history_button := tray.find_child("HistoryButton", true, false) as Button
	_check(lock_button != null and lock_button.is_visible_in_tree(), "closed lock remains visible while locked")
	_check(move_button != null and not move_button.is_visible_in_tree(), "move icon is hidden while locked")
	_check(history_button != null and not history_button.is_visible_in_tree(), "history icon is hidden while locked")
	lock_button.pressed.emit()
	_check(_lock_request == false, "closed lock requests edit mode")
	var slider := tray.find_child("ScaleSlider", true, false) as HSlider
	_check(slider != null, "edit tray has scale control")
	if slider != null:
		_check(not slider.is_visible_in_tree(), "scale is hidden while locked")
		_check(slider.min_value == 150.0, "overlay minimum scale is 150 percent")
		_check(slider.max_value == 200.0, "overlay maximum scale is 200 percent")
	tray.set_locked(false)
	if slider != null:
		_check(slider.is_visible_in_tree(), "scale appears only in edit mode")
	_check(move_button.is_visible_in_tree(), "move icon appears in edit mode")
	_check(history_button.is_visible_in_tree(), "history icon appears in edit mode")
	move_button.button_down.emit()
	history_button.pressed.emit()
	_check(_drag_requested, "move starts only from the move icon")
	_check(_history_requested, "history opens from its icon in edit mode")
	var tray_panel := tray.find_child("EditTrayPanel", true, false) as PanelContainer
	var tray_style := tray_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_check(tray_style != null and tray_style.bg_color.r < 0.1 and tray_style.bg_color.a >= 0.7, "edit tray uses a dark translucent pill")
	tray.set_character_anchor(642.0, Rect2(488.0, 320.0, 224.0, 42.0))
	tray.set_locked(false)
	var tray_row := tray.find_child("EditTrayRow", true, false) as HBoxContainer
	_check(tray_row.get_child(tray_row.get_child_count() - 1) == lock_button, "lock icon stays next to a right-edge composer")
	tray.set_character_anchor(hud.self_anchor_x(), composer_rect)
	for label_node in tray.find_children("*", "Label", true, false):
		_check((label_node as Label).text not in ["채팅", "기록", "이동", "편집 완료", "•••"], "legacy overlay control text is absent")

	var settings_path := "/tmp/sidey-overlay-ui-%d.json" % OS.get_process_id()
	var overlay := OverlayControllerScript.new() as OverlayController
	root.add_child(overlay)
	_check(overlay.configure(root, SettingsStoreScript.new(settings_path)) == OK, "overlay controller configured")
	overlay.set_locked(true, false)
	tray.set_locked(true)
	overlay.set_interactive_regions([composer_rect, tray.interactive_rect()])
	var locked_polygon := overlay.interactive_polygon()
	var overlay_scale := overlay.overlay_scale()
	_check(not locked_polygon.is_empty(), "locked overlay uses a limited input polygon")
	_check(Geometry2D.is_point_in_polygon(composer_rect.get_center() * overlay_scale, locked_polygon), "locked polygon includes the composer")
	_check(not Geometry2D.is_point_in_polygon(Vector2(360.0, 180.0) * overlay_scale, locked_polygon), "locked polygon passes unrelated window space through")
	overlay.set_locked(false, false)
	tray.set_locked(false)
	overlay.set_interactive_regions([composer_rect, tray.interactive_rect()])
	var unlocked_polygon := overlay.interactive_polygon()
	_check(not unlocked_polygon.is_empty(), "unlocked overlay still uses a limited input polygon")
	_check(Geometry2D.is_point_in_polygon(tray.interactive_rect().get_center() * overlay_scale, unlocked_polygon), "unlocked polygon includes the edit tray")
	_check(_polygon_bounds(unlocked_polygon).size.x < root.size.x, "unlocked polygon does not cover the full window")
	var history_rect := Rect2(8.0, 84.0, 320.0, 226.0)
	overlay.set_interactive_regions([composer_rect, tray.interactive_rect(), history_rect])
	var history_polygon := overlay.interactive_polygon()
	_check(Geometry2D.is_point_in_polygon(history_rect.get_center() * overlay_scale, history_polygon), "history polygon includes the open history panel")
	overlay.set_locked(true, false)
	var status_menu := StatusMenuControllerScript.new() as StatusMenuController
	root.add_child(status_menu)
	status_menu.configure(overlay, SettingsStoreScript.new(settings_path))
	status_menu.compose_requested.connect(func() -> void: _menu_compose_requested = true)
	status_menu._on_item_pressed(StatusMenuControllerScript.ITEM_COMPOSE)
	_check(_menu_compose_requested, "menu bar requests the composer")
	_check(overlay.is_locked(), "menu bar composer preserves the current lock state")
	DirAccess.remove_absolute(settings_path)

	canvas.queue_free()
	status_menu.queue_free()
	overlay.queue_free()
	_finish.call_deferred()


func _demo_room() -> Dictionary:
	var members: Array[Dictionary] = []
	for index in 5:
		members.append({
			"user_id": "friend-%d" % index,
			"nickname": "친구 %d" % (index + 1),
			"character_id": "minty_pup",
			"presence": "online",
			"is_self": index == 0,
		})
	return {"id": "overlay-ui", "name": "친구 모임", "members": members}


func _label_count(labels: Array[Node], text: String) -> int:
	var count := 0
	for node in labels:
		if (node as Label).text == text:
			count += 1
	return count


func _nickname_count(labels: Array[Node]) -> int:
	var count := 0
	for node in labels:
		if (node as Label).text.begins_with("친구 "):
			count += 1
	return count


func _same_rgb(left: Color, right: Color) -> bool:
	return is_equal_approx(left.r, right.r) \
		and is_equal_approx(left.g, right.g) \
		and is_equal_approx(left.b, right.b)


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	return bounds


func _check(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("OVERLAY_UI_TEST_FAILED %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("SIDEY_OVERLAY_UI_SMOKE_OK")
		quit(0)
	else:
		push_error("SIDEY_OVERLAY_UI_SMOKE_FAILED failures=%d" % _failures)
		quit(1)
