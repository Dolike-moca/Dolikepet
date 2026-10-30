extends SceneTree
## Offline integration: generated conversations, fake credentials and isolated storage.
## Covers the background worker's boundary with visible chat, persistence and consent.
const Companion = preload("res://scripts/ai_companion.gd")
const Store = preload("res://scripts/ai_store.gd")
var failures: Array[String] = []
var checks := 0
var fixture_number := 0

class Transport extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var starts: Array = []
	var busy := false
	var generation := 0
	var reject := false
	var reject_with_signal := false
	var cancels := 0
	func start(token: String, payload: Dictionary) -> bool:
		if reject_with_signal: failed.emit("fixture synchronous rejection"); return false
		if reject: return false
		generation += 1
		starts.append({"token":token,"payload":payload.duplicate(true),"generation":generation})
		busy = true
		return true
	func cancel() -> void:
		if not busy: return
		busy = false; generation += 1; cancels += 1; canceled.emit()
	func finish(text: String, expected_generation: int = -1) -> void:
		# Mirrors ai_http's generation guard after closing an old HTTP client.
		if not busy or (expected_generation >= 0 and expected_generation != generation): return
		busy = false; completed.emit(text)
	func error(message: String) -> void:
		if not busy: return
		busy = false; failed.emit(message)

class Keys extends RefCounted:
	var value := "fixture-memory-api-key"
	var reads := 0
	func setup(_native: Object, _path: String) -> void: pass
	func has_key() -> bool: return not value.is_empty()
	func load_key() -> String: reads += 1; return value
	func save_key(text: String) -> Error: value = text; return OK
	func clear_key() -> Error: value = ""; return OK

class Auth extends Node:
	signal token_ready(token: String, request_id: int)
	signal failed(message: String)
	signal changed
	var active_id := "memory-fixture-account"
	var selected_model := "fixture-catalog-model"
	var requests: Array = []
	func can_infer() -> bool: return not active_id.is_empty()
	func active_label() -> String: return "memory fixture"
	func request_access_token(request_id: int) -> void: requests.append(request_id)
	func deliver(index: int) -> void: token_ready.emit("fixture-memory-account-token", int(requests[index]))

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("AI MEMORY SERVICE: " + label)

func fixture(options: Dictionary = {}, existing_path: String = "") -> Dictionary:
	fixture_number += 1
	var clock := {"now":1800000000}
	var service = Companion.new()
	var transport := Transport.new()
	var keys := Keys.new()
	service.configure_dependencies(transport, keys)
	service.clock_override = func(): return int(clock.now)
	service.day_override = "2026-10-31"
	service.hour_override = 12
	root.add_child(service)
	var path := existing_path if not existing_path.is_empty() else ProjectSettings.globalize_path("res://../../_work/tests/ai-memory-service/%d-%d" % [OS.get_process_id(),fixture_number])
	service.setup(null, path, bool(options.get("network", true)))
	var signals := {"starts":[],"deltas":[],"completions":[],"failures":[],"cancels":0,"memory_changes":0}
	service.request_started.connect(func(kind): signals.starts.append(kind))
	service.delta.connect(func(text): signals.deltas.append(text))
	service.reply_completed.connect(func(text, proactive): signals.completions.append([text,proactive]))
	service.failed.connect(func(text): signals.failures.append(text))
	service.request_canceled.connect(func(): signals.cancels += 1)
	service.memories_changed.connect(func(): signals.memory_changes += 1)
	if bool(options.get("enable", true)):
		check(service.apply_settings({"enabled":true}) == OK, "fixture enables isolated fake-key route")
	return {"service":service,"transport":transport,"keys":keys,"clock":clock,"path":path,"signals":signals}

func close_fixture(f: Dictionary) -> void:
	f.service.shutdown()
	f.service.free()
	if f.has("auth"): f.auth.free()

