class_name CharacterHud
extends Control

const SideyThemeScript := preload("res://scripts/ui/sidey_theme.gd")
const OverlayThemeScript := preload("res://scripts/ui/overlay_theme.gd")
const LOGICAL_WIDTH := 720.0
const CHARACTER_VIEW_WIDTH := 2.96
const BUBBLE_SECONDS := 10.0
const IDENTITY_Y := 288.0
const IDENTITY_HEIGHT := 30.0
const SINGLE_BUBBLE_SIZE := Vector2(252.0, 70.0)
const MULTI_BUBBLE_SIZE := Vector2(170.0, 54.0)
const BUBBLE_EDGE_MARGIN := 8.0
const MULTI_BUBBLE_LANES := [8.0, 76.0]
const RECONNECT_BLINK_SECONDS := 0.48

var _slots: Dictionary = {}
var _self_anchor_x := LOGICAL_WIDTH * 0.5
var _reconnect_elapsed := 0.0
var _reconnect_bright := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func configure_room(room: Dictionary) -> void:
	clear_members()
	var members: Array = room.get("members", []) as Array
	var positions := CharacterRow.layout_positions(members.size())
	for index in members.size():
		var member := (members[index] as Dictionary).duplicate(true)
		var user_id := str(member.get("user_id", ""))
		var center_x := _world_x_to_canvas(positions[index])
		if bool(member.get("is_self", false)):
			_self_anchor_x = center_x
		var identity_panel := _build_identity_panel(member, center_x)
		var name_label := identity_panel.get_node("IdentityRow/Nickname") as Label
		var presence_dot := identity_panel.get_node("IdentityRow/PresenceDot") as Panel
		add_child(identity_panel)

		var bubble_group := _build_bubble_group(center_x, index, members.size())
		add_child(bubble_group)
		var bubble := bubble_group.get_node("Bubble") as PanelContainer
		var bubble_label := bubble.get_node("Message") as Label
		var timer := Timer.new()
		timer.name = "BubbleTimer_%s" % user_id.validate_node_name()
		timer.one_shot = true
		timer.wait_time = BUBBLE_SECONDS
		timer.timeout.connect(func() -> void: bubble_group.visible = false)
		add_child(timer)
		_slots[user_id] = {
			"member": member,
			"identity_panel": identity_panel,
			"name_label": name_label,
			"presence_dot": presence_dot,
			"bubble_group": bubble_group,
			"bubble_label": bubble_label,
			"timer": timer,
		}
		_set_presence_visual(_slots[user_id] as Dictionary, PresenceState.from_string(str(member.get("presence", "offline"))))
	_update_reconnect_processing()


func _build_identity_panel(member: Dictionary, center_x: float) -> PanelContainer:
	var nickname := str(member.get("nickname", "친구"))
	var is_self := bool(member.get("is_self", false))
	var width := clampf(58.0 + nickname.length() * 17.0 + (28.0 if is_self else 0.0), 96.0, 178.0)
	var panel := PanelContainer.new()
	panel.name = "Identity_%s" % str(member.get("user_id", "member")).validate_node_name()
	panel.position = Vector2(center_x - width * 0.5, IDENTITY_Y)
	panel.size = Vector2(width, IDENTITY_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", OverlayThemeScript.identity_pill_style())
	var row := HBoxContainer.new()
	row.name = "IdentityRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var dot := Panel.new()
	dot.name = "PresenceDot"
	dot.custom_minimum_size = Vector2(9.0, 9.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var name_label := Label.new()
	name_label.name = "Nickname"
	name_label.custom_minimum_size.x = minf(nickname.length() * 17.0, 92.0)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text = nickname
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", OverlayThemeScript.TEXT_PRIMARY)
	row.add_child(name_label)
	if is_self:
		var self_badge := Label.new()
		self_badge.name = "SelfBadge"
		self_badge.text = "나"
		self_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		self_badge.add_theme_font_size_override("font_size", 13)
		self_badge.add_theme_color_override("font_color", OverlayThemeScript.TEXT_PRIMARY)
		self_badge.add_theme_stylebox_override("normal", OverlayThemeScript.self_badge_style())
		row.add_child(self_badge)
	return panel


func _build_bubble_group(center_x: float, index: int, member_count: int) -> Control:
	var bubble_size := SINGLE_BUBBLE_SIZE if member_count == 1 else MULTI_BUBBLE_SIZE
	var lane_y: float = 6.0 if member_count == 1 else float(MULTI_BUBBLE_LANES[index % MULTI_BUBBLE_LANES.size()])
	var left := clampf(
		center_x - bubble_size.x * 0.5,
		BUBBLE_EDGE_MARGIN,
		LOGICAL_WIDTH - BUBBLE_EDGE_MARGIN - bubble_size.x,
	)
	var tail_center_x := clampf(center_x - left, 18.0, bubble_size.x - 18.0)
	var group := Control.new()
	group.name = "BubbleGroup_%d" % index
	group.position = Vector2(left, lane_y)
	group.size = Vector2(bubble_size.x, bubble_size.y + 10.0)
	group.visible = false
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.custom_minimum_size = bubble_size
	bubble.size = bubble_size
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", SideyThemeScript.message_bubble_style())
	group.add_child(bubble)
	var bubble_label := Label.new()
	bubble_label.name = "Message"
	bubble_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bubble_label.add_theme_font_size_override("font_size", 15 if member_count > 1 else 17)
	bubble_label.add_theme_color_override("font_color", SideyThemeScript.TEXT_PRIMARY)
	bubble.add_child(bubble_label)
	var tail := Polygon2D.new()
	tail.name = "Tail"
	tail.position = Vector2(tail_center_x - 9.0, bubble_size.y - 1.0)
	tail.polygon = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(18.0, 0.0),
		Vector2(9.0, 9.0),
	])
	tail.color = Color(1.0, 1.0, 1.0, 0.99)
	group.add_child(tail)
	return group


