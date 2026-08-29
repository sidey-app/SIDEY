class_name SettingsStore
extends RefCounted

const CURRENT_SCHEMA_VERSION := 3
const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const DEFAULT_SETTINGS := {
	"schema_version": CURRENT_SCHEMA_VERSION,
	"overlay": {
		"screen": -1,
		"screen_signature": "",
		"position": [0, 0],
		"scale": OverlayGeometryScript.MIN_SCALE,
		"visible": true,
		"locked": true,
	},
	"quiet_mode": false,
	"local_state": {},
}

var _path: String
var _settings: Dictionary


func _init(path: String = "user://settings.json") -> void:
	_path = path
	_settings = DEFAULT_SETTINGS.duplicate(true)
	load_settings()


func load_settings() -> Error:
	if not FileAccess.file_exists(_path):
		_settings = DEFAULT_SETTINGS.duplicate(true)
		return OK
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		_settings = DEFAULT_SETTINGS.duplicate(true)
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_settings = DEFAULT_SETTINGS.duplicate(true)
		return ERR_PARSE_ERROR
	_settings = migrate(parsed as Dictionary)
	return OK


func save() -> Error:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_settings, "\t"))
	file.flush()
	return OK


func overlay() -> Dictionary:
	return (_settings.get("overlay", {}) as Dictionary).duplicate(true)


func quiet_mode() -> bool:
	return bool(_settings.get("quiet_mode", false))


func local_state() -> Dictionary:
	return (_settings.get("local_state", {}) as Dictionary).duplicate(true)


func set_overlay_geometry(
	position: Vector2i,
	scale: float,
	screen: int,
	screen_signature: String,
) -> Error:
	var overlay_settings := _settings.get("overlay", {}) as Dictionary
	overlay_settings["position"] = [position.x, position.y]
	overlay_settings["scale"] = OverlayGeometryScript.clamp_scale(scale)
	overlay_settings["screen"] = screen
	overlay_settings["screen_signature"] = screen_signature
	_settings["overlay"] = overlay_settings
	return save()


func set_overlay_visible(visible: bool) -> Error:
	var overlay_settings := _settings.get("overlay", {}) as Dictionary
	overlay_settings["visible"] = visible
	_settings["overlay"] = overlay_settings
	return save()


func set_overlay_locked(locked: bool) -> Error:
	var overlay_settings := _settings.get("overlay", {}) as Dictionary
	overlay_settings["locked"] = locked
	_settings["overlay"] = overlay_settings
	return save()


func set_quiet_mode(enabled: bool) -> Error:
	_settings["quiet_mode"] = enabled
	return save()


func set_local_state(state: Dictionary) -> Error:
	# Local state is a non-secret cache. Refresh tokens and invite-code plaintext
	# belong in the platform secure store and must never be passed here.
	_settings["local_state"] = state.duplicate(true)
	return save()


static func migrate(raw_settings: Dictionary) -> Dictionary:
	var migrated := DEFAULT_SETTINGS.duplicate(true)
	var source_version := int(raw_settings.get("schema_version", 0))
	if source_version <= 0:
		var legacy_position := [
			int(raw_settings.get("overlay_position_x", 0)),
			int(raw_settings.get("overlay_position_y", 0)),
		]
		migrated["overlay"]["position"] = legacy_position
		migrated["overlay"]["scale"] = OverlayGeometryScript.clamp_scale(
			float(raw_settings.get("overlay_scale", 1.0)),
		)
	else:
		var raw_overlay: Dictionary = raw_settings.get("overlay", {}) as Dictionary
		var raw_position: Array = raw_overlay.get("position", [0, 0]) as Array
		if raw_position.size() >= 2:
			migrated["overlay"]["position"] = [int(raw_position[0]), int(raw_position[1])]
		migrated["overlay"]["scale"] = OverlayGeometryScript.clamp_scale(
			float(raw_overlay.get("scale", 1.0)),
		)
		migrated["overlay"]["screen"] = int(raw_overlay.get("screen", -1))
		migrated["overlay"]["screen_signature"] = str(raw_overlay.get("screen_signature", ""))
		migrated["overlay"]["visible"] = bool(raw_overlay.get("visible", true))
		migrated["overlay"]["locked"] = bool(raw_overlay.get("locked", true))
	migrated["quiet_mode"] = bool(raw_settings.get("quiet_mode", false))
	if source_version >= 2 and raw_settings.get("local_state") is Dictionary:
		migrated["local_state"] = (raw_settings["local_state"] as Dictionary).duplicate(true)
	migrated["schema_version"] = CURRENT_SCHEMA_VERSION
	return migrated
