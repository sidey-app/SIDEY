extends SceneTree

const CharacterHudScript := preload("res://scripts/characters/character_hud.gd")
const OverlayToolbarScript := preload("res://scripts/overlay/overlay_toolbar.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const OverlayControllerScript := preload("res://scripts/overlay/overlay_controller.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const StatusMenuControllerScript := preload("res://scripts/app/status_menu_controller.gd")

var _failures := 0
var _compose_requested := false
var _history_requested := false
var _lock_request: Variant = null
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
	var toolbar := OverlayToolbarScript.new()
	toolbar.name = "OverlayToolbar"
	canvas.add_child(toolbar)
	toolbar.compose_requested.connect(func() -> void: _compose_requested = true)
	toolbar.history_requested.connect(func() -> void: _history_requested = true)
	toolbar.locked_change_requested.connect(func(locked: bool) -> void: _lock_request = locked)
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

	toolbar.set_locked(true)
	var buttons := toolbar.find_children("*", "Button", true, false)
	_press_button(buttons, "채팅")
	_press_button(buttons, "기록")
	_press_button(buttons, "잠금 해제")
	_check(_compose_requested, "chat remains available while locked")
	_check(_history_requested, "history remains available while locked")
	_check(_lock_request == false, "locked toolbar requests edit mode")
	var slider := toolbar.find_child("*", true, false) as Node
	for candidate in toolbar.find_children("*", "HSlider", true, false):
		slider = candidate as HSlider
	_check(slider is HSlider, "toolbar has scale control")
	if slider is HSlider:
		_check(not (slider as HSlider).is_visible_in_tree(), "scale is hidden while locked")
		_check((slider as HSlider).min_value == 150.0, "overlay minimum scale is 150 percent")
		_check((slider as HSlider).max_value == 200.0, "overlay maximum scale is 200 percent")
	toolbar.set_locked(false)
	if slider is HSlider:
		_check((slider as HSlider).is_visible_in_tree(), "scale appears only in edit mode")

	var settings_path := "/tmp/sidey-overlay-ui-%d.json" % OS.get_process_id()
	var overlay := OverlayControllerScript.new() as OverlayController
	root.add_child(overlay)
	_check(overlay.configure(root, SettingsStoreScript.new(settings_path)) == OK, "overlay controller configured")
	overlay.set_locked(true, false)
	var status_menu := StatusMenuControllerScript.new() as StatusMenuController
	root.add_child(status_menu)
	status_menu.configure(overlay, SettingsStoreScript.new(settings_path))
	status_menu.compose_requested.connect(func() -> void: _menu_compose_requested = true)
	status_menu._on_item_pressed(StatusMenuControllerScript.ITEM_COMPOSE)
	_check(_menu_compose_requested, "menu bar requests the composer")
	_check(overlay.is_locked(), "menu bar composer preserves the lock")
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


func _press_button(buttons: Array[Node], text: String) -> void:
	for node in buttons:
		var button := node as Button
		if button.text == text:
			button.pressed.emit()
			return
	_check(false, "button exists: %s" % text)


func _same_rgb(left: Color, right: Color) -> bool:
	return is_equal_approx(left.r, right.r) \
		and is_equal_approx(left.g, right.g) \
		and is_equal_approx(left.b, right.b)


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
