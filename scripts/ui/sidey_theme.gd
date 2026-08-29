class_name SideyTheme
extends RefCounted

const BACKGROUND := Color("f7f8fa")
const SURFACE := Color("ffffff")
const FIELD := Color("f2f4f6")
const TEXT_PRIMARY := Color("191f28")
const TEXT_SECONDARY := Color("6b7684")
const TEXT_MUTED := Color("8b95a1")
const DIVIDER := Color("e5e8eb")
const BLUE := Color("3182f6")
const BLUE_HOVER := Color("1b64da")
const BLUE_PRESSED := Color("1957b8")
const DANGER := Color("f04452")
const SUCCESS := Color("20b486")


static func create() -> Theme:
	var theme := Theme.new()
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray([
		"Pretendard Variable",
		"Pretendard",
		"SF Pro Text",
		"Apple SD Gothic Neo",
		"Segoe UI",
		"Noto Sans CJK KR",
		"Arial",
	])
	theme.default_font = system_font
	theme.default_font_size = 18

	theme.set_font_size(&"font_size", &"Label", 18)
	theme.set_color(&"font_color", &"Label", TEXT_PRIMARY)
	theme.set_color(&"font_shadow_color", &"Label", Color(0.0, 0.0, 0.0, 0.0))

	_configure_button(theme, &"Button", BLUE, BLUE_HOVER, BLUE_PRESSED, Color.WHITE)
	theme.set_font_size(&"font_size", &"Button", 17)
	theme.set_color(&"font_disabled_color", &"Button", Color("b0b8c1"))
	theme.set_stylebox(&"disabled", &"Button", _style(Color("e5e8eb"), 14, Vector4(18, 12, 18, 12)))

	theme.set_type_variation(&"SideySecondaryButton", &"Button")
	_configure_button(
		theme,
		&"SideySecondaryButton",
		FIELD,
		Color("e5e8eb"),
		Color("d1d6db"),
		TEXT_PRIMARY,
	)
	theme.set_type_variation(&"SideyDangerButton", &"Button")
	_configure_button(
		theme,
		&"SideyDangerButton",
		Color("fff0f1"),
		Color("ffe0e3"),
		Color("ffc9ce"),
		DANGER,
	)
	theme.set_type_variation(&"SideyOverlayButton", &"Button")
	_configure_button(
		theme,
		&"SideyOverlayButton",
		Color(0.95, 0.96, 0.98, 0.96),
		Color.WHITE,
		Color("e5e8eb"),
		TEXT_PRIMARY,
		12,
		Vector4(12, 6, 12, 6),
	)

	for control_type in [&"LineEdit", &"TextEdit"]:
		theme.set_font_size(&"font_size", control_type, 18)
		theme.set_color(&"font_color", control_type, TEXT_PRIMARY)
		theme.set_color(&"font_placeholder_color", control_type, TEXT_MUTED)
		theme.set_color(&"caret_color", control_type, BLUE)
		theme.set_color(&"selection_color", control_type, Color(0.19, 0.51, 0.96, 0.22))
		theme.set_stylebox(&"normal", control_type, _style(FIELD, 14, Vector4(16, 13, 16, 13)))
		theme.set_stylebox(
			&"focus",
			control_type,
			_style(SURFACE, 14, Vector4(15, 12, 15, 12), BLUE, 2),
		)
		theme.set_stylebox(&"read_only", control_type, _style(Color("f7f8fa"), 14, Vector4(16, 13, 16, 13)))

	theme.set_font_size(&"font_size", &"OptionButton", 17)
	theme.set_color(&"font_color", &"OptionButton", TEXT_PRIMARY)
	theme.set_stylebox(&"normal", &"OptionButton", _style(FIELD, 14, Vector4(16, 12, 38, 12)))
	theme.set_stylebox(&"hover", &"OptionButton", _style(Color("e5e8eb"), 14, Vector4(16, 12, 38, 12)))
	theme.set_stylebox(&"pressed", &"OptionButton", _style(Color("d1d6db"), 14, Vector4(16, 12, 38, 12)))

	theme.set_stylebox(
		&"panel",
		&"PanelContainer",
		_style(SURFACE, 20, Vector4(24, 22, 24, 22), DIVIDER, 1, Color(0.08, 0.11, 0.16, 0.08), 18),
	)
	theme.set_color(&"font_color", &"CheckBox", TEXT_PRIMARY)
	theme.set_font_size(&"font_size", &"CheckBox", 17)
	theme.set_constant(&"separation", &"CheckBox", 10)
	theme.set_color(&"font_color", &"PopupMenu", TEXT_PRIMARY)
	theme.set_font_size(&"font_size", &"PopupMenu", 17)
	theme.set_stylebox(&"panel", &"PopupMenu", _style(SURFACE, 14, Vector4(8, 8, 8, 8), DIVIDER, 1))
	theme.set_stylebox(&"separator", &"HSeparator", _line_style(DIVIDER))
	return theme


static func overlay_panel_style() -> StyleBoxFlat:
	return _style(
		Color(1.0, 1.0, 1.0, 0.96),
		18,
		Vector4(8, 6, 8, 6),
		Color(1.0, 1.0, 1.0, 0.7),
		1,
		Color(0.0, 0.0, 0.0, 0.18),
		16,
	)


static func message_bubble_style() -> StyleBoxFlat:
	return _style(
		Color(1.0, 1.0, 1.0, 0.99),
		18,
		Vector4(14, 10, 14, 10),
		Color(1.0, 1.0, 1.0, 0.75),
		1,
		Color(0.0, 0.0, 0.0, 0.18),
		14,
	)


static func _configure_button(
	theme: Theme,
	theme_type: StringName,
	normal_color: Color,
	hover_color: Color,
	pressed_color: Color,
	font_color: Color,
	radius := 14,
	margins := Vector4(18, 12, 18, 12),
) -> void:
	theme.set_color(&"font_color", theme_type, font_color)
	theme.set_color(&"font_hover_color", theme_type, font_color)
	theme.set_color(&"font_pressed_color", theme_type, font_color)
	theme.set_stylebox(&"normal", theme_type, _style(normal_color, radius, margins))
	theme.set_stylebox(&"hover", theme_type, _style(hover_color, radius, margins))
	theme.set_stylebox(&"pressed", theme_type, _style(pressed_color, radius, margins))
	theme.set_stylebox(&"focus", theme_type, StyleBoxEmpty.new())


static func _style(
	color: Color,
	radius: int,
	margins: Vector4,
	border_color := Color.TRANSPARENT,
	border_width := 0,
	shadow_color := Color.TRANSPARENT,
	shadow_size := 0,
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
	style.shadow_color = shadow_color
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0.0, 6.0)
	return style


static func _line_style(color: Color) -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = color
	style.thickness = 1
	return style
