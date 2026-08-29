class_name BackendHttp
extends Node

const DEFAULT_TIMEOUT_SECONDS := 15.0


func request_json(
	method: HTTPClient.Method,
	url: String,
	headers: PackedStringArray,
	body: Variant = null,
	timeout_seconds := DEFAULT_TIMEOUT_SECONDS,
) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = timeout_seconds
	add_child(request)
	var encoded_body := "" if body == null else JSON.stringify(body)
	var request_error := request.request(url, headers, method, encoded_body)
	if request_error != OK:
		request.queue_free()
		return _failure(0, "request_start_failed", error_string(request_error))
	var completed: Array = await request.request_completed
	request.queue_free()
	var transport_result := int(completed[0])
	var status := int(completed[1])
	var response_headers := completed[2] as PackedStringArray
	var raw_body := (completed[3] as PackedByteArray).get_string_from_utf8()
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return _failure(status, "transport_error", "HTTPRequest result %d" % transport_result)
	var parsed: Variant = null
	if not raw_body.is_empty():
		parsed = JSON.parse_string(raw_body)
		if parsed == null and raw_body != "null":
			return _failure(status, "invalid_json_response", raw_body.left(240))
	if status < 200 or status >= 300:
		return {
			"ok": false,
			"status": status,
			"data": parsed,
			"headers": response_headers,
			"error_code": _response_error_code(parsed, status),
			"error_message": _response_error_message(parsed),
		}
	return {
		"ok": true,
		"status": status,
		"data": parsed,
		"headers": response_headers,
		"error_code": "",
		"error_message": "",
	}


static func _failure(status: int, code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"status": status,
		"data": null,
		"headers": PackedStringArray(),
		"error_code": code,
		"error_message": message,
	}


static func _response_error_code(data: Variant, status: int) -> String:
	if data is Dictionary:
		for key in ["code", "error_code", "error"]:
			var value := str((data as Dictionary).get(key, ""))
			if not value.is_empty():
				return value
	return "http_%d" % status


static func _response_error_message(data: Variant) -> String:
	if data is Dictionary:
		for key in ["message", "msg", "error_description", "error"]:
			var value := str((data as Dictionary).get(key, ""))
			if not value.is_empty():
				return value
	return "Backend request failed"