func chat(f: Dictionary, text: String = "我喜欢吃薯条。", response: String = "猫猫听到了，喵。") -> void:
	check(f.service.send_message(text), "ordinary user conversation starts")
	f.transport.finish(response)

func idle(f: Dictionary, day: String = "", seconds: int = 121) -> void:
	f.clock.now += seconds
	if not day.is_empty(): f.service.day_override = day
	f.service._memory_tick(true)

func result_for(f: Dictionary, text: String = "用户喜欢吃薯条", subject: String = "饮食偏好:薯条") -> String:
	var batch: Array = f.service.memory_ledger.batch()
	if batch.is_empty(): return '{"items":[]}'
	var source: Dictionary = batch[0]
	return JSON.stringify({"items":[{"op":"remember","text":text,"kind":"preference","subject":subject,
		"target_id":"","source_ids":[source.id],"quote":str(source.text),"expires_at":0}]})

func activity_counts(f: Dictionary) -> Dictionary:
	return {"starts":f.signals.starts.size(),"deltas":f.signals.deltas.size(),"completions":f.signals.completions.size(),
		"failures":f.signals.failures.size(),"cancels":f.signals.cancels,"history":f.service.history.size()}

func run() -> void:
	var f := fixture()
	check(f.service.settings.auto_memory_enabled and f.transport.starts.is_empty(), "automatic memory defaults on without a request at setup")
	check(f.service._clean_settings({"proactive_daily_limit":0}).proactive_daily_limit == 0, "service retains unlimited daily invitation sentinel")
	chat(f)
	check(f.service.memory_ledger.batch().size() == 1, "completed user message becomes a pending source")
	check(not JSON.stringify(f.service.memory_ledger.batch()).contains("猫猫听到了"), "assistant text never becomes extraction evidence")
	check(f.service.memory_entries().is_empty(), "ordinary chat completion does not immediately invent a memory")
	var baseline := activity_counts(f)
	f.service._memory_tick(true)
	check(f.service.request_kind.is_empty(), "memory worker waits for the idle interval")
	f.clock.now += 121
	f.service._memory_tick(false)
	check(f.transport.starts.size() == 1, "host gameplay and conversation gate defers background memory")
	f.service.external_proactive = true
	f.service.tick(1.0, {}, true)
	check(f.service.request_kind == "memory" and f.service._busy and not f.service.busy, "external proactive coordinator does not skip silent memory worker")
	check(f.transport.starts.size() == 2, "eligible new chat creates exactly one extraction request")
	var payload: Dictionary = f.transport.starts.back().payload
	check(payload.stream and not payload.store and not payload.has("previous_response_id"), "background request remains stateless streamed inference")
	check(not JSON.stringify(payload.input).contains("猫猫听到了"), "daily request contains only user evidence, not assistant replies")
	f.transport.delta.emit('{"items":[')
	check(activity_counts(f) == baseline, "background streaming does not change chat signals or history")
	f.transport.finish(result_for(f))
	check(activity_counts(f) == baseline and not f.service._busy, "memory completion remains silent and releases transport")
	check(f.service.memory_entries().size() == 1 and f.service.memory_entries()[0].tier == "recent", "validated extraction creates recent memory")
	check(f.service._instructions().contains("用户喜欢吃薯条"), "enabled automatic memory becomes available to ordinary conversation")
	chat(f, "我还喜欢散步。")
	idle(f)
	check(f.service.request_kind.is_empty(), "same local day cannot start a second daily extraction")
	var previous_path: String = f.path
	close_fixture(f)
	f = fixture({}, previous_path)
	idle(f)
	check(f.transport.starts.is_empty(), "restarting cannot bypass persisted daily extraction limit")
	idle(f, "2026-11-01", 86400)
	check(f.service.request_kind == "memory", "next day can process newly queued conversation")
	f.transport.finish('{"items":[]}')
	check(not f.service._busy, "empty valid extraction finishes without manufacturing memories")
	close_fixture(f)

	f = fixture()
	chat(f)
	idle(f)
	baseline = activity_counts(f)
	var old_generation: int = f.transport.generation
	var obsolete_response := result_for(f)
	check(f.service.send_message("先陪我说句话"), "manual chat preempts background memory immediately")
	check(f.transport.cancels == 1 and f.service.request_kind == "chat" and f.service.busy, "preemption closes worker before foreground transport starts")
	check(f.signals.cancels == baseline.cancels, "silent worker cancellation emits no visible cancellation")
	f.transport.finish(obsolete_response, old_generation)
	check(f.service.request_kind == "chat" and f.service.memory_entries().is_empty(), "closed worker generation cannot write memories or finish current chat")
	f.transport.finish("我在听，喵。")
	check(f.service.history.back().text == "我在听，喵。", "foreground chat completes after worker preemption")
	close_fixture(f)

	f = fixture()
	chat(f); idle(f)
	baseline = activity_counts(f)
	check(f.service.test_connection() and f.service.request_kind == "test", "explicit connection test can preempt memory")
	f.transport.finish("连接成功")
	check(f.signals.completions.size() == baseline.completions and f.signals.cancels == baseline.cancels, "connection test preemption produces no accidental chat")
	close_fixture(f)

	f = fixture()
	chat(f); idle(f)
	baseline = activity_counts(f)
	f.transport.error("fixture memory network unavailable")
	check(activity_counts(f) == baseline and not f.service._busy, "background network failure never reaches speech or foreground errors")
	idle(f)
	check(f.transport.starts.size() == 2, "failed memory request is not automatically retried the same day")
	idle(f, "2026-11-01", 86400)
	check(f.service.request_kind == "memory", "failed batch can be retried on a later day")
	f.transport.finish("not valid JSON")
	check(f.service.memory_entries().is_empty() and not f.service._busy, "malformed extraction is rejected without memories or busy lock")
	check(activity_counts(f) == baseline, "malformed extraction remains silent")
	close_fixture(f)

	for setting in ["auto_memory_enabled", "memory_enabled"]:
		f = fixture()
		var disabled_option := {}; disabled_option[setting] = false
		check(f.service.apply_settings(disabled_option) == OK, "memory option can be disabled: " + setting)
		chat(f); idle(f)
		check(f.service.memory_ledger.batch().is_empty() and f.transport.starts.size() == 1, "opt-out prevents source collection and extraction: " + setting)
		check(f.service.add_memory("固定测试偏好"), "manual fixed memory remains editable while automatic collection is off")
		if setting == "memory_enabled": check(not f.service._instructions().contains("固定测试偏好"), "memory sharing opt-out excludes saved facts from request context")
		close_fixture(f)
	f = fixture()
	chat(f)
	check(f.service.apply_settings({"auto_memory_enabled":false}) == OK, "automatic memory can be disabled after conversation")
	check(f.service.memory_ledger.batch().is_empty(), "disabling automatic memory discards queued sources")
	check(f.service.apply_settings({"auto_memory_enabled":true}) == OK, "automatic memory can be enabled again")
	idle(f)
	check(f.transport.starts.size() == 1, "re-enabling does not retrospectively import old conversations")
	close_fixture(f)

	f = fixture()
	chat(f); idle(f)
	var extraction := result_for(f)
	var saved_root: String = f.service._store.root_path
	f.service._store.root_path = ""
	baseline = activity_counts(f)
	f.transport.finish(extraction)
	check(f.service.memory_entries().is_empty() and not f.service.memory_ledger.batch().is_empty(), "failed storage rolls back memory creation and source consumption")
	check(activity_counts(f) == baseline, "background storage failure does not interrupt chat")
	f.service._store.root_path = saved_root
	close_fixture(f)

	f = fixture()
	chat(f); idle(f); f.transport.finish(result_for(f))
	var memory_id: String = f.service.memory_entries()[0].id
	chat(f)
	idle(f, "2026-11-01", 86400)
	old_generation = f.transport.generation
	extraction = result_for(f)
	check(f.service.forget_memory_id(memory_id), "memory can be explicitly forgotten while extraction is running")
	check(not f.service._busy and f.service.memory_entries().is_empty(), "forget invalidates worker before removing memory")
	f.transport.finish(extraction, old_generation)
	check(f.service.memory_entries().is_empty(), "late extraction cannot resurrect a forgotten fact")
	idle(f, "2026-11-02", 86400)
	if f.service.request_kind == "memory":
		f.transport.finish(result_for(f, "用户爱吃炸薯条", "食品偏好:炸土豆条"))
	check(f.service.memory_entries().is_empty(), "queued pre-deletion repetition cannot resurrect through a paraphrased memory next day")
	close_fixture(f)

	f = fixture()
	chat(f); idle(f)
	old_generation = f.transport.generation
	extraction = result_for(f)
	f.service.clear_history()
	check(f.service.history.is_empty() and f.service.memory_ledger.batch().is_empty() and not f.service._busy, "clearing chat cancels worker and discards queued chat evidence")
	f.transport.finish(extraction, old_generation)
	check(f.service.memory_entries().is_empty(), "cleared chat cannot produce a delayed memory")
	close_fixture(f)

	verify_legacy_migration()
	verify_mutation_and_policy_boundaries()
	verify_edit_pin_commands()
	verify_oauth_worker()
	verify_independent_memory_routes()
	await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures,"offline":true}))
	quit(0 if failures.is_empty() else 1)

