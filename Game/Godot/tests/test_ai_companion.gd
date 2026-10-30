extends SceneTree
## Entirely offline: fake requests/keys and a unique directory under _work.

const Companion = preload("res://scripts/ai_companion.gd")
const Store = preload("res://scripts/ai_store.gd")

class FakeTransport extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var calls: Array = []
	var busy := false
	var reject := false
	var reject_signal := false
	func start(_key: String, payload: Dictionary) -> bool:
		if reject_signal:
			reject_signal = false
			failed.emit("同步失败测试")
			return false
		if reject: return false
		calls.append(payload.duplicate(true))
		busy = true
		return true
	func cancel() -> void:
		busy = false
		canceled.emit()
	func finish(text: String) -> void:
		busy = false
		completed.emit(text)
	func error(text: String) -> void:
		busy = false
		failed.emit(text)

class FakeKeys extends RefCounted:
	var key := ""
	var deny_save := false
	func setup(_native: Object, _path: String) -> void: pass
	func has_key() -> bool: return not key.is_empty()
	func load_key() -> String: return key
	func save_key(value: String) -> Error:
		if deny_save: return ERR_UNAVAILABLE
		key = value
		return OK
	func clear_key() -> Error:
		key = ""
		return OK

var failures: Array[String] = []
var checks := 0
var current_time := 1800000000
var received_delta := ""
var completions: Array = []
var cancel_count := 0
var start_kinds: Array = []

