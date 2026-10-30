extends SceneTree
## Provider isolation with synthetic keys, an in-memory responder and local storage.
const Companion = preload("res://scripts/ai_companion.gd")
const HTTP = preload("res://scripts/ai_http.gd")
class Transport extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var starts: Array = []
	var busy := false
	func start(token: String, payload: Dictionary) -> bool:
		busy = true; starts.append({"token":token,"payload":payload.duplicate(true)}); return true
	func cancel() -> void:
		if not busy: return
		busy = false; canceled.emit()
	func finish(text: String = "收到喵。") -> void:
		busy = false; completed.emit(text)
class Keys extends RefCounted:
	var value := ""
	var path := ""
	var deny_save := false
	var reads := 0
	func setup(_native: Object, directory: String) -> void: path = directory
	func has_key() -> bool: return not value.is_empty()
	func load_key() -> String: reads += 1; return value
	func save_key(text: String) -> Error:
		if deny_save: return ERR_CANT_CREATE
		value = text; return OK
	func clear_key() -> Error: value = ""; return OK
class FaultStore extends "res://scripts/ai_store.gd":
	var deny_save := false
	func save_data(value: Dictionary) -> Error:
		return ERR_CANT_CREATE if deny_save else super.save_data(value)
class Auth extends Node:
	signal token_ready(token: String, request_id: int)
	signal failed(message: String)
	signal changed
	var active_id := "fixture-account"
	var selected_model := "fixture-account-model"
	var session_revision := 0
	var requests := 0
	func can_infer() -> bool: return true
	func active_label() -> String: return "fixture account"
	func request_access_token(id: int) -> void:
		requests += 1; token_ready.emit("fixture-account-token", id)
