extends SceneTree

const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run_geometry_tests()
	_run_settings_tests()
	if _failures == 0:
		print("SIDEY_UNIT_TESTS_OK checks=%d" % _checks)
		quit(0)
	else:
		push_error("SIDEY_UNIT_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
		quit(1)


func _run_geometry_tests() -> void:
	_check_equal(OverlayGeometryScript.scaled_window_size(Vector2i(400, 300), 0.2), Vector2i(280, 210), "scale lower bound")
	_check_equal(OverlayGeometryScript.scaled_window_size(Vector2i(400, 300), 2.0), Vector2i(600, 450), "scale upper bound")
	_check_equal(
		OverlayGeometryScript.centered_scaled_position(Vector2i(100, 100), Vector2i(400, 300), Vector2i(600, 450)),
		Vector2i(0, 25),
		"centered scaling",
	)
	var usable_rect := Rect2i(100, 50, 1200, 800)
	_check_equal(OverlayGeometryScript.clamp_position(Vector2i(-500, 900), Vector2i(400, 300), usable_rect), Vector2i(100, 550), "usable rect clamp")
	_check_equal(OverlayGeometryScript.clamp_position(Vector2i(500, 400), Vector2i(2000, 1200), usable_rect), usable_rect.position, "oversize window clamp")
	var screens: Array[Dictionary] = [
		{"index": 0, "signature": "1920x1080@1.000"},
		{"index": 1, "signature": "2560x1440@2.000"},
	]
	_check_equal(OverlayGeometryScript.resolve_screen(1, "2560x1440@2.000", screens, 0), 1, "saved screen")
	_check_equal(OverlayGeometryScript.resolve_screen(0, "2560x1440@2.000", screens, 0), 1, "screen signature relocation")
	_check_equal(OverlayGeometryScript.resolve_screen(8, "missing", screens, 1), 1, "primary screen fallback")


func _run_settings_tests() -> void:
	var path := "/tmp/sidey-settings-test-%d.json" % OS.get_process_id()
	var store = SettingsStoreScript.new(path)
	_check_equal(store.overlay()["locked"], true, "settings default locked")
	_check_equal(store.set_overlay_geometry(Vector2i(123, 456), 1.25, 2, "screen-a"), OK, "settings save geometry")
	_check_equal(store.set_overlay_locked(false), OK, "settings save lock")
	_check_equal(store.set_quiet_mode(true), OK, "settings save quiet mode")
	var restored = SettingsStoreScript.new(path)
	_check_equal(restored.overlay()["position"], [123, 456], "settings restore position")
	_check_equal(restored.overlay()["scale"], 1.25, "settings restore scale")
	_check_equal(restored.overlay()["locked"], false, "settings restore lock")
	_check_equal(restored.quiet_mode(), true, "settings restore quiet mode")
	var migrated := SettingsStoreScript.migrate({
		"overlay_position_x": 99,
		"overlay_position_y": 77,
		"overlay_scale": 9.0,
	})
	_check_equal(migrated["schema_version"], SettingsStoreScript.CURRENT_SCHEMA_VERSION, "settings schema migration")
	_check_equal(migrated["overlay"]["position"], [99, 77], "settings legacy position")
	_check_equal(migrated["overlay"]["scale"], OverlayGeometryScript.MAX_SCALE, "settings migration clamp")
	DirAccess.remove_absolute(path)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failures += 1
	push_error("TEST_FAILED %s expected=%s actual=%s" % [label, expected, actual])
