extends SceneTree

const CharacterHudScript := preload("res://scripts/characters/character_hud.gd")
const OverlayToolbarScript := preload("res://scripts/overlay/overlay_toolbar.gd")
const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")

var _failures := 0
var _compose_requested := false
var _history_requested := false
var _lock_request: Variant = null


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
	_check(_nickname_count(labels) == 5, "five large nicknames are shown")
	for label_node in labels:
		var label := label_node as Label
		if label.text.begins_with("친구") and label.text != "친구 모임":
			_check(label.get_theme_font_size("font_size") >= 19, "nickname text is readable")

	var visible_bubble: PanelContainer
	for panel_node in hud.find_children("*", "PanelContainer", true, false):
		var panel := panel_node as PanelContainer
		if panel.is_visible_in_tree():
			visible_bubble = panel
			break
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

	canvas.queue_free()
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
