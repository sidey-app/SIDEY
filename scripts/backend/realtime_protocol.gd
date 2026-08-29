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
	var parser := JSON.new()
	if parser.parse(raw_frame) != OK:
		return {"error": "invalid_json_frame"}
	var decoded: Variant = parser.data
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


static func decode_binary_frame(packet: PackedByteArray) -> Dictionary:
	if packet.size() < 5:
		return {"error": "invalid_binary_frame"}
	if packet[0] != 4:
		return {"error": "unsupported_binary_frame", "type": packet[0]}
	var topic_size := int(packet[1])
	var event_size := int(packet[2])
	var metadata_size := int(packet[3])
	var payload_encoding := int(packet[4])
	var offset := 5
	var required_size := offset + topic_size + event_size + metadata_size
	if required_size > packet.size():
		return {"error": "invalid_binary_frame"}
	var topic := packet.slice(offset, offset + topic_size).get_string_from_utf8()
	offset += topic_size
	var event_name := packet.slice(offset, offset + event_size).get_string_from_utf8()
	offset += event_size
	var metadata_raw := packet.slice(offset, offset + metadata_size).get_string_from_utf8()
	offset += metadata_size
	var metadata: Dictionary = {}
	if not metadata_raw.is_empty():
		var metadata_parser := JSON.new()
		if metadata_parser.parse(metadata_raw) != OK or not metadata_parser.data is Dictionary:
			return {"error": "invalid_binary_metadata"}
		metadata = metadata_parser.data as Dictionary
	var payload: Variant
	if payload_encoding == 1:
		var payload_parser := JSON.new()
		if payload_parser.parse(packet.slice(offset).get_string_from_utf8()) != OK:
			return {"error": "invalid_binary_json_payload"}
		payload = payload_parser.data
	else:
		payload = packet.slice(offset)
	return {
		"join_ref": null,
		"ref": null,
		"topic": topic,
		"event": "broadcast",
		"payload": {
			"type": "broadcast",
			"event": event_name,
			"meta": metadata,
			"payload": payload,
		},
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


static func leave_frame(topic: String, join_ref: String, message_ref: String) -> String:
	return encode_frame(join_ref, message_ref, wire_topic(topic), "phx_leave", {})