func _initialize() -> void: call_deferred("run")
func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var path := ProjectSettings.globalize_path("res://../../_work/tests/ai-service/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(path)
	var service = Companion.new()
	var transport := FakeTransport.new()
	var keys := FakeKeys.new()
	service.configure_dependencies(transport, keys)
	service.clock_override = func(): return current_time
	root.add_child(service)
	service.setup(null, path, true)
	service.delta.connect(func(text): received_delta += text)
	service.reply_completed.connect(func(text, proactive): completions.append([text, proactive]))
	service.request_canceled.connect(func(): cancel_count += 1)
	service.request_started.connect(func(kind): start_kinds.append(kind))
	verify(not service.settings.enabled and not service.settings.proactive, "AI and proactive are opt-in")
	verify(service.settings.model == "gpt-6-luna", "current configurable default model")
	verify(service.settings.personality == Companion.DEFAULT_PERSONALITY and service.memories.is_empty(), "fresh default style does not manufacture user memories")
	verify(not service.send_message("你好"), "disabled companion sends nothing")
	verify(transport.calls.is_empty(), "no automatic network request at setup")
	verify(service.apply_settings({"enabled": true}) != OK, "enabled configuration requires saved key")
	verify(service.apply_settings({"enabled": true}, "sk-offline-test-only") == OK, "settings can save with fake protected key")
	verify(service.has_key(), "key presence is exposed without leaking key")
	verify(service.send_message("你好", {"satiety_percent": 60, "dizzy": true, "bowl_open": true, "files": ["sensitive.txt"], "file_contents": "secret content"}), "chat begins")
	verify(service.busy and service.request_kind == "chat", "request state is visible")
	var unchanged_serial: int = service._request_serial
	verify(service.apply_settings(service.settings.duplicate(true)) == OK and service.busy and service._request_serial == unchanged_serial, "unmodified AI draft never interrupts live chat")
	verify(not service.send_message("不应并行"), "only one manual request at a time")
	var payload: Dictionary = transport.calls.back()
	verify(payload.stream and not payload.store and not payload.has("previous_response_id"), "stateless streaming Responses request")
	verify(payload.model == "gpt-6-luna" and payload.reasoning.effort == "none", "default model low reasoning mode")
	verify(payload.instructions.contains('"satiety_percent":60') and not payload.instructions.contains("sensitive") and not payload.instructions.contains("secret content"), "state allowlist excludes files and unknown fields")
	verify(not payload.has("tools") and not JSON.stringify(payload).contains("sk-offline"), "no tool authority or key in JSON body")
	verify(payload.instructions.contains("名字是東菱可") and payload.instructions.contains("默认称呼用户为大人"), "chat carries approved character identity and default address")
	transport.delta.emit("你好，")
	transport.delta.emit("我在这里喵。")
	verify(received_delta == "你好，我在这里喵。", "stream deltas are forwarded")
	verify(service.history.size() == 1 and service.history[0].state == "pending", "pending user shown while streaming")
	transport.finish("你好，我在这里喵。")
	verify(not service.busy and service.history.size() == 2, "completion records both sides")
	verify(service.history[0].state == "complete" and service.history[1].text == completions.back()[0], "history finalized before completion signal")
	verify(service.memories.is_empty(), "chat is not promoted before validated daily extraction")
	verify(service.add_memory("用户喜欢紫色"), "explicit memory creation")
	verify(not service.add_memory("用户喜欢紫色"), "memory duplicates rejected")
	verify(service.update_memory(0, "用户喜欢紫色和猫猫"), "memory can be edited")
	verify(not service.add_memory("字".repeat(301)), "memory length bounded")
	verify(service.send_message("记得吗？"), "second chat begins")
	payload = transport.calls.back()
	verify(payload.instructions.contains("用户喜欢紫色和猫猫"), "confirmed memory appears in context")
	verify(payload.input.size() == 3 and payload.input[0].content == "你好", "local completed conversation reused")
	transport.delta.emit("尚未完成")
	var before_cancel := cancel_count
	service.cancel()
	verify(not service.busy and cancel_count == before_cancel + 1 and service.history.back().state == "canceled", "cancel ends speech and records canceled user")
	verify(not str(service.history).contains("尚未完成"), "partial reply is not persisted")
	verify(service.send_message("继续吧"), "new request after cancellation")
	payload = transport.calls.back()
	verify(payload.input.size() == 3 and not JSON.stringify(payload.input).contains("记得吗"), "canceled turn excluded from context")
	transport.error("暂时无法连接，请稍后重试")
	verify(not service.busy and service.history.back().state == "failed", "failed request is retryable without busy lock")
	before_cancel = cancel_count
	verify(service.apply_settings({"model": "custom-gpt-model", "include_pet_state": false, "memory_enabled": false}) == OK, "advanced settings save")
	verify(cancel_count == before_cancel + 1, "changing model/context also clears previous completed speech")
	verify(service.send_message("你好"), "custom model request")
	payload = transport.calls.back()
	verify(not payload.has("reasoning"), "custom model never receives incompatible reasoning setting")
	verify(not payload.instructions.contains("satiety_percent") and not payload.instructions.contains("用户喜欢紫色和猫猫"), "context and memory opt-outs respected")
	verify(payload.instructions.contains("名字是東菱可"), "fixed character remains when optional user memories are disabled")
	transport.finish("你好。")
	var history_before: int = service.history.size()
	var completion_before := completions.size()
	var delta_before := received_delta
	verify(service.test_connection(), "saved configuration can be tested")
	verify(service.request_kind == "test" and transport.calls.back().max_output_tokens == 32, "connection test is distinct and short")
	transport.delta.emit("连接成功")
	transport.finish("连接成功")
	verify(service.history.size() == history_before and completions.size() == completion_before and received_delta == delta_before, "connection test never enters chat or bubble")
	verify(service.status.contains("连接成功"), "test result is shown")
	service.remove_memory(0)
	verify(service.memories.is_empty(), "memory removal applies")
	before_cancel = cancel_count
	service.clear_history()
	verify(service.history.is_empty(), "history can be cleared independently")
	verify(cancel_count == before_cancel + 1, "clearing completed history also stops any remaining speech")
	verify(service.apply_settings({"proactive": true, "proactive_interval_minutes": 15, "quiet_start": 22, "quiet_end": 8}) == OK, "proactive opt-in configured")
	service.hour_override = 23
	current_time += 901
	var before := transport.calls.size()
	service.tick(1.0, {}, true)
	verify(transport.calls.size() == before, "night quiet hours cross midnight")
	service.hour_override = 9
	service.tick(1.0, {}, false)
	verify(transport.calls.size() == before, "gameplay/busy presentation gate blocks proactive")
	service.tick(1.0, {"game": "juggle", "last_game_score": 42}, true)
	verify(service.busy and service.request_kind == "proactive", "eligible greeting starts once")
	service.tick(1200.0, {}, true)
	verify(transport.calls.size() == before + 1, "active greeting never queues another")
	before_cancel = cancel_count
	verify(service.send_message("我想聊一下"), "manual conversation preempts proactive request")
	verify(service.request_kind == "chat" and cancel_count == before_cancel + 1, "preempted greeting stops before manual chat")
	transport.finish("我听着呢。")
	current_time += 899
	service.tick(1.0, {}, true)
	verify(not service.busy, "greeting cooldown follows user conversation")
	current_time += 2
	service.tick(1.0, {}, true)
	verify(service.request_kind == "proactive", "greeting resumes after configured cooldown")
	transport.finish("喝口水，歇一会儿吧。")
	verify(completions.back()[1] == true, "proactive response identified")
	service.tick(9000.0, {}, true)
	verify(not service.busy, "elapsed delta alone cannot create catch-up burst")
	var stored = Store.new()
	stored.setup(path)
	var saved: Dictionary = stored.load_data()
	verify(saved.settings.model == "custom-gpt-model" and saved.history.size() == service.history.size(), "bounded local state persists")
	verify(not JSON.stringify(saved).contains("sk-offline"), "credential absent from all companion state")
	verify(saved.last_proactive == current_time, "greeting cooldown persisted")
	keys.deny_save = true
	verify(service.apply_settings({"model": "should-not-save"}, "sk-other-offline") != OK and service.settings.model == "custom-gpt-model", "failed protected key update leaves prior settings")
	keys.deny_save = false
	transport.reject = true
	verify(not service.send_message("无法开始") and not service.busy, "synchronous transport rejection never sticks busy")
	transport.reject = false
	verify(service.history.back().state == "failed", "transport start rejection marks pending turn")
	service.failed.connect(func(_message): service.send_message("同步失败后的新请求"), CONNECT_ONE_SHOT)
	transport.reject_signal = true
	verify(not service.send_message("同步失败") and service.busy and transport.busy, "synchronous failure listener may start new request without old start swallowing it")
	transport.finish("新请求完成。")
	verify(service.history.back().text == "新请求完成。", "reentrant retry completes normally")
	verify(service.send_message("超长回复"), "oversize fixture starts")
	service.failed.connect(func(_message): service.send_message("超长失败后的新请求"), CONNECT_ONE_SHOT)
	transport.delta.emit("猫".repeat(8001))
	verify(service.busy and transport.busy and service.history.back().text == "超长失败后的新请求", "oversize abort closes old transport before exposing failure")
	transport.finish("短回复。")
	verify(service.send_message("取消前"), "cancel reentrancy fixture starts")
	service.request_canceled.connect(func(): service.send_message("取消后的新请求"), CONNECT_ONE_SHOT)
	service.cancel()
	verify(service.busy and transport.busy and service.history.back().text == "取消后的新请求", "old cancel fallback cannot swallow request started by canceled listener")
	transport.finish("取消后的回复。")
	var calls_before_cancel_start := transport.calls.size()
	service.request_started.connect(func(_kind): service.cancel(), CONNECT_ONE_SHOT)
	verify(not service.send_message("开始即取消") and not service.busy and transport.calls.size() == calls_before_cancel_start, "request canceled by started listener never reaches transport")
	verify(service.apply_settings({"enabled": false}, "", true) == OK and not service.has_key(), "key can be erased with disabled AI")
	var offline = Companion.new()
	var offline_transport := FakeTransport.new()
	var offline_keys := FakeKeys.new()
	offline_keys.key = "sk-isolated"
	offline.configure_dependencies(offline_transport, offline_keys)
	root.add_child(offline)
	offline.setup(null, path.path_join("disabled-network"), false)
	verify(offline.apply_settings({"enabled": true}) == OK and not offline.send_message("禁网"), "network_allowed false blocks even configured service")
	verify(offline_transport.calls.is_empty(), "offline tests cannot accidentally call HTTP")
	offline.free()
	# Malformed/untrusted local JSON is bounded, whitelisted and recoverable.
	var dirty_history: Array = [{"role": "user", "text": "interrupted", "state": "pending", "at": -4}, {"role": "system", "text": "not allowed"}, {"role": "assistant", "text": {"bad": true}}]
	var cleaned_history: Array = service._clean_history(dirty_history)
	verify(cleaned_history.size() == 1 and cleaned_history[0].state == "failed" and cleaned_history[0].at == 0, "interrupted and malformed stored turns sanitized")
	var clean_settings: Dictionary = service._clean_settings({"enabled": "true", "model": " custom-model ", "api_key": "must-not-copy", "proactive_interval_minutes": 1, "max_output_tokens": 999999, "quiet_start": 29})
	verify(not clean_settings.enabled and clean_settings.model == "custom-model" and not clean_settings.has("api_key"), "settings reject coercion and secret/unknown fields")
	verify(clean_settings.proactive_interval_minutes == 5 and clean_settings.max_output_tokens == 1024 and clean_settings.quiet_start == 23, "time and spending-related limits are bounded")
	verify(not service._clean_settings({"quiet_start":0,"quiet_end":0}).quiet_enabled, "legacy equal quiet endpoints migrate to disabled switch")
	verify(service._clean_settings({"quiet_start":22,"quiet_end":8}).quiet_enabled, "legacy overnight quiet period remains enabled")
	verify(not service._clean_settings({"quiet_enabled":false,"quiet_start":22,"quiet_end":8}).quiet_enabled, "explicit quiet opt-out is retained with saved hours")
	verify(service.apply_settings({"quiet_enabled":false,"quiet_start":22,"quiet_end":8,"proactive_interval_minutes":5}) == OK, "quiet switch and fastest frequency persist")
	verify(not service._quiet(23) and service.settings.quiet_start == 22 and service.settings.quiet_end == 8, "disabled quiet hours no longer suppress night and retain time range")
	verify(service.apply_settings({"quiet_enabled":true}) == OK and service._quiet(23) and not service._quiet(12), "re-enabling quiet hours restores saved overnight range")
	verify(not service._valid_model("bad\r\nmodel") and not service._valid_model(" "), "invalid model identifiers rejected")
	var huge_history: Array = []
	for i in 80: huge_history.append({"role": "assistant", "text": "猫".repeat(1000), "at": i})
	verify(service._clean_history(huge_history).size() == 24, "local history has total character limit")
	verify(service._clean_memories(["a", "a", 123, " "]).size() == 1, "memory load rejects duplicate/invalid values")
	var root_before: String = service._store.root_path
	var blocked_path := path.path_join("blocked-storage")
	var blocker := FileAccess.open(blocked_path, FileAccess.WRITE)
	blocker.store_string("isolated file intentionally blocks directory creation")
	blocker.close()
	service._store.root_path = blocked_path
	verify(service.apply_settings({"model": "unsaved-model"}) != OK and service.settings.model == "custom-gpt-model", "settings rollback when local disk replacement fails")
	verify(not service.add_memory("不应保留") and service.memories.is_empty(), "memory creation rollback on disk failure")
	service.history = [{"role": "user", "text": "keep", "state": "complete", "at": 0}]
	service.clear_history()
	verify(service.history.size() == 1, "history deletion rollback on disk failure")
	service._store.root_path = root_before
	var recovery = Store.new()
	recovery.setup(path.path_join("recovery"))
	verify(recovery.save_data({"history": ["first"]}) == OK and recovery.save_data({"history": ["second"]}) == OK, "atomic replacement succeeds")
	verify(not FileAccess.file_exists(recovery.root_path.path_join("companion.json.bak")), "successful replacement removes old deleted data backup")
	var primary: String = recovery.root_path.path_join("companion.json")
	DirAccess.rename_absolute(primary, primary + ".bak")
	verify(recovery.load_data().history == ["second"], "interrupted atomic replacement can recover backup")
	DirAccess.make_dir_absolute(primary)
	verify(recovery.save_data({"history": ["cannot-commit"]}) != OK and FileAccess.file_exists(primary + ".bak"), "failed recovery commit retains its only durable backup")
	verify(recovery.load_data().history == ["second"], "original recovered history remains readable after commit failure")
	DirAccess.remove_absolute(primary)
	verify(recovery.save_data({"history": ["recovered"]}) == OK and recovery.load_data().history == ["recovered"], "recovered state replaces only its own files")
	var oversize := FileAccess.open(primary, FileAccess.WRITE)
	oversize.store_string("x".repeat(Store.MAX_BYTES + 1))
	oversize.close()
	verify(recovery.load_data().is_empty() and recovery.last_error == ERR_OUT_OF_MEMORY, "oversized input rejected before reading body")
	_verify_persona_upgrade(path.path_join("persona-upgrade"))
	service.free()
	print(JSON.stringify({"checks": checks, "failures": failures, "offline": true}))
	quit(0 if failures.is_empty() else 1)

func _verify_persona_upgrade(path: String) -> void:
	var storage = Store.new()
	storage.setup(path)
	var previous := {"settings": {"personality": Companion.LEGACY_DEFAULT_PERSONALITY},
		"history": [{"role": "assistant", "text": "已有对话", "state": "complete", "at": 1}],
		"memories": ["请称呼用户为小铃"]}
	verify(storage.save_data(previous) == OK, "legacy persona fixture saves in isolated storage")
	var migrated = Companion.new()
	var transport := FakeTransport.new()
	migrated.configure_dependencies(transport, FakeKeys.new())
	root.add_child(migrated)
	migrated.setup(null, path, false)
	verify(migrated.settings.personality == Companion.DEFAULT_PERSONALITY, "existing shipped default upgrades on load")
	verify(migrated.history == previous.history and migrated.memories == previous.memories and transport.calls.is_empty(), "upgrade preserves existing history and memories without a network request")
	verify(migrated._instructions().contains("请称呼用户为小铃") and migrated._instructions().contains("优先于默认称呼"), "explicit saved nickname is available with precedence over default address")
	var personal_style := "称呼我为小铃，少说一点，别加喵。"
	verify(migrated.apply_settings({"personality": personal_style}) == OK, "custom address and speaking style save normally")
	verify(storage.load_data().settings.personality == personal_style, "upgrade never replaces user-written style on later saves")
	verify(migrated.apply_settings({"personality": "", "memory_enabled": false}) == OK, "an intentionally empty custom style remains allowed")
	verify(migrated.settings.personality.is_empty() and not migrated._instructions().contains("请称呼用户为小铃") and migrated._instructions().contains("名字是東菱可"), "memory opt-out removes nickname data while retaining fixed identity and empty style")
	migrated.free()
