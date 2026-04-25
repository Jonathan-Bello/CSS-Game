extends Node
class_name EmisClient

@export var base_url: String = "http://127.0.0.1:8080"
@export var chat_endpoint: String = "/chat"
@export var timeout_seconds: float = 20.0

func request_chat(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return _error_result("Mensaje vacío para Emis.", "invalid_response")

	var http := _create_http_request()
	if http == null:
		return _error_result("No se pudo crear el cliente HTTP.", "network")

	var endpoint := _resolve_endpoint()
	var body := JSON.stringify(payload)
	var request_started_msec := Time.get_ticks_msec()
	print("[Emis] request -> %s (payload=%s bytes, timeout=%ss)" % [endpoint, body.length(), timeout_seconds])
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	var request_error := http.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	if request_error != OK:
		http.queue_free()
		push_warning("[Emis] Falló request() con código %s" % request_error)
		return _error_result("No pude conectar con Emis en este momento.", "network")

	var response := await _await_http_response(http, endpoint)
	http.queue_free()
	var elapsed_ms := max(0, Time.get_ticks_msec() - request_started_msec)
	print("[Emis] request <- elapsed=%sms code=%s ok=%s" % [elapsed_ms, String(response.get("code", "")), String(response.get("ok", false))])

	if not bool(response.get("ok", false)):
		return {
			"ok": false,
			"error": String(response.get("error", "Error desconocido")),
			"code": String(response.get("code", "network"))
		}

	var status_code := int(response.get("status_code", 0))
	if status_code < 200 or status_code >= 300:
		push_warning("[Emis] HTTP no exitoso: %s" % status_code)
		return _error_result("Emis respondió con un error del servidor.", "http_error")

	var parsed: Variant = JSON.parse_string(String(response.get("body_text", "")))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Emis] JSON inválido o no es objeto")
		return _error_result("La respuesta de Emis llegó en un formato inválido.", "invalid_response")

	var parsed_dict: Dictionary = parsed
	var reply := _extract_reply(parsed_dict)
	if reply == "":
		push_warning("[Emis] Esquema inesperado: falta campo reply")
		return _error_result("No entendí la respuesta de Emis.", "invalid_response")

	print("[Emis] respuesta OK")
	return {
		"ok": true,
		"reply": reply,
		"raw": parsed_dict
	}

func _create_http_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	add_child(http)
	return http

func _resolve_endpoint() -> String:
	var normalized_base := base_url.strip_edges()
	if normalized_base.ends_with("/"):
		normalized_base = normalized_base.substr(0, normalized_base.length() - 1)

	var normalized_endpoint := chat_endpoint.strip_edges()
	if normalized_endpoint == "":
		normalized_endpoint = "/chat"
	if not normalized_endpoint.begins_with("/"):
		normalized_endpoint = "/" + normalized_endpoint

	return normalized_base + normalized_endpoint

func _await_http_response(http: HTTPRequest, endpoint: String) -> Dictionary:
	var done := false
	var timed_out := false
	var packet := {
		"ok": false,
		"error": "No response",
		"code": "network"
	}

	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		done = true
		packet = _map_http_packet(result, response_code, body)
	, CONNECT_ONE_SHOT)

	var timer := get_tree().create_timer(max(timeout_seconds, 0.1))
	while not done and not timed_out:
		if timer.time_left <= 0.0:
			timed_out = true
			break
		await get_tree().process_frame

	if timed_out:
		http.cancel_request()
		push_warning("[Emis] timeout alcanzado (%ss) endpoint=%s" % [timeout_seconds, endpoint])
		return _error_result("Emis tardó demasiado en responder.", "timeout")

	return packet

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