func verify_legacy_migration() -> void:
	fixture_number += 1
	var path := ProjectSettings.globalize_path("res://../../_work/tests/ai-memory-service/%d-legacy-%d" % [OS.get_process_id(),fixture_number])
	var store = Store.new(); store.setup(path)
	var legacy := {"schema":1,"settings":{"enabled":false},"history":[{"role":"user","text":"旧聊天不应被重新学习","at":10,"state":"complete"}],"memories":["用户固定保存的称呼"]}
	check(store.save_data(legacy) == OK, "legacy fixture persists in isolated directory")
	var f := fixture({"enable":false}, path)
	check(f.service.memory_entries().size() == 1 and f.service.memory_entries()[0].tier == "fixed", "legacy manual memories migrate to fixed tier")
	check(f.service.history == legacy.history and f.service.memory_ledger.batch().is_empty(), "migration preserves history without importing it as evidence")
	f.clock.now += 400 * 86400
	f.service._memory_tick(true)
	check(f.service.memory_entries().size() == 1, "fixed legacy memory does not automatically decay")
	check(f.transport.starts.is_empty(), "disabled AI never runs extraction during migration or decay")
	close_fixture(f)

func verify_oauth_worker() -> void:
	var f := fixture()
	chat(f)
	var authority := Auth.new(); root.add_child(authority)
	f.auth = authority; f.service.bind_auth(authority)
	check(f.service.apply_settings({"auth_method":"chatgpt"}) == OK, "authorized fake OAuth route can be selected")
	var key_reads: int = f.keys.reads
	idle(f)
	check(f.service.request_kind == "memory" and f.service._auth_waiting and f.transport.starts.size() == 1, "background OAuth request waits for verified account token")
	check(f.service.send_message("前台优先"), "manual chat preempts background token wait")
	authority.deliver(0)
	check(f.transport.starts.size() == 1, "late worker token cannot start obsolete inference")
	authority.deliver(1)
	check(f.transport.starts.size() == 2 and f.transport.starts.back().token == "fixture-memory-account-token", "foreground request receives only its own authorized token")
	check(f.keys.reads == key_reads, "OAuth preemption never reads an API key fallback")
	f.transport.finish("当然，喵。")
	idle(f, "2026-11-01", 86400)
	authority.deliver(2)
	var payload: Dictionary = f.transport.starts.back().payload
	check(payload.model == "fixture-catalog-model" and not payload.has("max_output_tokens"), "memory uses selected OAuth model and omits unsupported API token limit")
	f.transport.finish('{"items":[]}')
	check(not f.service._busy and f.keys.reads == key_reads, "OAuth daily memory finishes without API billing fallback")
	close_fixture(f)

