extends Node
## One nonblocking Responses request. No automatic retries or redirected keys.
signal delta(text: String)
signal completed(text: String)
signal failed(message: String)
signal canceled

const HOST := "https://api.openai.com"
const PATH := "/v1/responses"
const DEEPSEEK_HOST := "https://api.deepseek.com"
const DEEPSEEK_PATH := "/responses"
const MAX_WIRE_BYTES := 2097152
const MAX_REQUEST_BYTES := 262144
const MAX_TEXT_CHARS := 24000
const MAX_EVENT_BYTES := 262144
const CONNECT_TIMEOUT := 20.0
const IDLE_TIMEOUT := 45.0
const TOTAL_TIMEOUT := 180.0

var busy := false
var billing_mode := "api_key"
var _request_mode := "api_key"
# Test fixtures may use an explicit loopback URL. Remote overrides are rejected.
var endpoint_override := ""
var _client: HTTPClient
var _key := ""
var _body := ""
var _path := PATH
var _sent := false
var _headers_checked := false
var _started_at := 0
var _last_progress_at := 0
var _wire_bytes := 0
var _line_bytes := PackedByteArray()
var _event_lines: Array[String] = []
var _event_size := 0
var _text := ""
var _status_code := 0
var _generation := 0

func _ready() -> void:
	set_process(false)

func start(api_key: String, payload: Dictionary) -> bool:
	if busy: return false
	_request_mode = billing_mode
	if not _valid_key(api_key):
		failed.emit(_provider_message("请先在 AI 设置中保存有效的 API Key。"))
		return false
	var endpoint := _endpoint()
	if endpoint.is_empty():
		failed.emit("AI 服务地址无效。")
		return false
	_key = api_key.strip_edges()
	var request := payload.duplicate(true)
	request["stream"] = true
	request["store"] = false
	_body = JSON.stringify(request)
	if _body.to_utf8_buffer().size()>MAX_REQUEST_BYTES:
		_key = ""
		_body = ""
		failed.emit("对话内容过长，请清空对话或缩短问题后重试。")
		return false
	_path = str(endpoint.path)
	_sent = false
	_headers_checked = false
	_wire_bytes = 0
	_line_bytes.clear()
	_event_lines.clear()
	_event_size = 0
	_text = ""
	_status_code = 0
	_started_at = Time.get_ticks_msec()
	_last_progress_at = _started_at
	_client = HTTPClient.new()
	_client.read_chunk_size = 16384
	_client.blocking_mode_enabled = false
	busy = true
	_generation += 1
	set_process(true)
	# Explicit verification as well as the HTTPS scheme; never client_unsafe().
	var tls := TLSOptions.client() if endpoint_override.is_empty() else null
	var error := _client.connect_to_host(str(endpoint.host), int(endpoint.port), tls)
	if error != OK:
		_fail("暂时无法连接 GPT，请检查网络后重试。")
		return false
	return true

func _valid_key(value: String) -> bool:
	if value.strip_edges().is_empty() or value.length()>16384: return false
	for index in value.length():
		var code := value.unicode_at(index)
		if code<32 or code>126: return false
	return true

func cancel() -> void:
	if not busy: return
	_close()
	canceled.emit()

func _exit_tree() -> void:
	_close()

func _endpoint() -> Dictionary:
	if billing_mode not in ["api_key", "chatgpt", "deepseek"]: return {}
	if endpoint_override.is_empty():
		return {"host": DEEPSEEK_HOST, "port": 443, "path": DEEPSEEK_PATH} if billing_mode == "deepseek" else {"host": HOST, "port": 443, "path": PATH}
	var matcher := RegEx.new()
	matcher.compile("^http://(127\\.0\\.0\\.1|localhost):([0-9]{1,5})(/[^\\s#]*)?$")
	var found := matcher.search(endpoint_override)
	if found == null: return {}
	var port := int(found.get_string(2))
	if port < 1 or port > 65535: return {}
	return {"host": "http://"+found.get_string(1), "port": port,
		"path": found.get_string(3) if not found.get_string(3).is_empty() else PATH}

func _process(_dt: float) -> void:
	if not busy or _client == null: return
	var generation := _generation
	var now := Time.get_ticks_msec()
	if now-_started_at > int(TOTAL_TIMEOUT*1000.0):
		_fail("回复等待时间过长，已停止本次请求；可以稍后重试。")
		return
	if now-_last_progress_at > int((IDLE_TIMEOUT if _sent else CONNECT_TIMEOUT)*1000.0):
		_fail("网络连接超时，已停止本次请求；可以稍后重试。")
		return
	var error := _client.poll()
	if error != OK:
		_fail("连接中断，回复可能未完成；请检查网络后重试。")
		return
	match _client.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				var headers := PackedStringArray(["Authorization: Bearer "+_key,
					"Content-Type: application/json", "Accept: text/event-stream"])
				error = _client.request(HTTPClient.METHOD_POST, _path, headers, _body)
				_key = ""
				_body = ""
				if error != OK:
					_fail("GPT 请求未能发出，请稍后重试。")
					return
				_sent = true
				_last_progress_at = now
			elif _headers_checked:
				_fail("回复连接已结束，但没有收到完成确认；请重试。")
			elif _client.has_response():
				if not _check_headers(): return
				if busy and generation == _generation: _fail("GPT 返回了空响应，请重试。")
		HTTPClient.STATUS_BODY:
			if not _headers_checked and not _check_headers(): return
			# Limit each frame's work even if a proxy flushes a large response.
			for _chunk in range(8):
				if _client.get_status() != HTTPClient.STATUS_BODY: break
				var bytes := _client.read_response_body_chunk()
				if bytes.is_empty(): break
				_last_progress_at = now
				_consume_bytes(bytes)
				if not busy or generation != _generation: return
		HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_fail("无法连接 GPT 或连接已中断，请检查网络后重试。")

