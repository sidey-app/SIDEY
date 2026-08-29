class_name CharacterHud
extends Control

const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const LOGICAL_WIDTH := 720.0
const CHARACTER_VIEW_WIDTH := 2.96
const BUBBLE_SECONDS := 10.0

var _slots: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure_room(room: Dictionary) -> void:
	clear_members()
	var members: Array = room.get("members", []) as Array
	var positions := CharacterRow.layout_positions(members.size())
	for index in members.size():
		var member := (members[index] as Dictionary).duplicate(true)
		var user_id := str(member.get("user_id", ""))
		var center_x := _world_x_to_canvas(positions[index])
		var name_label := Label.new()
		name_label.position = Vector2(center_x - 72.0, 282.0)
		name_label.size = Vector2(144.0, 36.0)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.text = "%s%s" % [
			str(member.get("nickname", "친구")),
			" · 나" if bool(member.get("is_self", false)) else "",
		]
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 19)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.09, 0.76))
		name_label.add_theme_constant_override("outline_size", 6)
		add_child(name_label)

		var bubble_group := Control.new()
		bubble_group.position = Vector2(center_x - 80.0, 44.0 + (index % 2) * 10.0)
		bubble_group.size = Vector2(160.0, 86.0)
		bubble_group.visible = false
		bubble_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bubble_group)
		var bubble := PanelContainer.new()
		bubble.size = Vector2(160.0, 76.0)
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.add_theme_stylebox_override("panel", SideyThemeScript.message_bubble_style())
		bubble_group.add_child(bubble)
		var bubble_label := Label.new()
		bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bubble_label.add_theme_font_size_override("font_size", 17)
		bubble_label.add_theme_color_override("font_color", SideyThemeScript.TEXT_PRIMARY)
		bubble.add_child(bubble_label)
		var tail := Polygon2D.new()
		tail.position = Vector2(70.0, 73.0)
		tail.polygon = PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(20.0, 0.0),
			Vector2(10.0, 11.0),
		])
		tail.color = Color(1.0, 1.0, 1.0, 0.99)
		bubble_group.add_child(tail)
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = BUBBLE_SECONDS
		timer.timeout.connect(func() -> void: bubble_group.visible = false)
		add_child(timer)
		_slots[user_id] = {
			"member": member,
			"name_label": name_label,
			"bubble_group": bubble_group,
			"bubble_label": bubble_label,
			"timer": timer,
		}


func clear_members() -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		for key in ["name_label", "bubble_group", "timer"]:
			var node := slot.get(key) as Node
			if is_instance_valid(node):
				node.queue_free()
	_slots.clear()


func set_presence(user_id: String, presence: PresenceState.Value) -> void:
	if not _slots.has(user_id):
		return
	var slot := _slots[user_id] as Dictionary
	var member := slot["member"] as Dictionary
	member["presence"] = str(PresenceState.to_string_name(presence))
	slot["member"] = member


func show_message(user_id: String, body: String) -> void:
	if not _slots.has(user_id):
		return
	var slot := _slots[user_id] as Dictionary
	var bubble_group := slot["bubble_group"] as Control
	var label := slot["bubble_label"] as Label
	var timer := slot["timer"] as Timer
	label.text = body
	bubble_group.visible = true
	timer.start()


func hide_all_messages() -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		(slot["bubble_group"] as Control).visible = false
		(slot["timer"] as Timer).stop()


func set_identities_visible(identities_visible: bool) -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		(slot["name_label"] as Label).visible = identities_visible


static func _world_x_to_canvas(world_x: float) -> float:
	return (world_x / CHARACTER_VIEW_WIDTH + 0.5) * LOGICAL_WIDTH
