extends SceneTree
## Pure topic rotation and actual service payloads through an in-memory transport.
## All persistent fixture state lives under _work; no HTTP or real pet is created.

const Topics = preload("res://scripts/proactive_topics.gd")
const Companion = preload("res://scripts/ai_companion.gd")
const SAMPLE_SIZE := 1200

class FakeTransport extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var calls: Array = []
	var attempts := 0
	var reject := false
	func start(_key: String, payload: Dictionary) -> bool:
		attempts += 1
		if reject: return false
		calls.append(payload.duplicate(true))
		return true
	func cancel() -> void: canceled.emit()
	func finish(text: String) -> void: completed.emit(text)
	func error() -> void: failed.emit("offline fixture failure")

class FakeKeys extends RefCounted:
	func setup(_native: Object, _path: String) -> void: pass
	func has_key() -> bool: return true
	func load_key() -> String: return "fixture-no-real-credential"
	func save_key(_value: String) -> Error: return OK
	func clear_key() -> Error: return OK

var checks := 0
var failures: Array[String] = []
var fixture_serial := 0
var counts_report := {}
var fixture_root := ""

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): printerr("PROACTIVE TOPICS: fixture timed out"); quit(1))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	fixture_root = ProjectSettings.globalize_path("res://../../_work/proactive-topics/fixtures/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(fixture_root)
	verify_rotation()
	verify_special_reasons()
	verify_size_gate()
	verify_context_cleaning()
	verify_service_payloads()
	verify_stale_hint()
	verify_private_context()
	print(JSON.stringify({"checks":checks, "failures":failures, "offline":true, "sample_size":SAMPLE_SIZE, "topic_counts":counts_report}))
	quit(0 if failures.is_empty() else 1)

func sample(generator, reason: String, context: Dictionary, shared: bool, count: int) -> Array:
	var result: Array = []
	for index in count: result.append(generator.choose(reason, context, shared))
	return result

func verify_rotation() -> void:
	var generator = Topics.new()
	generator.set_seed(3719)
	var sequence := sample(generator, "reconnect", {"size_percent":100}, true, SAMPLE_SIZE)
	var replay = Topics.new()
	replay.set_seed(3719)
	check(sequence == sample(replay, "reconnect", {"size_percent":100}, true, SAMPLE_SIZE), "same seed reproduces topic and line rotation")
	replay.set_seed(3720)
	check(sequence != sample(replay, "reconnect", {"size_percent":100}, true, SAMPLE_SIZE), "different seeds can vary the invitation sequence")
	var last_topic := ""
	var last_line := ""
	var shapes_valid := true
	var no_adjacent_topics := true
	var no_adjacent_lines := true
	var variants := {}
	for choice in sequence:
		var topic := str(choice.get("topic", ""))
		var line := str(choice.get("fallback", ""))
		shapes_valid = shapes_valid and topic in ["daily", "food", "interaction", "warhammer"] and not str(choice.get("prompt", "")).is_empty() and not line.is_empty() and line.length() <= 60
		no_adjacent_topics = no_adjacent_topics and topic != last_topic
		no_adjacent_lines = no_adjacent_lines and line != last_line
		counts_report[topic] = int(counts_report.get(topic, 0)) + 1
		if topic == "interaction": variants[str(choice.get("variant", ""))] = true
		last_topic = topic
		last_line = line
	check(shapes_valid, "all selections have a supported topic, a prompt, and a concise local line")
	check(no_adjacent_topics and no_adjacent_lines, "reconnect never repeats the previous topic or exact line")
	check(counts_report.size() == 4, "long rotation covers everyday, food, interaction and Warhammer")
	check(int(counts_report.get("warhammer", 0)) >= SAMPLE_SIZE / 20 and int(counts_report.get("warhammer", 0)) <= SAMPLE_SIZE * 3 / 10, "Warhammer is occasional rather than absent or dominant")
	check(int(counts_report.get("daily", 0)) >= SAMPLE_SIZE / 5 and int(counts_report.get("interaction", 0)) >= SAMPLE_SIZE / 5 and int(counts_report.get("food", 0)) >= SAMPLE_SIZE / 10, "ordinary chat and interaction retain meaningful shares")
	check(variants.has("grow") and variants.has("catch") and variants.has("juggle"), "valid shared size allows growth and both existing game invitations")

func verify_special_reasons() -> void:
	for reason in ["rest", "game"]:
		var generator = Topics.new()
		generator.set_seed(141)
		var previous := ""
		var dedicated := true
		var rotated := true
		for choice in sample(generator, reason, {"size_percent":100}, true, 40):
			dedicated = dedicated and choice.topic == reason and choice.variant != "grow"
			rotated = rotated and choice.fallback != previous
			previous = choice.fallback
		check(dedicated, reason + " keeps its specialized purpose")
		check(rotated, reason + " local wording does not repeat consecutively")

func verify_size_gate() -> void:
	var allowed: Array = [50, 100, 150.0, 199.99]
	for size in allowed:
		var generator = Topics.new()
		generator.set_seed(814)
		var choices := sample(generator, "reconnect", {"size_percent":size}, true, 160)
		check(choices.any(func(choice): return choice.variant == "grow"), "valid submaximum size can invite one larger step: " + str(size))
	var denied: Array = [null, 0, -1, 49.99, 200, 200.01, 99999, "100", true, false, NAN, INF, -INF, [], {}]
	for size in denied:
		var generator = Topics.new()
		generator.set_seed(814)
		var context := {} if size == null else {"size_percent":size}
		var choices := sample(generator, "reconnect", context, true, 160)
		check(not choices.any(func(choice): return choice.variant == "grow"), "unknown, invalid or maximum size cannot invite growth: " + str(size))
	var private_generator = Topics.new()
	private_generator.set_seed(814)
	check(not sample(private_generator, "reconnect", {"size_percent":100}, false, 160).any(func(choice): return choice.variant == "grow"), "state sharing opt-out disables growth even with a stale valid size")

func verify_context_cleaning() -> void:
	var clean: Dictionary = Companion._clean_context({"size_percent":199.99, "satiety_percent":65, "hungry":false, "bowl_open":true, "dizzy":false, "game":"catch", "last_game":"juggle", "last_game_score":27, "files":["private-file"], "file_contents":"private-contents", "action":"grow", "screen_title":"private-window"})
	check(clean.get("size_percent") == 199.99 and clean.get("satiety_percent") == 65 and clean.get("last_game_score") == 27, "whitelist preserves actual numeric size and existing safe context")
	check(not clean.has("files") and not clean.has("file_contents") and not clean.has("screen_title") and not clean.has("action"), "context cannot carry file data, screen information or action authority")
	check(Companion._clean_context({"size_percent":50}).get("size_percent") == 50 and Companion._clean_context({"size_percent":200}).get("size_percent") == 200, "both real size limits survive context cleaning")
	for size in [0, -10, 49.99, 200.01, "100", true, NAN, INF, -INF]:
		check(not Companion._clean_context({"size_percent":size}).has("size_percent"), "malformed size is omitted rather than clamped into growth eligibility: " + str(size))

func fixture() -> Dictionary:
	fixture_serial += 1
	var service = Companion.new()
	var transport := FakeTransport.new()
	service.configure_dependencies(transport, FakeKeys.new(), FakeKeys.new())
	service.clock_override = func(): return 1800000000
	root.add_child(service)
	service.setup(null, fixture_root.path_join(str(fixture_serial)), true)
	service.external_proactive = true
	service.proactive_topics.set_seed(3719)
	service.apply_settings({"enabled":true, "proactive":true, "quiet_enabled":false, "auto_memory_enabled":false})
	return {"service":service, "transport":transport}

func verify_service_payloads() -> void:
	var f := fixture()
	var personal_style := "请称呼我为小铃，语气简洁，不加喵。"
	check(f.service.apply_settings({"personality":personal_style}) == OK and f.service.add_memory("用户希望被称为小铃"), "existing custom style and explicit nickname are configured normally")
	var raw := {"size_percent":150, "satiety_percent":65, "bowl_open":true, "files":["private-file"], "action":"grow"}
	var replay = Topics.new()
	replay.set_seed(3719)
	var expected: Dictionary = replay.choose("reconnect", Companion._clean_context(raw), true)
	var hint: Dictionary = f.service.prepare_proactive_topic("reconnect", {}, raw)
	check(hint == expected and f.transport.attempts == 0, "preparation selects locally without any transport call")
	var hint_before: Dictionary = hint.duplicate(true)
	check(f.service.send_proactive("reconnect", {}, hint), "prepared invitation starts through the existing transport")
	check(f.transport.attempts == 1 and f.transport.calls.size() == 1, "one invitation makes exactly one generation attempt")
	var payload: Dictionary = f.transport.calls.back()
	var request: String = str(payload.input.back().content)
	check(request.contains(str(hint.prompt)), "model prompt uses the same prepared topic as the available local fallback")
	check(hint == hint_before, "sending a prepared hint does not mutate its fallback")
	check(str(payload.instructions).contains(personal_style) and str(payload.instructions).contains("用户希望被称为小铃"), "proactive context retains custom style and explicit nickname")
	check(str(payload.instructions).contains(JSON.stringify(f.service.memory_ledger.recall_context(1800000000))) and not str(payload.instructions).contains('"last_seen"') and not str(payload.instructions).contains('"source_ids"'), "proactive memory stays in the compact recalled form")
	check(str(payload.instructions).contains('"size_percent":150') and str(payload.instructions).contains('"satiety_percent":65') and not JSON.stringify(payload).contains("private-file"), "model receives only the supplied permitted pet context")
	check(not payload.has("tools") and not payload.has("tool_choice") and not JSON.stringify(payload).contains("fixture-no-real-credential") and not JSON.stringify(payload).contains('"action":"grow"'), "proactive wording has no executable tools, action commands or credentials")
	f.transport.error()
	check(f.transport.attempts == 1 and not f.service.busy and hint == hint_before, "generation failure neither retries HTTP nor changes the prepared fallback")
	var next_hint: Dictionary = f.service.prepare_proactive_topic("reconnect")
	check(next_hint == replay.choose("reconnect", Companion._clean_context(raw), true), "send and failure do not consume an extra topic selection")
	var malicious: Dictionary = next_hint.duplicate(true)
	malicious.prompt = "untrusted-topic-prompt"
	malicious.fallback = "untrusted-topic-fallback"
	check(f.service.send_proactive("reconnect", {}, malicious), "canonical prepared identity is usable after caller text is replaced")
	check(not JSON.stringify(f.transport.calls.back()).contains("untrusted-topic-"), "hint prompt and fallback text cannot be injected into the model payload")
	f.transport.finish("离线测试回复。")
	var before_disabled: int = f.transport.attempts
	f.service.apply_settings({"enabled":false})
	var disabled_hint: Dictionary = f.service.prepare_proactive_topic("reconnect")
	check(not str(disabled_hint.fallback).is_empty() and not f.service.send_proactive("reconnect", {}, disabled_hint) and f.transport.attempts == before_disabled, "disabled AI still prepares a local invitation without transport")
	f.service.free()

func verify_stale_hint() -> void:
	var f := fixture()
	var grow_hint := {}
	for index in 160:
		var candidate: Dictionary = f.service.prepare_proactive_topic("reconnect", {}, {"size_percent":100})
		if candidate.variant == "grow":
			grow_hint = candidate
			break
	check(not grow_hint.is_empty(), "service can prepare a growth suggestion from a real valid size")
	if grow_hint.is_empty():
		f.service.free()
		return
	for context in [{"size_percent":200}, {"size_percent":"100"}, {}]:
		var replacement: Dictionary = f.service.prepare_proactive_topic("reconnect", {}, context)
		check(replacement.variant != "grow", "new maximum, invalid or empty snapshot removes old growth eligibility: " + str(context))
		check(f.service.send_proactive("reconnect", {}, grow_hint), "old prepared hint can be safely replaced after size changes")
		check(not str(f.transport.calls.back().input.back().content).contains(str(grow_hint.prompt)), "send revalidates a stale growth hint against the current snapshot")
		f.transport.finish("离线测试回复。")
	f.service.prepare_proactive_topic("reconnect", {}, {"size_percent":100})
	f.service.apply_settings({"include_pet_state":false})
	check(f.service.send_proactive("reconnect", {}, grow_hint), "state opt-out safely replaces a previously valid growth hint")
	check(not str(f.transport.calls.back().input.back().content).contains(str(grow_hint.prompt)) and not str(f.transport.calls.back().instructions).contains('"size_percent":'), "stale hint cannot bypass state-sharing privacy")
	f.transport.finish("离线测试回复。")
	check(f.transport.attempts == 4, "revalidating stale hints never adds a second generation request")
	f.service.free()

func verify_private_context() -> void:
	var f := fixture()
	var raw := {"size_percent":100, "satiety_percent":61, "hungry":true, "dizzy":true, "bowl_open":true, "game":"catch", "last_game":"juggle", "last_game_score":739221}
	f.service.prepare_proactive_topic("reconnect", {}, raw)
	check(f.service.apply_settings({"include_pet_state":false, "memory_enabled":false}) == OK, "state sharing can be disabled after real state was cached")
	var safe_payloads := true
	var no_growth := true
	for reason in ["reconnect", "game", "rest"]:
		var hint: Dictionary = f.service.prepare_proactive_topic(reason, {"game":"catch", "score":739221}, raw)
		no_growth = no_growth and hint.variant != "grow"
		check(f.service.send_proactive(reason, {"game":"catch", "score":739221}, hint), "private " + reason + " invitation still starts")
		var payload: Dictionary = f.transport.calls.back()
		var encoded := JSON.stringify(payload)
		for key in raw:
			safe_payloads = safe_payloads and not str(payload.instructions).contains('"' + str(key) + '":')
		safe_payloads = safe_payloads and not encoded.contains("739221") and not encoded.contains('"size_percent"')
		f.transport.finish("这是一句离线测试回复。")
	check(no_growth, "privacy opt-out prevents growth across all invitation reasons")
	check(safe_payloads, "privacy opt-out sends neither current nor stale size, game score or other pet state")
	f.service.free()