func verify_mutation_and_policy_boundaries() -> void:
	var f := fixture()
	check(f.service.send_message("这条请求会失败"), "failed-turn fixture starts")
	f.transport.error("fixture failure")
	check(f.service.memory_ledger.batch().is_empty(), "failed user turn is not submitted as automatic memory evidence")
	check(f.service.send_message("这条请求会取消"), "cancelled-turn fixture starts")
	f.service.cancel()
	check(f.service.memory_ledger.batch().is_empty(), "cancelled user turn is not submitted as automatic memory evidence")
	chat(f); idle(f)
	var old_generation: int = f.transport.generation
	var response := result_for(f)
	check(f.service.apply_settings({"memory_enabled":false}) == OK, "memory sharing can be disabled during extraction")
	check(not f.service._busy and f.service.memory_ledger.batch().is_empty(), "privacy opt-out closes worker and discards queued sources")
	f.transport.finish(response, old_generation)
	check(f.service.memory_entries().is_empty(), "late response cannot bypass memory privacy opt-out")
	close_fixture(f)

func attach_auth(f: Dictionary) -> Auth:
	var authority := Auth.new()
	root.add_child(authority)
	f.auth = authority
	f.service.bind_auth(authority)
	return authority

func verify_independent_memory_routes() -> void:
	var f := fixture()
	var authority := attach_auth(f)
	check(f.service._clean_settings({"memory_auth_method":"untrusted-url"}).memory_auth_method == "follow", "unsupported memory route safely defaults to follow")
	check(f.service.apply_settings({"memory_auth_method":"chatgpt"}) == OK, "API chat can select independent ChatGPT memory route")
	chat(f)
	var before_key_reads: int = f.keys.reads
	idle(f)
	check(f.service.request_kind == "memory" and f.service._auth_waiting and authority.requests.size() == 1, "independent ChatGPT memory waits for OAuth while ordinary chat uses API")
	authority.deliver(0)
	var request: Dictionary = f.transport.starts.back()
	check(request.token == "fixture-memory-account-token" and request.payload.model == authority.selected_model, "independent memory request uses ChatGPT token and catalog model")
	check(not request.payload.has("max_output_tokens") and f.keys.reads == before_key_reads, "independent OAuth memory never uses API budget parameter or API credential")
	f.transport.finish('{"items":[]}')
	chat(f, "我喜欢轻松的聊天。")
	check(f.transport.starts.back().token == "fixture-memory-api-key" and f.transport.starts.back().payload.has("max_output_tokens"), "memory route leaves ordinary chat's API route unchanged")
	var path: String = f.path
	close_fixture(f)
	f = fixture({"enable":false}, path)
	check(f.service.settings.memory_auth_method == "chatgpt" and f.service.settings.auth_method == "api_key", "independent memory route survives restart without changing chat route")
	idle(f, "2026-11-02", 2 * 86400)
	check(f.transport.starts.is_empty(), "missing remembered OAuth authority never falls back to an available API key")
	close_fixture(f)

	f = fixture()
	authority = attach_auth(f)
	check(f.service.apply_settings({"auth_method":"chatgpt","memory_auth_method":"api_key"}) == OK, "ChatGPT chat can select independent API memory route")
	check(f.service.send_message("我喜欢散步。"), "independent-route foreground OAuth chat begins")
	authority.deliver(0)
	f.transport.finish("猫猫也想听听散步的事。")
	var before_auth_calls: int = authority.requests.size()
	idle(f)
	request = f.transport.starts.back()
	check(f.service.request_kind == "memory" and request.token == "fixture-memory-api-key", "independent API memory uses only the API key")
	check(request.payload.model == Companion.DEFAULT_MODEL and request.payload.max_output_tokens == 2048 and authority.requests.size() == before_auth_calls, "API memory uses API model/limit without requesting ChatGPT authority")
	f.transport.finish('{"items":[]}')
	check(f.service.settings.auth_method == "chatgpt", "independent API memory does not change chat account route")
	check(f.service.send_message("我现在喜欢喝茶。"), "new foreground OAuth conversation begins")
	authority.deliver(1)
	f.transport.finish("记下这个话题，喵。")
	f.keys.value = ""
	var starts_before: int = f.transport.starts.size()
	idle(f, "2026-11-01", 86400)
	check(f.transport.starts.size() == starts_before and authority.requests.size() == 2 and f.service.request_kind.is_empty(), "lost API credential cannot silently charge ChatGPT for memory")
	close_fixture(f)

	f = fixture()
	check(f.service.apply_settings({"memory_auth_method":"chatgpt"}) != OK and f.service.settings.memory_auth_method == "follow", "selecting unavailable memory OAuth route is rejected without mutation")
	authority = attach_auth(f)
	f.keys.value = ""
	check(f.service.apply_settings({"auth_method":"chatgpt","memory_auth_method":"api_key"}) != OK, "selecting unavailable memory API route is rejected even with valid ChatGPT")
	check(f.service.apply_settings({"auth_method":"chatgpt","memory_auth_method":"follow"}) == OK, "follow route uses available current ChatGPT authority")
	check(f.service._memory_route() == "chatgpt", "follow resolves to selected chat account")
	f.keys.value = "fixture-memory-api-key"
	check(f.service.apply_settings({"auth_method":"api_key"}) == OK and f.service._memory_route() == "api_key", "follow automatically tracks an explicit chat route change")
	close_fixture(f)

