class_name OverlayTheme
extends RefCounted

const HUD_BACKGROUND := Color(0.02, 0.025, 0.03, 0.72)
const HUD_BACKGROUND_HOVER := Color(0.04, 0.05, 0.06, 0.82)
const TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 0.98)
const TEXT_SECONDARY := Color(1.0, 1.0, 1.0, 0.62)


static func identity_pill_style() -> StyleBoxFlat:
	return _style(HUD_BACKGROUND, 14, Vector4(10, 5, 10, 5))


static func self_badge_style() -> StyleBoxFlat:
	return _style(Color(1.0, 1.0, 1.0, 0.15), 8, Vector4(6, 2, 6, 2))


static func presence_dot_style(color: Color) -> StyleBoxFlat:
	return _style(color, 5, Vector4.ZERO)


static func composer_style(focused := false) -> StyleBoxFlat:
	return _style(
		Color(0.02, 0.025, 0.03, 0.84 if focused else 0.72),
		14,
		Vector4(12, 8, 12, 8),
		Color(1.0, 1.0, 1.0, 0.22) if focused else Color.TRANSPARENT,
		1 if focused else 0,
	)


static func tray_style() -> StyleBoxFlat:
	return _style(HUD_BACKGROUND, 14, Vector4(6, 6, 6, 6))


static func history_style() -> StyleBoxFlat:
	return _style(Color(0.02, 0.025, 0.03, 0.92), 18, Vector4(16, 14, 16, 14))


static func style_icon_button(button: Button) -> void:
	button.add_theme_color_override("icon_normal_color", TEXT_PRIMARY)
	button.add_theme_color_override("icon_hover_color", Color.WHITE)
	button.add_theme_color_override("icon_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color.TRANSPARENT, 10, Vector4(5, 5, 5, 5)))
	button.add_theme_stylebox_override("hover", _style(Color(1.0, 1.0, 1.0, 0.12), 10, Vector4(5, 5, 5, 5)))
	button.add_theme_stylebox_override("pressed", _style(Color(1.0, 1.0, 1.0, 0.2), 10, Vector4(5, 5, 5, 5)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


static func _style(
	color: Color,
	radius: int,
	margins: Vector4,
	border_color := Color.TRANSPARENT,
	border_width := 0,
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = margins.x
	style.content_margin_top = margins.y
	style.content_margin_right = margins.z
	style.content_margin_bottom = margins.w
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	return style
