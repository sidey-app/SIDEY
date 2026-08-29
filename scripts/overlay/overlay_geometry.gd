class_name OverlayGeometry
extends RefCounted

const MIN_SCALE := 1.50
const MAX_SCALE := 2.00


static func clamp_scale(value: float) -> float:
	return clampf(value, MIN_SCALE, MAX_SCALE)


static func scaled_window_size(base_size: Vector2i, scale: float) -> Vector2i:
	var safe_scale := clamp_scale(scale)
	return Vector2i(
		maxi(1, roundi(base_size.x * safe_scale)),
		maxi(1, roundi(base_size.y * safe_scale)),
	)


static func centered_scaled_position(
	current_position: Vector2i,
	current_size: Vector2i,
	next_size: Vector2i,
) -> Vector2i:
	return current_position + Vector2i(
		roundi((current_size.x - next_size.x) * 0.5),
		roundi((current_size.y - next_size.y) * 0.5),
	)


static func clamp_position(
	position: Vector2i,
	window_size: Vector2i,
	usable_rect: Rect2i,
) -> Vector2i:
	var max_x := usable_rect.end.x - window_size.x
	var max_y := usable_rect.end.y - window_size.y
	if max_x < usable_rect.position.x:
		max_x = usable_rect.position.x
	if max_y < usable_rect.position.y:
		max_y = usable_rect.position.y
	return Vector2i(
		clampi(position.x, usable_rect.position.x, max_x),
		clampi(position.y, usable_rect.position.y, max_y),
	)


static func screen_signature(size: Vector2i, scale: float) -> String:
	return "%dx%d@%.3f" % [size.x, size.y, scale]


static func resolve_screen(
	saved_index: int,
	saved_signature: String,
	screens: Array[Dictionary],
	primary_index: int,
) -> int:
	if screens.is_empty():
		return 0
	if saved_index >= 0 and saved_index < screens.size():
		var indexed_signature := str(screens[saved_index].get("signature", ""))
		if saved_signature.is_empty() or indexed_signature == saved_signature:
			return saved_index
	if not saved_signature.is_empty():
		for screen in screens:
			if str(screen.get("signature", "")) == saved_signature:
				return int(screen.get("index", primary_index))
	return clampi(primary_index, 0, screens.size() - 1)