var failures: Array[String] = []
var checks := 0
var now := 1800000000
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("DEEPSEEK: " + label)
func run() -> void:
	var service := Companion.new()
	var transport := Transport.new()
	var openai := Keys.new(); openai.value = "fixture-openai-key"
	var deepseek := Keys.new()
	var auth := Auth.new(); root.add_child(auth)
	service.configure_dependencies(transport, openai, deepseek)
	service.bind_auth(auth)
	service._store = FaultStore.new()
	service.clock_override = func(): return now
	service.day_override = "2026-11-01"
	root.add_child(service)
	var directory := ProjectSettings.globalize_path("res://../../_work/tests/ai-deepseek/%d" % OS.get_process_id())
	service.setup(null, directory, true)
	check(openai.path == directory and deepseek.path == directory.path_join("deepseek"), "independent credential directories")
	check(service.settings.auth_method == "api_key" and service.settings.deepseek_model == "deepseek-flash", "existing route remains default; DeepSeek model default is independent")
	check(service.apply_settings({"auth_method":"deepseek","enabled":true}) == ERR_UNCONFIGURED, "DeepSeek cannot borrow saved OpenAI key")
	check(service.apply_settings({"auth_method":"deepseek","enabled":true}, "", false, "fixture-deepseek-key") == OK, "save independent DeepSeek credential and route")
	check(service.ready_to_chat() and service.has_deepseek_key() and service.has_key(), "both provider credentials retained")
	check(service.billing_label().contains("DeepSeek"), "billing label names selected provider")
	check(service.send_message("我喜欢薯条。"), "DeepSeek chat starts")
	var call: Dictionary = transport.starts.back()
	check(call.token == "fixture-deepseek-key" and service._request_route == "deepseek", "DeepSeek receives only its own credential")
	check(call.payload.model == "deepseek-flash" and call.payload.reasoning.effort == "none", "DeepSeek nonthinking payload")
	check(call.payload.max_output_tokens == 512 and call.payload.stream and not call.payload.store and not call.payload.has("tools"), "bounded text-only stateless request")
	check(not JSON.stringify(call.payload).contains("fixture-deepseek-key"), "credential not put into request JSON")
	check(service.apply_settings(service.settings.duplicate(true)) == OK and service.busy, "unchanged settings do not cancel DeepSeek")
	transport.finish()
	check(service.test_connection(), "DeepSeek connection test uses same route")
	check(transport.starts.back().payload.max_output_tokens == 32 and transport.starts.back().token == "fixture-deepseek-key", "connection test has small provider-specific budget")
	transport.finish("连接成功")
	check(service.apply_settings({"auth_method":"api_key","memory_auth_method":"deepseek"}) == OK, "OpenAI chat with independent DeepSeek memory")
	now += 121
	service._memory_tick(true)
	check(service.request_kind == "memory" and service._request_route == "deepseek", "daily memory really selects DeepSeek")
	check(transport.starts.back().token == "fixture-deepseek-key" and transport.starts.back().payload.max_output_tokens == 2048, "memory uses DeepSeek key and bounded extraction budget")
	check(service.send_message("再聊一句"), "foreground chat interrupts background memory")
	check(transport.starts.back().token == "fixture-openai-key" and transport.starts.back().payload.model == "gpt-6-luna", "foreground returns to configured OpenAI route")
	transport.finish()
	check(service.apply_settings({"auth_method":"deepseek","memory_auth_method":"api_key","deepseek_model":"deepseek-v4-pro"}) == OK, "DeepSeek chat with independent OpenAI memory")
	service.day_override = "2026-11-02"; now += 86400
	service._memory_tick(true)
	check(service.request_kind == "memory" and service._request_route == "api_key" and transport.starts.back().token == "fixture-openai-key", "memory routing works in reverse without leaking DeepSeek key")
	transport.finish('{"items":[]}')
	check(service.apply_settings({"auth_method":"chatgpt","memory_auth_method":"deepseek"}) == OK and service.send_message("账户聊天"), "ChatGPT sign-in coexists with DeepSeek memory")
	check(transport.starts.back().token == "fixture-account-token" and not transport.starts.back().payload.has("max_output_tokens"), "OAuth keeps own payload and token")
	transport.finish()
	check(service.apply_settings({"auth_method":"deepseek","memory_auth_method":"follow"}) == OK and service.send_message("DeepSeek 继续"), "switch back preserves DeepSeek configuration")
	check(transport.starts.back().payload.model == "deepseek-v4-pro" and auth.requests == 1, "DeepSeek never invokes ChatGPT token authority")
	var previous_starts := transport.starts.size()
	check(service.apply_settings({"auth_method":"api_key"}) == OK and not service.busy, "changing provider cancels in-flight old request")
	check(transport.starts.size() == previous_starts, "switching provider never automatically retransmits")
	deepseek.value = ""
	check(service.apply_settings({"memory_auth_method":"deepseek"}) == ERR_UNCONFIGURED, "missing memory key fails without fallback")
	check(service.apply_settings({"auth_method":"deepseek"}) == ERR_UNCONFIGURED, "missing chat key fails despite OpenAI and OAuth available")
	check(service.apply_settings({}, "", false, "fixture-deepseek-key") == OK, "DeepSeek key can be saved while OpenAI is selected")
	check(service.apply_settings({"auth_method":"deepseek","deepseek_model":"bad model"}) == ERR_INVALID_PARAMETER, "invalid DeepSeek model rejected")
	check(service.apply_settings({}, "", false, "bad key") == ERR_INVALID_PARAMETER, "invalid DeepSeek key rejected")
	deepseek.deny_save = true
	check(service.apply_settings({}, "replacement-openai", false, "replacement-deepseek") != OK, "second key save failure reported")
	check(openai.value == "fixture-openai-key" and deepseek.value == "fixture-deepseek-key", "second key failure rolls back first provider credential")
	deepseek.deny_save = false
	service._store.deny_save = true
	check(service.apply_settings({"deepseek_model":"deepseek-flash"}, "replacement-openai", false, "replacement-deepseek") != OK, "settings persistence failure reported")
	check(openai.value == "fixture-openai-key" and deepseek.value == "fixture-deepseek-key" and service.settings.deepseek_model == "deepseek-v4-pro", "failed settings commit rolls back both credentials and model")
	service._store.deny_save = false
	check(service.apply_settings({}, "", false, "", true) == OK and not service.has_deepseek_key() and service.has_key(), "remove DeepSeek credential preserves OpenAI key")
	var stored := FileAccess.get_file_as_string(directory.path_join("companion.json")) if FileAccess.file_exists(directory.path_join("companion.json")) else ""
	check(not stored.contains("fixture-openai-key") and not stored.contains("fixture-deepseek-key"), "plain settings do not contain provider credentials")
	var http := HTTP.new(); root.add_child(http)
	check(http._endpoint().host == "https://api.openai.com" and http._endpoint().path == "/v1/responses", "OpenAI endpoint unchanged")
	http.billing_mode = "deepseek"
	check(http._endpoint() == {"host":"https://api.deepseek.com","port":443,"path":"/responses"}, "DeepSeek uses fixed official HTTPS endpoint")
	http.endpoint_override = "https://foreign.example/responses"
	check(http._endpoint().is_empty(), "remote endpoint override rejected")
	http.endpoint_override = ""; http.billing_mode = "unknown"
	check(http._endpoint().is_empty(), "unknown provider fails closed instead of selecting OpenAI")
	http.billing_mode = "deepseek"; http._request_mode = "deepseek"; http.busy = true
	var received := {"text":"", "done":"", "errors":[]}
	http.delta.connect(func(text): received.text += text)
	http.completed.connect(func(text): received.done = text)
	http.failed.connect(func(text): received.errors.append(text))
	http._consume_event('{"type":"response.reasoning_text.delta","delta":"hidden reasoning"}')
	http._consume_event('{"type":"response.output_text.delta","delta":"你好喵"}')
	http._consume_event('{"type":"response.completed","response":{"status":"completed"}}')
	check(received.text == "你好喵" and received.done == "你好喵" and received.errors.is_empty(), "official Responses SSE reuses parser without displaying reasoning")
	http.busy = true; http.billing_mode = "api_key"
	http._fail("无法连接 GPT 或连接已中断，请检查网络后重试。")
	check(str(received.errors.back()).contains("DeepSeek") and not str(received.errors.back()).contains("GPT"), "errors preserve request provider despite subsequent UI route change")
	http.free(); service.shutdown(); service.free(); auth.free()
	print("DeepSeek backend: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
