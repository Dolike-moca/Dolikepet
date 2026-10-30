extends SceneTree
## Local presentation timing and save semantics; no external network or user data.
const Speed = preload("res://scripts/speech_speed.gd")
const Speech = preload("res://scripts/ai_speech.gd")
const Mouth = preload("res://scripts/speech_mouth.gd")
const Reveal = preload("res://scripts/text_reveal.gd")
const Companion = preload("res://scripts/ai_companion.gd")
class Transport extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var starts := 0
	var cancels := 0
	func start(_key: String, _payload: Dictionary) -> bool: starts += 1; return true
	func cancel() -> void: cancels += 1; canceled.emit()
class Keys extends RefCounted:
	func setup(_native: Object, _path: String) -> void: pass
	func has_key() -> bool: return true
	func load_key() -> String: return "fixture-speed-only"
	func save_key(_value: String) -> Error: return OK
	func clear_key() -> Error: return OK
class FaultStore extends "res://scripts/ai_store.gd":
	var deny_save := false
	func save_data(value: Dictionary) -> Error:
		return ERR_CANT_CREATE if deny_save else super.save_data(value)
var checks := 0
var failures: Array[String] = []
var now := 1800000000
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("SPEECH SPEED: " + message)
func reading_duration(factor: float) -> float:
	var speech := Speech.new(); speech.append("这是速度回归测试。猫猫陪着你喵。"); speech.finish()
	var duration := 0.0
	while duration < 20.0:
		speech.advance(1.0/60.0, true, factor); duration += 1.0/60.0
		if speech.current.is_empty() and speech.queue.is_empty(): break
	return duration
func run() -> void:
	check(Speed.DEFAULT == 2 and Speed.factor(2) == 1.0 and Speed.label_at(2) == "正常", "normal default retains animation timing")
	var prior := 0.0
	for index in 5:
		var factor := Speed.factor(index)
		check(factor > prior and is_equal_approx(Speed.chars_per_second(index), 18.0 * factor), "text and mouth use same ordered factor %d" % index)
		prior = factor
		var speech := Speech.new(); speech.append("这是同一句速度回归测试。猫猫陪着你喵。"); speech.finish()
		var local := Mouth.new(); local.say("这是同一句速度回归测试。猫猫陪着你喵。", 5.0)
		var reveal := Reveal.new(); reveal.replace("这是同一句速度回归测试。猫猫陪着你喵。")
		for frame in 30:
			speech.advance(1.0/60.0, true, factor)
			local.advance(1.0/60.0, true, false, 0.0, {}, factor)
			reveal.advance(1.0/60.0, Speed.chars_per_second(index))
		check(is_equal_approx(speech.elapsed, 0.5 * factor) and is_equal_approx(local.elapsed, 0.5 * factor), "AI and local jaw phases share factor %d" % index)
		check(absi(reveal.visible_text().length() - int(9.0 * factor)) <= 1, "text advances at selected character rate %d" % index)
		var before: float = speech.remaining
		speech.advance(0.25, false, factor)
		check(is_equal_approx(before, speech.remaining), "hidden speech pauses independent of speed %d" % index)
		for frame in 121: speech.advance(0.25, false, factor)
		check(speech.current.is_empty() and speech.queue.is_empty(), "abandoned speech expires after real 30 seconds %d" % index)
	var slow := reading_duration(Speed.factor(0))
	var normal := reading_duration(Speed.factor(2))
	var fast := reading_duration(Speed.factor(4))
	check(slow > normal and normal > fast and absf(slow * 0.6 - fast * 1.6) < 0.12, "whole reply duration scales inversely across all segments")
	check(Speed.safe_factor(NAN) == 1.0 and Speed.safe_factor(INF) == 1.0, "invalid factor returns normal")
	check(Companion._clean_settings({}).speech_speed == 2 and Companion._clean_settings({"speech_speed":NAN}).speech_speed == 2, "legacy and invalid speed migrate to normal")
	check(Companion._clean_settings({"speech_speed":-10}).speech_speed == 0 and Companion._clean_settings({"speech_speed":10}).speech_speed == 4, "saved speed bounded to five indices")
	var service := Companion.new(); var transport := Transport.new()
	service.configure_dependencies(transport, Keys.new())
	service._store = FaultStore.new()
	service.clock_override = func(): return now
	service.day_override = "2026-11-02"
	root.add_child(service)
	var folder := ProjectSettings.globalize_path("res://../../_work/tests/speech-speed/%d" % OS.get_process_id())
	service.setup(null, folder, true)
	check(service.apply_settings({"enabled":true}) == OK and service.send_message("我喜欢薯条"), "fixture starts one active chat")
	var serial: int = service._request_serial
	var activity: int = service._last_activity
	var signals := {"canceled":0, "failed":0}
	service.request_canceled.connect(func(): signals.canceled += 1)
	service.failed.connect(func(_text): signals.failed += 1)
	check(service.apply_settings({"speech_speed":4}) == OK, "speed saves during reply")
	check(service.busy and service._request_serial == serial and transport.starts == 1 and transport.cancels == 0 and signals.canceled == 0, "speed save never cancels or reissues paid request")
	check(service._last_activity == activity and service.history.size() == 1 and service.history[0].state == "pending", "presentation save preserves pending user turn and scheduling")
	service._store.deny_save = true
	check(service.apply_settings({"speech_speed":0}) != OK and service.settings.speech_speed == 4, "failed speed save retains previous setting")
	check(service.busy and signals.failed == 0 and signals.canceled == 0 and transport.starts == 1, "save error does not silence or restart live reply")
	service._store.deny_save = false
	transport.completed.emit("收到喵。")
	now += 121; service._memory_tick(true)
	check(service.request_kind == "memory" and service._busy, "fixture starts background memory")
	var memory_batch: Array = service._memory_batch.duplicate(true)
	serial = service._request_serial
	var starts: int = transport.starts
	check(service.apply_settings({"speech_speed":1}) == OK and service._busy and service.request_kind == "memory", "speed saves during background memory")
	check(service._request_serial == serial and transport.starts == starts and service._memory_batch == memory_batch, "memory batch and request remain unchanged")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("companion.json")))
	check(saved.settings.speech_speed == 1, "speed persists to local settings")
	service.shutdown(); service.free()
	print("Speech speed: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