func _check_headers() -> bool:
	_status_code = _client.get_response_code()
	_headers_checked = true
	if _status_code != 200:
		var message := "GPT 服务暂时不可用，请稍后重试。"
		if _status_code == 401:
			message = "ChatGPT 登录或授权已失效，请在 AI 设置中重新登录。" if _request_mode == "chatgpt" else "API Key 无效或已失效，请在 AI 设置中重新填写。"
		elif _status_code == 403: message = "此 API 账户暂时无法访问该服务，请检查账户权限。"
		elif _status_code == 404: message = "模型不存在或当前账户无权使用，请在 AI 设置中更换模型。"
		elif _status_code == 429:
			message = "ChatGPT 方案用量或请求频率已达限制，请查看用量后稍后重试。" if _request_mode == "chatgpt" else "请求过于频繁或 API 额度不足，请检查账户后稍后重试。"
		elif _status_code >= 300 and _status_code < 400: message = "服务返回了重定向；为保护 API Key，本次请求已停止。"
		elif _status_code == 400: message = "模型或请求设置不受支持，请检查 AI 设置。"
		_fail(message)
		return false
	var content_type := ""
	for header in _client.get_response_headers():
		if header.to_lower().begins_with("content-type:"):
			content_type = header.to_lower()
	if not "text/event-stream" in content_type:
		_fail("GPT 响应格式不正确，请稍后重试。")
		return false
	return true

func _consume_bytes(bytes: PackedByteArray) -> void:
	var generation := _generation
	_wire_bytes += bytes.size()
	if _wire_bytes > MAX_WIRE_BYTES:
		_fail("回复数据过长，本次请求已停止。")
		return
	# Decode only complete lines: a multibyte Chinese character can span packets.
	for byte in bytes:
		if byte == 10:
			var line := _line_bytes.get_string_from_utf8().trim_suffix("\r")
			_line_bytes.clear()
			_consume_line(line)
			if not busy or generation != _generation: return
		else:
			_line_bytes.append(byte)
			if _line_bytes.size() > MAX_EVENT_BYTES:
				_fail("回复事件过长，本次请求已停止。")
				return

func _consume_line(line: String) -> void:
	if line.is_empty():
		if not _event_lines.is_empty():
			var value := "\n".join(_event_lines)
			_event_lines.clear()
			_event_size = 0
			_consume_event(value)
		return
	if not line.begins_with("data:"): return
	var value := line.substr(5)
	if value.begins_with(" "): value = value.substr(1)
	_event_lines.append(value)
	_event_size += value.to_utf8_buffer().size()
	if _event_size > MAX_EVENT_BYTES: _fail("回复事件过长，本次请求已停止。")

func _consume_event(value: String) -> void:
	var generation := _generation
	if value == "[DONE]":
		# Responses uses response.completed as its authoritative terminal event.
		_fail("未收到回复完成确认，请稍后重试。")
		return
	var parser := JSON.new()
	if parser.parse(value) != OK or not parser.data is Dictionary:
		_fail("GPT 回复格式异常，本次请求已停止。")
		return
	var event: Dictionary = parser.data
	var kind := str(event.get("type", ""))
	if kind == "response.output_text.delta" or kind == "response.refusal.delta":
		var part = event.get("delta", "")
		if not part is String:
			_fail("GPT 回复格式异常，本次请求已停止。")
			return
		if _text.length()+part.length()>MAX_TEXT_CHARS:
			_fail("回复过长，本次请求已停止；请缩短问题后重试。")
			return
		_text += part
		delta.emit(part)
	elif kind == "response.completed":
		var response = event.get("response", {})
		if not response is Dictionary or str(response.get("status", "completed")) != "completed":
			_fail("GPT 未完成本次回复，请重试。")
			return
		if _text.is_empty():
			var final_text := _response_text(response)
			if final_text.length()>MAX_TEXT_CHARS:
				_fail("回复过长，本次请求已停止；请缩短问题后重试。")
				return
			if not final_text.is_empty():
				_text = final_text
				delta.emit(_text)
				if not busy or generation != _generation: return
		if _text.is_empty():
			_fail("GPT 没有返回文字，请换一种说法再试。")
			return
		var answer := _text
		_close()
		completed.emit(answer)
	elif kind == "response.failed" or kind == "error":
		_fail("GPT 未能完成回复，请检查模型权限或稍后重试。")
	elif kind == "response.incomplete":
		_fail("回复达到长度或服务限制，尚未完成；可以缩短问题后重试。")

func _response_text(response: Dictionary) -> String:
	var text := ""
	var output = response.get("output", [])
	if not output is Array: return text
	for item in output:
		if not item is Dictionary or item.get("type", "") != "message": continue
		var content = item.get("content", [])
		if not content is Array: continue
		for part in content:
			if not part is Dictionary: continue
			if part.get("type", "") == "output_text": text += str(part.get("text", ""))
			elif part.get("type", "") == "refusal": text += str(part.get("refusal", ""))
	return text

func _fail(message: String) -> void:
	if not busy: return
	_close()
	failed.emit(_provider_message(message))

func _provider_message(message: String) -> String:
	# Keep provider errors tied to the request snapshot, even during UI changes.
	if _request_mode != "deepseek": return message
	var text := message.replace("GPT", "DeepSeek")
	return text if text.contains("DeepSeek") else "DeepSeek：" + text

func _close() -> void:
	_generation += 1
	busy = false
	set_process(false)
	if _client != null: _client.close()
	_client = null
	_key = ""
	_body = ""
	_text = ""
	_line_bytes.clear()
	_event_lines.clear()
