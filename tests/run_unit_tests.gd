extends SceneTree

const OverlayGeometryScript := preload("res://scripts/overlay/overlay_geometry.gd")
const SettingsStoreScript := preload("res://scripts/settings/settings_store.gd")
const CharacterCatalogScript := preload("res://scripts/characters/character_catalog.gd")
const CharacterRowScript := preload("res://scripts/characters/character_row.gd")
const RoomControllerScript := preload("res://scripts/rooms/room_controller.gd")
const PresenceStateScript := preload("res://scripts/characters/presence_state.gd")
const ChatStoreScript := preload("res://scripts/chat/chat_store.gd")
const TypingTrackerScript := preload("res://scripts/chat/typing_tracker.gd")
const BackendConfigScript := preload("res://scripts/backend/backend_config.gd")
const RealtimeProtocolScript := preload("res://scripts/backend/realtime_protocol.gd")
const ReconnectBackoffScript := preload("res://scripts/backend/reconnect_backoff.gd")
const RealtimeClientScript := preload("res://scripts/backend/realtime_client.gd")
const BackendRepositoryScript := preload("res://scripts/backend/backend_repository.gd")
const PresenceRosterScript := preload("res://scripts/backend/presence_roster.gd")
const ActivityPresenceScript := preload("res://scripts/platform/activity_presence.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run_geometry_tests()
	_run_settings_tests()
	_run_character_data_tests()
	_run_presence_state_tests()
	_run_activity_presence_tests()
	_run_chat_store_tests()
	_run_typing_tracker_tests()
	_run_backend_protocol_tests()
	_run_backend_repository_tests()
	_run_presence_roster_tests()
	_run_room_controller_tests()
	if _failures == 0:
		print("SIDEY_UNIT_TESTS_OK checks=%d" % _checks)
		quit(0)
	else:
		push_error("SIDEY_UNIT_TESTS_FAILED failures=%d checks=%d" % [_failures, _checks])
		quit(1)


func _run_geometry_tests() -> void:
	_check_equal(OverlayGeometryScript.scaled_window_size(Vector2i(400, 300), 0.2), Vector2i(600, 450), "scale lower bound")
	_check_equal(OverlayGeometryScript.scaled_window_size(Vector2i(400, 300), 3.0), Vector2i(800, 600), "scale upper bound")
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
	_check_equal(store.overlay()["scale"], OverlayGeometryScript.MIN_SCALE, "settings default readable scale")
	_check_equal(store.set_overlay_geometry(Vector2i(123, 456), 1.25, 2, "screen-a"), OK, "settings save geometry")
	_check_equal(store.set_overlay_locked(false), OK, "settings save lock")
	_check_equal(store.set_quiet_mode(true), OK, "settings save quiet mode")
	var restored = SettingsStoreScript.new(path)
	_check_equal(restored.overlay()["position"], [123, 456], "settings restore position")
	_check_equal(restored.overlay()["scale"], OverlayGeometryScript.MIN_SCALE, "settings restore scale")
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


func _run_activity_presence_tests() -> void:
	_check_equal(ActivityPresenceScript.state(false, false, 299.9), "online", "activity remains online before idle threshold")
	_check_equal(ActivityPresenceScript.state(false, false, 300.0), "away", "activity becomes away at idle threshold")
	_check_equal(ActivityPresenceScript.state(true, false, 0.0), "away", "screen lock forces away")
	_check_equal(ActivityPresenceScript.state(false, true, 0.0), "away", "system sleep forces away")


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
	var iso_chat = ChatStoreScript.new()
	iso_chat.insert({"id": "newer", "room_id": "room-iso", "sender_id": "user-1", "body": "둘", "created_at": "2026-08-29T02:00:00Z"})
	iso_chat.insert({"id": "older", "room_id": "room-iso", "sender_id": "user-1", "body": "하나", "created_at": "2026-08-29T01:00:00Z"})
	_check_equal(iso_chat.recent("room-iso")[0]["id"], "older", "chat sorts ISO server timestamps")


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


func _run_backend_protocol_tests() -> void:
	var config = BackendConfigScript.new("http://127.0.0.1:54321/", "sb_publishable_test")
	_check_equal(config.is_valid(), true, "backend config accepts publishable key")
	_check_equal(config.url, "http://127.0.0.1:54321", "backend config trims URL")
	_check_equal(config.realtime_url().begins_with("ws://127.0.0.1:54321/realtime/v1/websocket?"), true, "backend websocket URL")
	_check_equal(BackendConfigScript.new("https://example.test", "sb_secret_nope").is_valid(), false, "backend rejects secret key")
	var legacy_service_role := "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature"
	_check_equal(BackendConfigScript.new("https://example.test", legacy_service_role).is_valid(), false, "backend rejects legacy service role JWT")
	var join_raw: String = RealtimeProtocolScript.join_frame("room:abc", "7", "jwt", "user-1", true)
	var join := RealtimeProtocolScript.decode_frame(join_raw)
	_check_equal(join["join_ref"], "7", "Realtime join ref")
	_check_equal(join["topic"], "realtime:room:abc", "Realtime wire topic")
	_check_equal(join["event"], "phx_join", "Realtime join event")
	_check_equal(join["payload"]["config"]["private"], true, "Realtime channel is private")
	_check_equal(join["payload"]["config"]["presence"]["enabled"], true, "Realtime Presence enabled")
	var heartbeat := RealtimeProtocolScript.decode_frame(RealtimeProtocolScript.heartbeat_frame("8"))
	_check_equal(heartbeat["join_ref"], null, "heartbeat has no join ref")
	_check_equal(heartbeat["topic"], "phoenix", "heartbeat Phoenix topic")
	_check_equal(RealtimeProtocolScript.decode_frame("{}")["error"], "invalid_json_frame", "Realtime rejects object frame")
	_check_equal(RealtimeProtocolScript.decode_frame("[1,2]")["error"], "invalid_frame_shape", "Realtime rejects short frame")
	var binary_topic := "realtime:room:abc".to_utf8_buffer()
	var binary_event := "INSERT".to_utf8_buffer()
	var binary_meta := '{"id":"event-1"}'.to_utf8_buffer()
	var binary_payload := '{"record":{"id":"message-1"}}'.to_utf8_buffer()
	var binary_frame := PackedByteArray([4, binary_topic.size(), binary_event.size(), binary_meta.size(), 1])
	binary_frame.append_array(binary_topic)
	binary_frame.append_array(binary_event)
	binary_frame.append_array(binary_meta)
	binary_frame.append_array(binary_payload)
	var decoded_binary := RealtimeProtocolScript.decode_binary_frame(binary_frame)
	_check_equal(decoded_binary["event"], "broadcast", "Realtime decodes binary broadcast event")
	_check_equal(decoded_binary["payload"]["event"], "INSERT", "Realtime decodes binary user event")
	_check_equal(decoded_binary["payload"]["payload"]["record"]["id"], "message-1", "Realtime decodes binary JSON payload")
	_check_equal(RealtimeClientScript.response_timed_out(10.0, 19.99), false, "Realtime response remains live before timeout")
	_check_equal(RealtimeClientScript.response_timed_out(10.0, 20.0), true, "Realtime response times out at boundary")
	var realtime = RealtimeClientScript.new()
	_check_equal(realtime.configure(config, "jwt", "user-1"), OK, "Realtime client configures")
	for index in 5:
		_check_equal(realtime.subscribe_room("room-%d" % index), OK, "Realtime subscribes room %d" % index)
	_check_equal(realtime.subscribe_room("room-6"), ERR_BUSY, "Realtime rejects sixth room channel")
	realtime.free()
	var backoff = ReconnectBackoffScript.new()
	_check_approx(backoff.next_delay(0.5), 1.0, "reconnect first delay")
	_check_approx(backoff.next_delay(0.5), 2.0, "reconnect second delay")
	backoff.next_delay(0.5)
	backoff.next_delay(0.5)
	_check_approx(backoff.next_delay(0.5), 15.0, "reconnect capped delay")
	_check_approx(backoff.next_delay(0.5), 15.0, "reconnect stays capped")
	backoff.reset()
	_check_equal(backoff.attempt(), 0, "reconnect reset")


func _run_backend_repository_tests() -> void:
	var snapshot := BackendRepositoryScript.map_snapshot(
		"user-1",
		[{"id": "user-1", "nickname": "민트", "character_id": "minty_pup"}],
		[{"id": "room-1", "name": "친구들", "owner_id": "user-1", "invite_version": 1}],
		[
			{"room_id": "room-1", "user_id": "user-1", "joined_at": "2026-01-01T00:00:00Z"},
			{"room_id": "room-1", "user_id": "user-2", "joined_at": "2026-01-02T00:00:00Z"},
		],
		[
			{"id": "user-1", "nickname": "민트", "character_id": "minty_pup"},
			{"id": "user-2", "nickname": "민트", "character_id": "minty_pup"},
		],
	)
	_check_equal(snapshot["ok"], true, "backend snapshot maps")
	_check_equal(snapshot["profile"]["user_id"], "user-1", "backend snapshot maps current profile")
	_check_equal((snapshot["rooms"] as Array).size(), 1, "backend snapshot maps room")
	var members := ((snapshot["rooms"] as Array)[0] as Dictionary)["members"] as Array
	_check_equal(members.size(), 2, "backend snapshot maps members")
	_check_equal((members[0] as Dictionary)["is_self"], true, "backend snapshot marks self")
	_check_equal((members[0] as Dictionary)["nickname"], (members[1] as Dictionary)["nickname"], "backend snapshot preserves duplicate nicknames")


func _run_presence_roster_tests() -> void:
	var roster = PresenceRosterScript.new()
	var changed := roster.apply_state("room-1", {
		"user-1": {"metas": [{"phx_ref": "a", "state": "away"}, {"phx_ref": "b", "state": "online"}]},
	})
	_check_equal(changed, ["user-1"], "Presence state reports changed user")
	_check_equal(roster.presence("room-1", "user-1"), "online", "Presence uses online device priority")
	roster.apply_diff("room-1", {}, {"user-1": {"metas": [{"phx_ref": "b"}]}})
	_check_equal(roster.presence("room-1", "user-1"), "away", "Presence retains remaining away device")
	roster.apply_diff("room-1", {}, {"user-1": {"metas": [{"phx_ref": "a"}]}})
	_check_equal(roster.presence("room-1", "user-1"), "offline", "Presence is offline after final device leaves")


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
	_check_equal(rooms.set_profile(" 하 늘 ", "minty_pup"), OK, "duplicate nickname is allowed in a room")
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
