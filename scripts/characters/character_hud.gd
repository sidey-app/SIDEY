class_name CharacterHud
extends Control

const LOGICAL_WIDTH := 720.0
const CHARACTER_VIEW_WIDTH := 2.96
const BUBBLE_SECONDS := 10.0

var _slots: Dictionary = {}
var _room_label: Label
var _reconnect_elapsed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_label = Label.new()
	_room_label.position = Vector2(470.0, 12.0)
	_room_label.size = Vector2(238.0, 26.0)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_room_label.add_theme_font_size_override("font_size", 14)
	_room_label.add_theme_color_override("font_color", Color("d7e9ed"))
	add_child(_room_label)
	set_process(true)


func configure_room(room: Dictionary) -> void:
	clear_members()
	_room_label.text = str(room.get("name", ""))
	var members: Array = room.get("members", []) as Array
	var positions := CharacterRow.layout_positions(members.size())
	for index in members.size():
		var member := (members[index] as Dictionary).duplicate(true)
		var user_id := str(member.get("user_id", ""))
		var center_x := _world_x_to_canvas(positions[index])
		var identity_panel := PanelContainer.new()
		identity_panel.position = Vector2(center_x - 61.0, 286.0)
		identity_panel.size = Vector2(122.0, 28.0)
		identity_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var identity_style := StyleBoxFlat.new()
		identity_style.bg_color = Color(0.04, 0.07, 0.09, 0.78)
		identity_style.corner_radius_top_left = 10
		identity_style.corner_radius_top_right = 10
		identity_style.corner_radius_bottom_left = 10
		identity_style.corner_radius_bottom_right = 10
		identity_style.content_margin_left = 7.0
		identity_style.content_margin_right = 7.0
		identity_panel.add_theme_stylebox_override("panel", identity_style)
		add_child(identity_panel)
		var identity_row := HBoxContainer.new()
		identity_row.add_theme_constant_override("separation", 2)
		identity_panel.add_child(identity_row)
		var dot := Label.new()
		dot.custom_minimum_size = Vector2(14.0, 0.0)
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 12)
		identity_row.add_child(dot)
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(92.0, 0.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text = "%s%s" % [
			str(member.get("nickname", "친구")),
			" · 나" if bool(member.get("is_self", false)) else "",
		]
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color("e8f2f4"))
		identity_row.add_child(name_label)
		var bubble := PanelContainer.new()
		bubble.position = Vector2(center_x - 65.0, 58.0 + (index % 2) * 8.0)
		bubble.size = Vector2(130.0, 62.0)
		bubble.visible = false
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bubble_style := StyleBoxFlat.new()
		bubble_style.bg_color = Color(0.08, 0.12, 0.15, 0.94)
		bubble_style.corner_radius_top_left = 12
		bubble_style.corner_radius_top_right = 12
		bubble_style.corner_radius_bottom_left = 12
		bubble_style.corner_radius_bottom_right = 12
		bubble_style.content_margin_left = 10.0
		bubble_style.content_margin_right = 10.0
		bubble_style.content_margin_top = 7.0
		bubble_style.content_margin_bottom = 7.0
		bubble.add_theme_stylebox_override("panel", bubble_style)
		add_child(bubble)
		var bubble_label := Label.new()
		bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bubble_label.add_theme_font_size_override("font_size", 12)
		bubble.add_child(bubble_label)
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = BUBBLE_SECONDS
		timer.timeout.connect(func() -> void: bubble.visible = false)
		add_child(timer)
		_slots[user_id] = {
			"member": member,
			"identity_panel": identity_panel,
			"dot": dot,
			"bubble": bubble,
			"bubble_label": bubble_label,
			"timer": timer,
		}
		set_presence(user_id, PresenceState.from_string(str(member.get("presence", "offline"))))


func clear_members() -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		for key in ["identity_panel", "bubble", "timer"]:
			var node := slot.get(key) as Node
			if is_instance_valid(node):
				node.queue_free()
	_slots.clear()
	if is_instance_valid(_room_label):
		_room_label.text = ""


func set_presence(user_id: String, presence: PresenceState.Value) -> void:
	if not _slots.has(user_id):
		return
	var slot := _slots[user_id] as Dictionary
	var member := slot["member"] as Dictionary
	member["presence"] = str(PresenceState.to_string_name(presence))
	slot["member"] = member
	var dot := slot["dot"] as Label
	dot.add_theme_color_override("font_color", PresenceState.indicator_color(presence))
	dot.modulate.a = 1.0


func show_message(user_id: String, body: String) -> void:
	if not _slots.has(user_id):
		return
	var slot := _slots[user_id] as Dictionary
	var bubble := slot["bubble"] as PanelContainer
	var label := slot["bubble_label"] as Label
	var timer := slot["timer"] as Timer
	label.text = body
	bubble.visible = true
	timer.start()


func hide_all_messages() -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		(slot["bubble"] as PanelContainer).visible = false
		(slot["timer"] as Timer).stop()


func set_identities_visible(identities_visible: bool) -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		(slot["identity_panel"] as PanelContainer).visible = identities_visible


func _process(delta: float) -> void:
	_reconnect_elapsed += delta
	var reconnect_alpha := 0.35 if fmod(_reconnect_elapsed, 1.0) < 0.5 else 1.0
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		var member := slot["member"] as Dictionary
		if str(member.get("presence", "")) == "reconnecting":
			(slot["dot"] as Label).modulate.a = reconnect_alpha


static func _world_x_to_canvas(world_x: float) -> float:
	return (world_x / CHARACTER_VIEW_WIDTH + 0.5) * LOGICAL_WIDTH
