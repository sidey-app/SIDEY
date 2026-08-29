extends SceneTree

const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")
const CharacterRowScript := preload("res://scripts/characters/character_row.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const PresenceStateScript := preload("res://scripts/characters/presence_state.gd")
const ChatStoreScript := preload("res://scripts/chat/chat_store.gd")
const TypingTrackerScript := preload("res://scripts/chat/typing_tracker.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run_geometry_tests()
	_run_settings_tests()
	_run_character_data_tests()
	_run_presence_state_tests()
	_run_chat_store_tests()
	_run_typing_tracker_tests()
	_run_room_controller_tests()
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
	_check_equal(migrated["local_state"], {}, "settings migration initializes local state")
	DirAccess.remove_absolute(path)


func _run_character_data_tests() -> void:
	_check_equal(CharacterCatalogScript.has("minty_pup"), true, "catalog contains minty pup")
	_check_equal(CharacterCatalogScript.get_entry("missing"), {}, "catalog rejects unknown character")
	var single_position: Array[float] = [0.0]
	_check_equal(CharacterRowScript.layout_positions(1), single_position, "single character centered")
	var five_positions := CharacterRowScript.layout_positions(5)
	_check_equal(five_positions.size(), 5, "five character layout count")
	_check_approx(five_positions[0], -1.16, "five character layout start")
	_check_approx(five_positions[4], 1.16, "five character layout end")
	_check_equal(CharacterRowScript.layout_positions(8).size(), 5, "character row max five")


func _run_presence_state_tests() -> void:
	_check_equal(PresenceStateScript.motion_state(PresenceState.Value.ONLINE), CharacterState.Value.ONLINE_IDLE, "online motion mapping")
	_check_equal(PresenceStateScript.motion_state(PresenceState.Value.TYPING), CharacterState.Value.TYPING, "typing motion mapping")
	_check_equal(PresenceStateScript.motion_state(PresenceState.Value.AWAY), CharacterState.Value.OFFLINE_SLEEP, "away motion mapping")
	_check_equal(PresenceStateScript.motion_state(PresenceState.Value.OFFLINE), CharacterState.Value.OFFLINE_SLEEP, "offline motion mapping")
	_check_equal(PresenceStateScript.motion_state(PresenceState.Value.RECONNECTING), CharacterState.Value.OFFLINE_SLEEP, "reconnecting motion mapping")
	_check_equal(PresenceStateScript.from_string("invalid"), PresenceState.Value.OFFLINE, "unknown presence is offline")


func _run_chat_store_tests() -> void:
	var chat = ChatStoreScript.new()
	var message := {
		"id": "message-1",
		"room_id": "room-1",
		"sender_id": "user-1",
		"body": " 안녕 ",
		"created_at": 20.0,
	}
	_check_equal(chat.insert(message), OK, "chat accepts valid message")
	_check_equal(chat.insert(message), ERR_ALREADY_EXISTS, "chat deduplicates UUID")
	_check_equal(chat.recent("room-1")[0]["body"], "안녕", "chat trims message body")
	_check_equal(ChatStoreScript.validate_body(""), ERR_INVALID_PARAMETER, "chat rejects empty body")
	_check_equal(ChatStoreScript.validate_body("a".repeat(201)), ERR_INVALID_PARAMETER, "chat rejects long body")
	_check_equal(ChatStoreScript.validate_body("1\n2\n3"), OK, "chat accepts three lines")
	_check_equal(ChatStoreScript.validate_body("1\n2\n3\n4"), ERR_INVALID_PARAMETER, "chat rejects fourth line")


func _run_typing_tracker_tests() -> void:
	var tracker = TypingTrackerScript.new()
	_check_equal(tracker.note_input(10.0), &"typing_start", "typing starts on first input")
	_check_equal(tracker.note_input(11.0), &"", "typing does not spam start")
	_check_equal(tracker.poll(12.0), &"typing_keepalive", "typing keepalive every two seconds")
	_check_equal(tracker.poll(14.9), &"typing_keepalive", "typing keepalive continues before expiry")
	_check_equal(tracker.poll(15.0), &"typing_stop", "typing expires after four seconds")
	_check_equal(tracker.note_input(20.0), &"typing_start", "typing restarts after expiry")
	_check_equal(tracker.stop(), true, "typing explicit stop")
	_check_equal(tracker.stop(), false, "typing stop is idempotent")


func _run_room_controller_tests() -> void:
	var path := "/tmp/sidey-room-test-%d.json" % OS.get_process_id()
	var store = SettingsStoreScript.new(path)
	var rooms = RoomControllerScript.new()
	_check_equal(rooms.configure(store), OK, "room controller configure")
	_check_equal(rooms.set_profile("민트", "minty_pup"), OK, "profile validation")
	_check_equal(rooms.create_room("첫 그룹"), OK, "create first room")
	var first_room_id: String = rooms.active_room_id()
	_check_equal(rooms.join_demo_room("sidey-demo"), OK, "join demo room normalized code")
	_check_equal((rooms.active_room()["members"] as Array).size(), 5, "demo room has five members")
	_check_equal(rooms.set_active_room(first_room_id), OK, "switch active room")
	_check_equal(rooms.mark_message_received("demo-friends"), OK, "inactive room unread")
	_check_equal(rooms.unread_count("demo-friends"), 1, "unread count increments")
	_check_equal(rooms.set_active_room("demo-friends"), OK, "activate unread room")
	_check_equal(rooms.unread_count("demo-friends"), 0, "active room clears unread")
	_check_equal(rooms.rename_room("demo-friends", "권한 없음"), ERR_UNAUTHORIZED, "non-owner cannot rename room")
	_check_equal(rooms.set_active_room(first_room_id), OK, "return to owned room")
	_check_equal(rooms.rename_room(first_room_id, "이름 변경"), OK, "owner renames room")
	_check_equal(rooms.active_room()["name"], "이름 변경", "renamed room persists in model")
	_check_equal(rooms.set_profile(" 하 늘 ", "minty_pup"), ERR_ALREADY_EXISTS, "profile nickname conflict across rooms")
	for index in 3:
		_check_equal(rooms.create_room("추가 그룹 %d" % index), OK, "create room within user limit %d" % index)
	_check_equal(rooms.create_room("여섯 번째"), ERR_BUSY, "reject sixth room")
	_check_equal(rooms.complete_onboarding(), OK, "complete onboarding with profile and room")
	var restored = RoomControllerScript.new()
	_check_equal(restored.configure(SettingsStoreScript.new(path)), OK, "restore room state")
	_check_equal(restored.rooms().size(), 5, "restore five rooms")
	_check_equal(restored.is_onboarding_complete(), true, "restore onboarding state")
	_check_equal(RoomControllerScript.validate_nickname("한"), ERR_INVALID_PARAMETER, "nickname minimum length")
	_check_equal(RoomControllerScript.validate_room_name(""), ERR_INVALID_PARAMETER, "room name required")
	rooms.free()
	restored.free()
	DirAccess.remove_absolute(path)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failures += 1
	push_error("TEST_FAILED %s expected=%s actual=%s" % [label, expected, actual])


func _check_approx(actual: float, expected: float, label: String) -> void:
	_checks += 1
	if is_equal_approx(actual, expected):
		return
	_failures += 1
	push_error("TEST_FAILED %s expected=%s actual=%s" % [label, expected, actual])
