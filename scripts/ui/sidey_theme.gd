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
const STANDARD_WINDOW_MIN_SCALE := 1.0
const STANDARD_WINDOW_MAX_SCALE := 2.0


static func create() -> Theme:
	return _create_theme(false)


static func create_standard_window_theme() -> Theme:
	return _create_theme(true)


static func standard_window_scale(screen := DisplayServer.SCREEN_PRIMARY) -> float:
	return clampf(
		DisplayServer.screen_get_scale(screen),
		STANDARD_WINDOW_MIN_SCALE,
		STANDARD_WINDOW_MAX_SCALE,
	)


static func scaled_window_size(logical_size: Vector2i, scale: float) -> Vector2i:
	var safe_scale := clampf(scale, STANDARD_WINDOW_MIN_SCALE, STANDARD_WINDOW_MAX_SCALE)
	return Vector2i(
		int(round(logical_size.x * safe_scale)),
		int(round(logical_size.y * safe_scale)),
	)


static func _create_theme(standard_window: bool) -> Theme:
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
	theme.default_font_size = 20 if standard_window else 18

	theme.set_font_size(&"font_size", &"Label", 20 if standard_window else 18)
	theme.set_color(&"font_color", &"Label", TEXT_PRIMARY)
	theme.set_color(&"font_shadow_color", &"Label", Color(0.0, 0.0, 0.0, 0.0))

	_configure_button(
		theme,
		&"Button",
		BLUE,
		BLUE_HOVER,
		BLUE_PRESSED,
		Color.WHITE,
		14,
		Vector4(18, 12, 18, 12),
		standard_window,
	)
	theme.set_font_size(&"font_size", &"Button", 18 if standard_window else 17)
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
		14,
		Vector4(18, 12, 18, 12),
		standard_window,
	)
	theme.set_type_variation(&"SideyDangerButton", &"Button")
	_configure_button(
		theme,
		&"SideyDangerButton",
		Color("fff0f1"),
		Color("ffe0e3"),
		Color("ffc9ce"),
		DANGER,
		14,
		Vector4(18, 12, 18, 12),
		standard_window,
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
	if standard_window:
		_configure_standard_window_variations(theme)

	for control_type in [&"LineEdit", &"TextEdit"]:
		theme.set_font_size(&"font_size", control_type, 20 if standard_window else 18)
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

	theme.set_font_size(&"font_size", &"OptionButton", 19 if standard_window else 17)
	theme.set_color(&"font_color", &"OptionButton", TEXT_PRIMARY)
	theme.set_stylebox(&"normal", &"OptionButton", _style(FIELD, 14, Vector4(16, 12, 38, 12)))
	theme.set_stylebox(&"hover", &"OptionButton", _style(Color("e5e8eb"), 14, Vector4(16, 12, 38, 12)))
	theme.set_stylebox(&"pressed", &"OptionButton", _style(Color("d1d6db"), 14, Vector4(16, 12, 38, 12)))
	if standard_window:
		theme.set_stylebox(&"focus", &"OptionButton", _focus_style(14))

	theme.set_stylebox(
		&"panel",
		&"PanelContainer",
		_style(
			SURFACE,
			16 if standard_window else 20,
			Vector4(26, 24, 26, 24) if standard_window else Vector4(24, 22, 24, 22),
			DIVIDER,
			1,
			Color(0.08, 0.11, 0.16, 0.04) if standard_window else Color(0.08, 0.11, 0.16, 0.08),
			6 if standard_window else 18,
		),
	)
	theme.set_color(&"font_color", &"CheckBox", TEXT_PRIMARY)
	theme.set_font_size(&"font_size", &"CheckBox", 19 if standard_window else 17)
	theme.set_constant(&"separation", &"CheckBox", 10)
	if standard_window:
		theme.set_stylebox(&"focus", &"CheckBox", _focus_style(10))
	theme.set_color(&"font_color", &"PopupMenu", TEXT_PRIMARY)
	theme.set_font_size(&"font_size", &"PopupMenu", 18 if standard_window else 17)
	theme.set_stylebox(&"panel", &"PopupMenu", _style(SURFACE, 14, Vector4(8, 8, 8, 8), DIVIDER, 1))
	theme.set_stylebox(&"separator", &"HSeparator", _line_style(DIVIDER))
	if standard_window:
		theme.set_stylebox(&"panel", &"TabContainer", StyleBoxEmpty.new())
	return theme


static func _configure_standard_window_variations(theme: Theme) -> void:
	theme.set_type_variation(&"SideyNavigationButton", &"Button")
	_configure_button(
		theme,
		&"SideyNavigationButton",
		Color.TRANSPARENT,
		Color("e5e8eb"),
		Color("d1d6db"),
		TEXT_PRIMARY,
		12,
		Vector4(16, 12, 16, 12),
		true,
	)
	theme.set_type_variation(&"SideyNavigationButtonSelected", &"Button")
	_configure_button(
		theme,
		&"SideyNavigationButtonSelected",
		SURFACE,
		SURFACE,
		Color("e8f3ff"),
		BLUE,
		12,
		Vector4(16, 12, 16, 12),
		true,
	)
	theme.set_type_variation(&"SideySegmentButton", &"Button")
	_configure_button(
		theme,
		&"SideySegmentButton",
		FIELD,
		Color("e5e8eb"),
		Color("d1d6db"),
		TEXT_SECONDARY,
		12,
		Vector4(18, 10, 18, 10),
		true,
	)
	theme.set_type_variation(&"SideySegmentButtonSelected", &"Button")
	_configure_button(
		theme,
		&"SideySegmentButtonSelected",
		BLUE,
		BLUE_HOVER,
		BLUE_PRESSED,
		Color.WHITE,
		12,
		Vector4(18, 10, 18, 10),
		true,
	)
	theme.set_type_variation(&"SideyFeedbackSuccess", &"PanelContainer")
	theme.set_stylebox(
		&"panel",
		&"SideyFeedbackSuccess",
		_style(Color("effbf7"), 12, Vector4(16, 12, 16, 12), Color("b8ead9"), 1),
	)
	theme.set_type_variation(&"SideyFeedbackDanger", &"PanelContainer")
	theme.set_stylebox(
		&"panel",
		&"SideyFeedbackDanger",
		_style(Color("fff2f3"), 12, Vector4(16, 12, 16, 12), Color("ffc9ce"), 1),
	)


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
	show_focus := false,
) -> void:
	theme.set_color(&"font_color", theme_type, font_color)
	theme.set_color(&"font_hover_color", theme_type, font_color)
	theme.set_color(&"font_pressed_color", theme_type, font_color)
	theme.set_stylebox(&"normal", theme_type, _style(normal_color, radius, margins))
	theme.set_stylebox(&"hover", theme_type, _style(hover_color, radius, margins))
	theme.set_stylebox(&"pressed", theme_type, _style(pressed_color, radius, margins))
	theme.set_stylebox(&"focus", theme_type, _focus_style(radius) if show_focus else StyleBoxEmpty.new())


static func _focus_style(radius: int) -> StyleBoxFlat:
	return _style(Color.TRANSPARENT, radius, Vector4.ZERO, BLUE, 2)


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
