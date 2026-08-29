class_name RealtimeProtocol
extends RefCounted

const WIRE_TOPIC_PREFIX := "realtime:"


static func encode_frame(
	join_ref: Variant,
	message_ref: Variant,
	topic: String,
	event: String,
	payload: Dictionary,
) -> String:
	return JSON.stringify([join_ref, message_ref, topic, event, payload])


static func decode_frame(raw_frame: String) -> Dictionary:
	var decoded: Variant = JSON.parse_string(raw_frame)
	if not decoded is Array:
		return {"error": "invalid_json_frame"}
	var parts := decoded as Array
	if parts.size() != 5 or not parts[2] is String or not parts[3] is String or not parts[4] is Dictionary:
		return {"error": "invalid_frame_shape"}
	return {
		"join_ref": parts[0],
		"ref": parts[1],
		"topic": parts[2],
		"event": parts[3],
		"payload": parts[4],
	}


static func room_topic(room_id: String) -> String:
	return "room:%s" % room_id


static func wire_topic(topic: String) -> String:
	return "%s%s" % [WIRE_TOPIC_PREFIX, topic]


static func client_topic(wire_topic_value: String) -> String:
	return wire_topic_value.trim_prefix(WIRE_TOPIC_PREFIX)


static func join_frame(
	topic: String,
	message_ref: String,
	access_token: String,
	presence_key: String,
	self_broadcast := false,
) -> String:
	return encode_frame(
		message_ref,
		message_ref,
		wire_topic(topic),
		"phx_join",
		{
			"config": {
				"broadcast": {"ack": true, "self": self_broadcast},
				"presence": {"enabled": true, "key": presence_key},
				"postgres_changes": [],
				"private": true,
			},
			"access_token": access_token,
		},
	)


static func heartbeat_frame(message_ref: String) -> String:
	return encode_frame(null, message_ref, "phoenix", "heartbeat", {})


static func broadcast_frame(
	topic: String,
	join_ref: String,
	message_ref: String,
	event_name: String,
	payload: Dictionary,
) -> String:
	return encode_frame(
		join_ref,
		message_ref,
		wire_topic(topic),
		"broadcast",
		{"type": "broadcast", "event": event_name, "payload": payload},
	)


static func presence_frame(
	topic: String,
	join_ref: String,
	message_ref: String,
	payload: Dictionary,
) -> String:
	return encode_frame(
		join_ref,
		message_ref,
		wire_topic(topic),
		"presence",
		{"type": "presence", "event": "track", "payload": payload},
	)


static func access_token_frame(
	topic: String,
	join_ref: String,
	message_ref: String,
	access_token: String,
) -> String:
	return encode_frame(
		join_ref,
		message_ref,
		wire_topic(topic),
		"access_token",
		{"access_token": access_token},
	)
