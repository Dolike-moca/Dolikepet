extends SceneTree
## Route isolation with an explicit fake credential authority; no external requests.
const Companion = preload("res://scripts/ai_companion.gd")
var failures: Array[String] = []
var checks := 0
var fixture_number := 0
class Transport extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var busy := false
	var starts: Array = []
	var cancels := 0
	func start(token: String, payload: Dictionary) -> bool:
		busy = true; starts.append({"token":token,"payload":payload.duplicate(true)}); return true
	func cancel() -> void:
		if not busy: return
		busy = false; cancels += 1; canceled.emit()
	func finish(text: String = "收到喵") -> void:
		busy = false; completed.emit(text)
class Keys extends RefCounted:
	var value := "fixture-api-key"
	var reads := 0
	func setup(_native: Object, _path: String) -> void: pass
	func has_key() -> bool: return not value.is_empty()
	func load_key() -> String: reads += 1; return value
	func save_key(key: String) -> Error: value = key; return OK
	func clear_key() -> Error: value = ""; return OK
class Auth extends Node:
	signal token_ready(token: String, request_id: int)
	signal failed(message: String)
	signal changed
	var active_id := "account-a"
	var selected_model := "catalog-model-a"
	var session_revision := 0
	var authorized := true
	var synchronous := false
	var requests: Array[Dictionary] = []
	func can_infer() -> bool: return authorized and not active_id.is_empty()
	func active_label() -> String: return "Fixture " + active_id
	func request_access_token(request_id: int = 0) -> void:
		requests.append({"account":active_id,"id":request_id})
		if synchronous: token_ready.emit("fixture-oauth-" + active_id, request_id)
	func deliver(index: int) -> void:
		# Matches the real authority's serial/account guard: a rotated identity
		# cannot release its prior account's credential into the new session.
		if index < requests.size() and requests[index].account == active_id and authorized:
			token_ready.emit("fixture-oauth-" + active_id, int(requests[index].id))
	func switch_account(value: String) -> void:
		active_id = value; changed.emit()
	func switch_model(value: String) -> void:
		selected_model = value; changed.emit()
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("AI AUTH ROUTE: " + message)
func fixture() -> Dictionary:
	fixture_number += 1
	var service := Companion.new()
	var transport := Transport.new()
	var keys := Keys.new()
	var auth := Auth.new()
	root.add_child(auth)
	service.configure_dependencies(transport, keys)
	root.add_child(service)
	var path := ProjectSettings.globalize_path("res://../../_work/tests/ai-auth-route/%d-%d" % [OS.get_process_id(),fixture_number])
	service.bind_auth(auth)
	service.setup(null, path, true)
	return {"service":service,"transport":transport,"keys":keys,"auth":auth}
func finish_fixture(value: Dictionary) -> void:
	value.service.shutdown(); value.service.queue_free(); value.auth.queue_free()
func oauth(value: Dictionary) -> void:
	check(value.service.apply_settings({"enabled":true,"auth_method":"chatgpt"}) == OK, "authorized account route can be selected")
