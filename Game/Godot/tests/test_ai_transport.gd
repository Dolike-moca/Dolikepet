extends SceneTree
## Pure parser/key-boundary tests; no network or real player data is accessed.
const Transport = preload("res://scripts/ai_http.gd")
const KeyStore = preload("res://scripts/ai_key_store.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("AI TRANSPORT: "+label)

func fixture() -> Dictionary:
	var transport := Transport.new()
	root.add_child(transport)
	transport.busy = true
	var state := {"http":transport,"parts":[],"done":[],"errors":[],"cancels":0}
	transport.delta.connect(func(text): state.parts.append(text))
	transport.completed.connect(func(text): state.done.append(text))
	transport.failed.connect(func(text): state.errors.append(text))
	transport.canceled.connect(func(): state.cancels += 1)
	return state

func wire(event: Dictionary, ending := "\n\n") -> PackedByteArray:
	return ("data: "+JSON.stringify(event)+ending).to_utf8_buffer()

func dispose(state: Dictionary) -> void:
	state.http.free()

func run() -> void:
	var state := fixture()
	var body := wire({"type":"response.created","response":{"status":"in_progress"}})
	body.append_array(wire({"type":"response.output_text.delta","delta":"你好喵！🐈"}, "\r\n\r\n"))
	body.append_array(wire({"type":"response.output_text.delta","delta":"陪你一会儿。"}))
	body.append_array(wire({"type":"response.completed","response":{"status":"completed"}}))
	for byte in body: state.http._consume_bytes(PackedByteArray([byte]))
	check(state.done == ["你好喵！🐈陪你一会儿。"], "UTF8 split at every byte preserves Chinese and emoji")
	check(state.parts == ["你好喵！🐈", "陪你一会儿。"], "only output deltas are surfaced")
	check(state.errors.is_empty() and not state.http.busy, "completion ends request once")
	check(state.http._text.is_empty() and state.http._key.is_empty(), "transport clears temporary text and key")
	dispose(state)
	state = fixture()
	state.http._consume_bytes(wire({"type":"response.completed","response":{"status":"completed","output":[
		{"type":"reasoning","summary":[]}, {"type":"message","content":[{"type":"output_text","text":"完整回复"}]}]}}))
	check(state.done == ["完整回复"] and state.parts == ["完整回复"], "terminal text fallback works")
	dispose(state)
	state = fixture()
	state.http._consume_bytes(wire({"type":"response.refusal.delta","delta":"抱歉，这个请求无法处理。"}))
	state.http._consume_bytes(wire({"type":"response.completed","response":{"status":"completed"}}))
	check(state.done == ["抱歉，这个请求无法处理。"], "refusal is visible as assistant text")
	dispose(state)
	for kind in ["response.failed","response.incomplete","error"]:
		state = fixture()
		state.http._consume_bytes(wire({"type":kind,"error":{"message":"do not show raw server secrets"}}))
		check(state.errors.size()==1 and state.done.is_empty() and not state.http.busy, kind+" terminates with error")
		check(not "secrets" in str(state.errors), kind+" does not expose server body")
		dispose(state)
	for content in ["data: {invalid}\n\n","data: [DONE]\n\n", "data: []\n\n"]:
		state = fixture()
		state.http._consume_bytes(content.to_utf8_buffer())
		check(state.errors.size()==1 and state.done.is_empty(), "malformed or unconfirmed terminal is rejected")
		dispose(state)
	state = fixture()
	state.http._consume_bytes(": keepalive\nevent: response.output_text.delta\ndata: {\ndata: \"type\":\"response.output_text.delta\",\"delta\":\"喵\"}\n\n".to_utf8_buffer())
	check(state.parts == ["喵"] and state.errors.is_empty(), "SSE comments and multiline data are supported")
	state.http.cancel()
	state.http.cancel()
	check(state.cancels==1 and not state.http.busy, "cancel is idempotent")
	dispose(state)
	state = fixture()
	state.http._consume_bytes(wire({"type":"response.output_text.delta","delta":"a".repeat(Transport.MAX_TEXT_CHARS+1)}))
	check(state.errors.size()==1 and state.parts.is_empty(), "output text bound rejects oversized reply")
	dispose(state)
	state = fixture()
	state.http._wire_bytes = Transport.MAX_WIRE_BYTES
	state.http._consume_bytes(PackedByteArray([10]))
	check(state.errors.size()==1, "wire response bound")
	dispose(state)
	state = fixture()
	state.http._consume_bytes(("data: "+"x".repeat(Transport.MAX_EVENT_BYTES+1)).to_utf8_buffer())
	check(state.errors.size()==1, "line length bound")
	dispose(state)
	state = fixture()
	state.http._consume_bytes(wire({"type":"response.output_text.delta","delta":42}))
	check(state.errors.size()==1, "nonstring delta is rejected")
	dispose(state)
	state = fixture()
	var replacement := state
	state.http.delta.connect(func(_text):
		replacement.http.cancel()
		# Represents a new request started synchronously by an application callback.
		replacement.http.busy = true
		replacement.http._generation += 1)
	var old_packet := wire({"type":"response.output_text.delta","delta":"first"})
	old_packet.append_array(wire({"type":"response.output_text.delta","delta":"stale"}))
	old_packet.append_array(wire({"type":"response.completed","response":{"status":"completed"}}))
	state.http._consume_bytes(old_packet)
	check(state.parts==["first"] and state.done.is_empty(), "reentrant cancellation/new request discards old packet remainder")
	dispose(state)
	state = fixture()
	var fallback_replacement := state
	state.http.delta.connect(func(_text):
		fallback_replacement.http.cancel()
		fallback_replacement.http.busy = true
		fallback_replacement.http._generation += 1)
	state.http._consume_bytes(wire({"type":"response.completed","response":{"status":"completed","output":[
		{"type":"message","content":[{"type":"output_text","text":"fallback"}]}]}}))
	check(state.parts==["fallback"] and state.done.is_empty() and state.http.busy,
		"terminal fallback callback cannot complete or close a replacement request")
	dispose(state)
	state = fixture()
	check(not state.http.start("fixture-only",{}), "busy request is never replaced or sent twice")
	state.http.cancel()
	for endpoint in ["https://malicious.example/v1/responses","http://127.0.0.1:0/responses","http://127.0.0.1:99999/responses","http://localhost.example:80/"]:
		state.http.endpoint_override = endpoint
		check(state.http._endpoint().is_empty(), "non-loopback or invalid fixture endpoint rejected")
	state.http.endpoint_override = "http://127.0.0.1:8765/v1/responses"
	check(state.http._endpoint().port==8765, "explicit loopback fixture accepted")
	state.http.endpoint_override = ""
	check(state.http._endpoint().host=="https://api.openai.com", "normal endpoint remains official OpenAI")
	for value in ["", "x\r\nInjected: y", "tab\tkey", "中文", "x".repeat(16385)]:
		check(not state.http._valid_key(value), "invalid key header rejected")
	dispose(state)
	var keys := KeyStore.new()
	keys.setup(null, "")
	check(keys.load_key().is_empty() and not keys.has_key(), "unconfigured key store reads nothing")
	check(keys.save_key("fixture-key") == ERR_UNAVAILABLE, "no native vault never falls back to plaintext")
	check(keys.clear_key()==ERR_UNCONFIGURED, "unconfigured clear touches no path")
	print(JSON.stringify({"suite":"ai_transport","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