func verify_edit_pin_commands() -> void:
	var f: Dictionary
	var old_generation := 0
	var response := ""
	for action in ["edit", "pin"]:
		f = fixture()
		chat(f); idle(f); f.transport.finish(result_for(f))
		var id: String = f.service.memory_entries()[0].id
		chat(f, "我现在不喜欢吃薯条了。")
		idle(f, "2026-11-01", 86400)
		old_generation = f.transport.generation
		response = result_for(f)
		var deferred_result: Dictionary = JSON.parse_string(response)
		deferred_result.items[0].op = "correct"
		deferred_result.items[0].target_id = id
		deferred_result.items[0].text = "用户现在不喜欢吃薯条"
		f.clock.now += 10
		var changed: bool = f.service.edit_memory_id(id, "用户现在偶尔吃薯条") if action == "edit" else f.service.pin_memory_id(id)
		check(changed and not f.service._busy, action + " invalidates an in-flight memory extraction")
		var saved_entries: Array = f.service.memory_entries().duplicate(true)
		f.transport.finish(response, old_generation)
		check(f.service.memory_entries() == saved_entries, "obsolete extraction cannot overwrite manual " + action)
		if action == "pin": check(saved_entries[0].tier == "fixed", "pinning removes automatic expiry")
		idle(f, "2026-11-02", 86400)
		if f.service.request_kind == "memory": f.transport.finish(JSON.stringify(deferred_result))
		check(f.service.memory_entries() == saved_entries, "pre-mutation source cannot override manual " + action + " in a future daily batch")
		close_fixture(f)

	f = fixture()
	chat(f, "请记住：我的昵称是小铃。")
	check(f.service.memory_entries().size() == 1 and f.service.memory_entries()[0].tier == "fixed", "explicit remember command creates fixed memory immediately")
	check(f.service.memory_ledger.batch().is_empty(), "explicit memory operation is not learned again as a daily source")
	chat(f, "请忘掉：小铃。")
	check(f.service.memory_entries().is_empty(), "explicit forget command removes matching memory immediately")
	check(f.service.memory_ledger.batch().is_empty(), "forget request itself never becomes a new memory")
	close_fixture(f)
