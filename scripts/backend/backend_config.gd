class_name BackendConfig
extends RefCounted

const PROJECT_URL_SETTING := "sidey/backend/supabase_url"
const PROJECT_PUBLISHABLE_KEY_SETTING := "sidey/backend/supabase_publishable_key"

var url := ""
var publishable_key := ""


func _init(config_url := "", config_publishable_key := "") -> void:
	url = config_url.strip_edges().trim_suffix("/")
	publishable_key = config_publishable_key.strip_edges()


func is_valid() -> bool:
	return (url.begins_with("http://") or url.begins_with("https://")) \
		and not publishable_key.is_empty() \
		and not _is_secret_key(publishable_key)


func auth_url(path: String) -> String:
	return "%s/auth/v1/%s" % [url, path.trim_prefix("/")]


func rest_url(path: String) -> String:
	return "%s/rest/v1/%s" % [url, path.trim_prefix("/")]


func realtime_url() -> String:
	var websocket_base := url.replace("https://", "wss://").replace("http://", "ws://")
	return "%s/realtime/v1/websocket?apikey=%s&vsn=2.0.0" % [
		websocket_base,
		publishable_key.uri_encode(),
	]


static func from_environment() -> BackendConfig:
	return BackendConfig.new(
		OS.get_environment("SIDEY_SUPABASE_URL"),
		OS.get_environment("SIDEY_SUPABASE_PUBLISHABLE_KEY"),
	)


static func from_project_settings() -> BackendConfig:
	return BackendConfig.new(
		str(ProjectSettings.get_setting(PROJECT_URL_SETTING, "")),
		str(ProjectSettings.get_setting(PROJECT_PUBLISHABLE_KEY_SETTING, "")),
	)


static func from_runtime() -> BackendConfig:
	var environment_config := from_environment()
	if not environment_config.url.is_empty() or not environment_config.publishable_key.is_empty():
		return environment_config
	return from_project_settings()


static func _is_secret_key(key: String) -> bool:
	if key.begins_with("sb_secret_") or key.to_lower().contains("service_role"):
		return true
	var segments := key.split(".")
	if segments.size() != 3:
		return false
	var payload_text := Marshalls.base64_to_utf8(_pad_base64_url(segments[1]))
	var payload: Variant = JSON.parse_string(payload_text)
	return payload is Dictionary and str((payload as Dictionary).get("role", "")) == "service_role"


static func _pad_base64_url(value: String) -> String:
	var normalized := value.replace("-", "+").replace("_", "/")
	while normalized.length() % 4 != 0:
		normalized += "="
	return normalized