func clear_members() -> void:
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		for key in ["identity_panel", "bubble_group", "timer"]:
			var node := slot.get(key) as Node
			if is_instance_valid(node):
				node.queue_free()
	_slots.clear()
	_self_anchor_x = LOGICAL_WIDTH * 0.5
	set_process(false)


func set_presence(user_id: String, presence: PresenceState.Value) -> void:
	if not _slots.has(user_id):
		return
	var slot := _slots[user_id] as Dictionary
	var member := slot["member"] as Dictionary
	member["presence"] = str(PresenceState.to_string_name(presence))
	slot["member"] = member
	_set_presence_visual(slot, presence)
	_update_reconnect_processing()


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
		(slot["identity_panel"] as PanelContainer).visible = identities_visible


func self_anchor_x() -> float:
	return _self_anchor_x


func identity_rect(user_id: String) -> Rect2:
	if not _slots.has(user_id):
		return Rect2()
	var panel := (_slots[user_id] as Dictionary)["identity_panel"] as PanelContainer
	return Rect2(panel.position, panel.size)


func bubble_rect(user_id: String) -> Rect2:
	if not _slots.has(user_id):
		return Rect2()
	var group := (_slots[user_id] as Dictionary)["bubble_group"] as Control
	return Rect2(group.position, group.size)


func presence_color(user_id: String) -> Color:
	if not _slots.has(user_id):
		return Color.TRANSPARENT
	var dot := (_slots[user_id] as Dictionary)["presence_dot"] as Panel
	var style := dot.get_theme_stylebox("panel") as StyleBoxFlat
	return style.bg_color if style != null else Color.TRANSPARENT


func presence_dot_alpha(user_id: String) -> float:
	if not _slots.has(user_id):
		return 0.0
	return ((_slots[user_id] as Dictionary)["presence_dot"] as Panel).modulate.a


func _process(delta: float) -> void:
	_reconnect_elapsed += delta
	if _reconnect_elapsed < RECONNECT_BLINK_SECONDS:
		return
	_reconnect_elapsed = fmod(_reconnect_elapsed, RECONNECT_BLINK_SECONDS)
	_reconnect_bright = not _reconnect_bright
	for slot_value in _slots.values():
		var slot := slot_value as Dictionary
		var member := slot["member"] as Dictionary
		if PresenceState.from_string(str(member.get("presence", "offline"))) == PresenceState.Value.RECONNECTING:
			(slot["presence_dot"] as Panel).modulate.a = 1.0 if _reconnect_bright else 0.28


func _set_presence_visual(slot: Dictionary, presence: PresenceState.Value) -> void:
	var dot := slot["presence_dot"] as Panel
	dot.add_theme_stylebox_override("panel", OverlayThemeScript.presence_dot_style(PresenceState.indicator_color(presence)))
	dot.modulate.a = 1.0


func _update_reconnect_processing() -> void:
	var reconnecting := false
	for slot_value in _slots.values():
		var member := (slot_value as Dictionary)["member"] as Dictionary
		if PresenceState.from_string(str(member.get("presence", "offline"))) == PresenceState.Value.RECONNECTING:
			reconnecting = true
			break
	_reconnect_elapsed = 0.0
	_reconnect_bright = true
	set_process(reconnecting)


static func _world_x_to_canvas(world_x: float) -> float:
	return (world_x / CHARACTER_VIEW_WIDTH + 0.5) * LOGICAL_WIDTH