func run() -> void:
	var f := fixture()
	check(f.service.apply_settings({"enabled":true,"auth_method":"api_key"}) == OK, "API key route can be selected")
	check(f.service.send_message("API route"), "API request starts")
	check(f.transport.starts.size() == 1 and f.transport.starts[0].token == "fixture-api-key", "API route uses only supplied API key")
	check(f.auth.requests.is_empty(), "API route never requests a ChatGPT token")
	check(f.transport.starts[0].payload.max_output_tokens == 512 and f.transport.starts[0].payload.model == Companion.DEFAULT_MODEL, "API route retains its own model and output limit")
	check(f.service.billing_label().contains("API Key"), "API billing is visible")
	f.transport.finish()
	f.keys.value = ""
	oauth(f)
	check(f.service.ready_to_chat() and f.service.billing_label().contains("ChatGPT"), "account route works without an API key and labels billing")
	var old_reads: int = f.keys.reads
	check(f.service.send_message("OAuth route"), "OAuth request waits for token")
	check(f.service.busy and f.transport.starts.size() == 1 and f.auth.requests.size() == 1, "no inference begins before verified token")
	f.auth.deliver(0)
	check(f.transport.starts.size() == 2 and f.transport.starts.back().token == "fixture-oauth-account-a", "OAuth route uses only account access token")
	check(f.keys.reads == old_reads, "OAuth route never reads API key as fallback")
	var payload: Dictionary = f.transport.starts.back().payload
	check(payload.model == "catalog-model-a" and payload.stream and not payload.store, "OAuth request uses selected catalog model and streaming")
	for forbidden in ["max_output_tokens","max_tokens","temperature","top_p","prompt","previous_response_id"]:
		check(not payload.has(forbidden), "OAuth request omits unsupported parameter " + forbidden)
	f.transport.finish()
	f.auth.synchronous = true
	check(f.service.send_message("synchronous token"), "synchronously cached token starts normally")
	check(f.transport.starts.size() == 3 and f.service.busy, "cached token does not lose busy lifecycle")
	f.transport.finish()
	check(f.service.test_connection(), "OAuth connection test starts")
	check(not f.transport.starts.back().payload.has("max_output_tokens"), "OAuth connection test does not inject API limit 32")
	f.transport.finish("连接成功")
	check(not f.service.busy and f.service.status.contains("连接成功"), "OAuth connection test completes")
	finish_fixture(f)

	f = fixture(); oauth(f)
	check(f.service.send_message("cancel pending token"), "pending-token request accepted")
	f.service.cancel(); f.auth.deliver(0)
	check(not f.service.busy and f.transport.starts.is_empty(), "cancelled token wait cannot start inference")
	check(f.service.send_message("newest request"), "retry after cancellation accepts new input")
	f.auth.deliver(0)
	check(f.transport.starts.is_empty() and f.service.busy, "a late canceled request ID cannot satisfy the new request")
	f.auth.deliver(1)
	check(f.transport.starts.size() == 1 and str(f.transport.starts[0].payload.input).contains("newest request") and not str(f.transport.starts[0].payload.input).contains("cancel pending token"), "shared credential refresh uses only newest noncancelled payload")
	f.transport.finish()
	check(f.service.send_message("cancel on model switch"), "model-switch fixture waits")
	f.auth.switch_model("catalog-model-b")
	check(not f.service.busy, "explicit model switch cancels a waiting request")
	f.auth.deliver(2)
	check(f.transport.starts.size() == 1, "late token cannot start old model request")
	finish_fixture(f)

	f = fixture(); oauth(f)
	f.auth.selected_model = ""; f.auth.changed.emit()
	check(f.service.send_message("initial catalog"), "account can request its initial refreshed catalog")
	f.auth.switch_model("fresh-catalog-model")
	f.auth.deliver(0)
	check(f.transport.starts.size() == 1 and f.transport.starts[0].payload.model == "fresh-catalog-model", "first catalog result sets model before inference")
	f.auth.switch_model("another-visible-model")
	check(not f.service.busy and f.transport.cancels == 1, "explicit model change cancels streaming request")
	check(f.service.send_message("waiting old identity"), "identity switch fixture waits")
	f.auth.switch_account("account-b")
	check(not f.service.busy, "account switch cancels pending inference")
	f.auth.deliver(1)
	check(f.transport.starts.size() == 1, "old identity cannot release a token into service")
	check(f.service.send_message("new identity"), "new selected identity can start its own request")
	f.auth.deliver(1)
	check(f.transport.starts.size() == 1, "old callback does not satisfy new account request")
	f.auth.token_ready.emit("fixture-oauth-account-a", int(f.auth.requests[1].id))
	check(f.transport.starts.size() == 1 and f.service.busy, "service also rejects a stale account token by its old request ID")
	f.auth.deliver(2)
	check(f.transport.starts.size() == 2 and f.transport.starts.back().token == "fixture-oauth-account-b", "new identity only uses its own credential")
	f.transport.finish()
	finish_fixture(f)

	f = fixture(); oauth(f)
	f.auth.authorized = false; f.auth.changed.emit()
	check(not f.service.ready_to_chat() and not f.service.send_message("no permission"), "declined plan permission blocks OAuth even when API key exists")
	check(f.transport.starts.is_empty() and f.keys.reads == 0 and f.service.settings.auth_method == "chatgpt", "OAuth failure never silently switches billing")
	f.auth.authorized = true
	f.service.send_message("refresh fails")
	f.auth.failed.emit("fixture refresh failed")
	check(not f.service.busy and f.transport.starts.is_empty() and f.service.status.contains("refresh failed"), "refresh failure remains visible without API fallback")
	check(f.service.apply_settings({"auth_method":"api_key"}) == OK, "user may explicitly change to API billing")
	check(f.service.send_message("explicit API"), "explicit API route works after account failure")
	check(f.transport.starts.back().token == "fixture-api-key", "only explicit route change permits API key use")
	f.service.cancel()
	f.keys.value = ""
	check(not f.service.send_message("missing API key") and f.auth.requests.size() == 1, "missing API key never silently falls back to ChatGPT account")
	finish_fixture(f)
	f = fixture(); oauth(f)
	f.auth.synchronous = true
	check(f.service.send_message("same-account session replacement"), "same-account replacement fixture starts a real stream")
	f.auth.changed.emit()
	check(f.service.busy and f.transport.cancels == 0, "routine authentication status and token refresh updates do not interrupt a stream")
	f.auth.session_revision += 1; f.auth.changed.emit()
	check(not f.service.busy and f.transport.cancels == 1, "successful relogin cancels old-token stream even when account and model are unchanged")
	f.auth.synchronous = false
	check(f.service.send_message("waiting before same-account replacement"), "relogin during pending token has a current request")
	var waiting_index: int = f.auth.requests.size() - 1
	f.auth.session_revision += 1; f.auth.changed.emit(); f.auth.deliver(waiting_index)
	check(not f.service.busy and f.transport.starts.size() == 1, "old same-account token callback cannot revive the request after reauthentication")
	check(f.service.apply_settings({"auth_method":"api_key"}) == OK and f.service.send_message("API unaffected by relogin"), "separate API request starts normally")
	f.auth.session_revision += 1; f.auth.changed.emit()
	check(f.service.busy and f.transport.cancels == 1, "ChatGPT session replacement does not cancel independent API-key requests")
	finish_fixture(f)
	f = fixture()
	check(f.service.apply_settings({"enabled":true,"auth_method":"chatgpt","model":""}) == OK, "hidden inactive API model does not block a valid ChatGPT route")
	check(f.service.apply_settings({"auth_method":"api_key"}) == ERR_INVALID_PARAMETER, "returning to API billing still validates its own model")
	finish_fixture(f)
	await process_frame
	print("AI auth route: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
