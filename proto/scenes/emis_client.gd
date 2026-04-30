extends Node
class_name EmisClient

@export var base_url: String = "http://127.0.0.1:8080"
@export var chat_endpoint: String = "/api/emis/chat"
@export var timeout_seconds: float = 20.0
@export var auto_discover_endpoint: bool = true
@export var candidate_endpoints: PackedStringArray = PackedStringArray([
	"/api/emis/chat",
	"/chat",
	"/api/chat",
	"/v1/chat",
	"/emis/chat",
	"/api/v1/emis/chat"
])

var _resolved_endpoint: String = ""

func request_chat(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return _error_result("Mensaje vacío para Emis.", "invalid_response")

	var endpoint_result := await _resolve_chat_endpoint(payload)
	if not bool(endpoint_result.get("ok", false)):
		return endpoint_result

	var endpoint := String(endpoint_result.get("endpoint", ""))
	if endpoint == "":
		return _error_result("No pude determinar el endpoint de chat de Emis.", "invalid_response")

	var response := await _post_json(endpoint, payload)
	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"error": String(response.get("error", "Error desconocido")),
			"code": String(response.get("code", "network"))
		}

	var status_code := int(response.get("status_code", 0))
	if status_code < 200 or status_code >= 300:
		push_warning("[Emis] HTTP no exitoso: %s (endpoint=%s)" % [status_code, endpoint])
		return _error_result("Emis respondió con un error del servidor.", "http_error")

	var parsed: Variant = JSON.parse_string(String(response.get("body_text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Emis] JSON inválido o no es objeto")
		return _error_result("La respuesta de Emis llegó en un formato inválido.", "invalid_response")

	var parsed_dict: Dictionary = parsed
	var reply := _extract_reply(parsed_dict)
	if reply == "":
		push_warning("[Emis] Esquema inesperado: falta campo reply/message")
		return _error_result("No entendí la respuesta de Emis.", "invalid_response")

	print("[Emis] respuesta OK endpoint=%s" % endpoint)
	return {
		"ok": true,
		"reply": reply,
		"raw": parsed_dict,
		"endpoint": endpoint
	}

func _resolve_chat_endpoint(payload: Dictionary) -> Dictionary:
	if _resolved_endpoint != "":
		return {"ok": true, "endpoint": _resolved_endpoint}

	var explicit := _read_explicit_endpoint()
	if explicit != "":
		_resolved_endpoint = explicit
		return {"ok": true, "endpoint": _resolved_endpoint}

	var discovered := await _discover_from_openapi()
	if discovered != "":
		_resolved_endpoint = discovered
		return {"ok": true, "endpoint": _resolved_endpoint}

	var candidates := _build_candidate_list()
	for candidate in candidates:
		var endpoint := _resolve_full_endpoint(candidate)
		var probe := await _post_json(endpoint, payload)
		if not bool(probe.get("ok", false)):
			continue
		var status_code := int(probe.get("status_code", 0))
		if status_code >= 200 and status_code < 300:
			_resolved_endpoint = endpoint
			print("[Emis] endpoint detectado automáticamente: %s" % endpoint)
			return {"ok": true, "endpoint": _resolved_endpoint}

	return _error_result("No se encontró endpoint de chat válido en Emis.", "invalid_response")

func _read_explicit_endpoint() -> String:
	var env_endpoint := OS.get_environment("EMIS_CHAT_ENDPOINT").strip_edges()
	if env_endpoint != "":
		return _resolve_full_endpoint(env_endpoint)

	var configured_endpoint := chat_endpoint.strip_edges()
	if configured_endpoint != "":
		return _resolve_full_endpoint(configured_endpoint)

	return ""

func _discover_from_openapi() -> String:
	if not auto_discover_endpoint:
		return ""

	var specs := PackedStringArray(["/openapi.json", "/docs/openapi.json"])
	for spec_path in specs:
		var spec_url := _resolve_full_endpoint(spec_path)
		var spec_response := await _get_json(spec_url)
		if not bool(spec_response.get("ok", false)):
			continue
		if int(spec_response.get("status_code", 0)) != 200:
			continue

		var body_text := String(spec_response.get("body_text", ""))
		var parsed: Variant = JSON.parse_string(body_text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		var path := _extract_chat_path_from_openapi(parsed)
		if path != "":
			var resolved := _resolve_full_endpoint(path)
			print("[Emis] endpoint encontrado en OpenAPI: %s" % resolved)
			return resolved

	return ""

func _extract_chat_path_from_openapi(spec: Dictionary) -> String:
	var raw_paths: Variant = spec.get("paths", {})
	if typeof(raw_paths) != TYPE_DICTIONARY:
		return ""

	var paths: Dictionary = raw_paths
	for key in paths.keys():
		var path := String(key)
		var operations_variant: Variant = paths.get(key, {})
		if typeof(operations_variant) != TYPE_DICTIONARY:
			continue
		var operations: Dictionary = operations_variant
		if not operations.has("post"):
			continue

		var normalized := path.to_lower()
		if normalized.contains("chat") or normalized.contains("emis"):
			return path

	return ""

func _build_candidate_list() -> PackedStringArray:
	var candidates := PackedStringArray()
	var env_candidates := OS.get_environment("EMIS_CHAT_ENDPOINTS").strip_edges()
	if env_candidates != "":
		for part in env_candidates.split(","):
			var candidate := String(part).strip_edges()
			if candidate != "" and not candidates.has(candidate):
				candidates.append(candidate)

	for candidate in candidate_endpoints:
		var normalized := String(candidate).strip_edges()
		if normalized != "" and not candidates.has(normalized):
			candidates.append(normalized)

	return candidates

func _resolve_full_endpoint(endpoint: String) -> String:
	var normalized_endpoint := endpoint.strip_edges()
	if normalized_endpoint.begins_with("http://") or normalized_endpoint.begins_with("https://"):
		return normalized_endpoint

	var normalized_base := _resolve_base_url()
	if normalized_base.ends_with("/"):
		normalized_base = normalized_base.substr(0, normalized_base.length() - 1)
	if not normalized_endpoint.begins_with("/"):
		normalized_endpoint = "/" + normalized_endpoint
	return normalized_base + normalized_endpoint

func _resolve_base_url() -> String:
	var env_base := OS.get_environment("EMIS_BASE_URL").strip_edges()
	if env_base != "":
		return env_base
	return base_url.strip_edges()

func _create_http_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	add_child(http)
	return http

func _post_json(endpoint: String, payload: Dictionary) -> Dictionary:
	return await _request_json(endpoint, HTTPClient.METHOD_POST, JSON.stringify(payload), PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	]))

func _get_json(endpoint: String) -> Dictionary:
	return await _request_json(endpoint, HTTPClient.METHOD_GET, "", PackedStringArray([
		"Accept: application/json"
	]))

func _request_json(endpoint: String, method: int, body: String, headers: PackedStringArray) -> Dictionary:
	var http := _create_http_request()
	if http == null:
		return _error_result("No se pudo crear el cliente HTTP.", "network")
	http.timeout = max(timeout_seconds, 0.1)

	var request_started_msec := Time.get_ticks_msec()
	print("[Emis] request -> %s (method=%s, payload=%s bytes, timeout=%ss)" % [endpoint, method, body.length(), timeout_seconds])
	var request_error := http.request(endpoint, headers, method, body)
	if request_error != OK:
		http.queue_free()
		push_warning("[Emis] Falló request() con código %s" % request_error)
		return _error_result("No pude conectar con Emis en este momento.", "network")

	var response := await _await_http_response(http, endpoint)
	http.queue_free()
	var elapsed_ms :Variant= max(0, Time.get_ticks_msec() - request_started_msec)
	print("[Emis] request <- elapsed=%sms code=%s ok=%s" % [elapsed_ms, str(response.get("code", "")), str(response.get("ok", false))])
	return response

func _await_http_response(http: HTTPRequest, endpoint: String) -> Dictionary:
	var completed: Array = await http.request_completed
	if completed.size() < 4:
		push_warning("[Emis] respuesta incompleta del request endpoint=%s" % endpoint)
		return _error_result("La respuesta de Emis llegó incompleta.", "invalid_response")

	var result := int(completed[0])
	var response_code := int(completed[1])
	var body := completed[3] as PackedByteArray
	if result == HTTPRequest.RESULT_TIMEOUT:
		push_warning("[Emis] timeout alcanzado (%ss) endpoint=%s" % [timeout_seconds, endpoint])
	return _map_http_packet(result, response_code, body)

func _map_http_packet(result: int, response_code: int, body: PackedByteArray) -> Dictionary:
	var body_text := body.get_string_from_utf8()
	if result == HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": true,
			"status_code": response_code,
			"body_text": body_text
		}

	var network_codes := [
		HTTPRequest.RESULT_CANT_CONNECT,
		HTTPRequest.RESULT_CANT_RESOLVE,
		HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR
	]
	if network_codes.has(result):
		push_warning("[Emis] backend caído o inaccesible. result=%s" % result)
		return _error_result("No se pudo conectar al backend de Emis.", "network")

	if result == HTTPRequest.RESULT_TIMEOUT:
		return _error_result("La conexión con Emis expiró.", "timeout")

	push_warning("[Emis] error HTTPRequest result=%s response=%s" % [result, response_code])
	return _error_result("No se pudo completar la solicitud a Emis.", "network")

func _extract_reply(raw: Dictionary) -> String:
	var direct := String(raw.get("reply", "")).strip_edges()
	if direct != "":
		return direct

	var message := String(raw.get("message", "")).strip_edges()
	if message != "":
		return message

	return ""

func _error_result(message: String, code: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"code": code
	}
