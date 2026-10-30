extends SceneTree
## Real host clocks and text clipping; isolated settings and synthetic transport.
class Responder extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	func start(_key: String, _payload: Dictionary) -> bool: return true
	func cancel() -> void: canceled.emit()
class Keys extends RefCounted:
	func setup(_model: Object, _root: String) -> void: pass
	func has_key() -> bool: return true
	func load_key() -> String: return "fixture-speed-host"
	func save_key(_key: String) -> Error: return OK
	func clear_key() -> Error: return OK
var checks := 0
var failures: Array[String] = []
var app
const DT := 1.0/60.0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("SPEECH SPEED HOST: " + label)
func reset() -> void:
	app.bubble.hide(); app._clear_ai_speech(); app.speech_mouth.clear()
func run() -> void:
	app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = ProjectSettings.globalize_path("res://../../_work/tests/speech-speed-host/%d/pet.cfg" % OS.get_process_id())
	app.ai_service.configure_dependencies(Responder.new(), Keys.new())
	root.add_child(app)
	app.set_process(false); app.set_process_input(false); app.bowl_window.set_process(false)
	app.bowl_enabled = false; app.bowl_window.hide(); app.bowl_summon.finish()
	app.roaming.configure("off"); app.idle_sitting.enabled = false; app.behavior.command("normal")
	await process_frame
	check(app.pet.available, "actual host and rig loaded")
	check(app.ai_service.apply_settings({"enabled":true,"speech_speed":0}) == OK, "save slow presentation speed")
	reset()
	var long_text := "大人今天也辛苦啦，猫猫想陪你慢慢聊；可以先喝口水，再歇一会儿喵。".repeat(3)
	app._say(long_text, 1.0)
	check(app.bubble_label.text == long_text and app.bubble_label.visible_characters == 0, "full text retained for stable wrap while initial display is empty")
	var slow_duration: float = app.bubble_until - Time.get_ticks_msec()/1000.0
	check(slow_duration > long_text.length()/10.8, "slow local bubble remains until every character can be shown")
	for frame in 60: app._advance_bubble_text(DT)
	var before_chars: int = app.bubble_label.visible_characters
	check(before_chars >= 10 and before_chars <= 11, "local slow mode reveals about eleven characters per second")
	var before_deadline: float = app.bubble_until
	check(app.ai_service.apply_settings({"speech_speed":4}) == OK, "change speaking speed mid-sentence")
	app._advance_bubble_text(DT)
	check(app.bubble_label.visible_characters >= before_chars and app.bubble_label.text == long_text, "speed change preserves visible prefix and complete wording")
	check(app.bubble_until < before_deadline and app.bubble_until > Time.get_ticks_msec()/1000.0, "speed change rescales remaining deadline without restarting")
	for frame in 240: app._advance_bubble_text(DT)
	check(app.bubble_label.visible_characters == long_text.length(), "long Chinese local text is fully revealed")
	reset()
	var utterance := "第一段有标点，猫猫陪着你慢慢读完这句话！第二段比较长，包含中文、English 123 和多个停顿；最后一段也要完整出现，不漏掉最后一个字喵。"
	for speed in [0, 2, 4]:
		check(app.ai_service.apply_settings({"speech_speed":speed}) == OK, "set AI speed %d" % speed)
		reset(); app.ai_speech.append(utterance); app.ai_speech.finish()
		var last_text := ""
		var last_visible := 0
		var segments := 0
		for frame in 1600:
			if speed == 2 and frame in [45, 110]:
				check(app.ai_service.apply_settings({"speech_speed":0 if frame==45 else 4}) == OK, "AI queued reply can change speed in progress")
			var pose := {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}
			app._update_ai_presentation(DT, pose, true)
			var next_text: String = app.bubble_label.text if app.bubble.visible else ""
			if next_text != last_text:
				if not last_text.is_empty():
					check(last_visible == last_text.length(), "AI segment complete before replacement at speed %d" % speed)
					segments += 1
				last_text = next_text
			app._advance_bubble_text(DT)
			last_visible = app.bubble_label.visible_characters
			if app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty(): break
		check(segments >= 3 and app.ai_speech.current.is_empty(), "all long-punctuation segments finish at speed %d" % speed)
	# A full chat is a continuous surface, not a sequence of head bubbles. Its
	# completed visible text owns the end of speech even for a 500-character
	# unpunctuated answer that would otherwise accumulate segment pauses.
	reset(); app.ai_service._network_allowed = true
	app.ai_service.apply_settings({"speech_speed":2})
	app.ai_chat.open_panel(); app.ai_chat.set_process(false)
	check(app.ai_service.send_message("长句显示回归"), "start long visible full-window reply")
	var long_reply := "猫猫在这里陪大人慢慢聊天".repeat(42)
	app.ai_service._transport.delta.emit(long_reply)
	app.ai_service._transport.completed.emit(long_reply)
	var visible_before_change := 0
	for frame in 2400:
		if frame == 120:
			visible_before_change = app.ai_chat._reveal.visible_text().length()
			check(app.ai_service.apply_settings({"speech_speed":4}) == OK, "change speed while completed reply is still revealing")
		app.ai_chat._process(DT)
		app._update_ai_presentation(DT, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
		if frame == 121:
			check(app.ai_chat._reveal.visible_text().length() >= visible_before_change, "full-window speed change retains shown prefix")
		if app.ai_chat.is_speech_complete(): break
	check(app.ai_chat._reveal.visible_text() == long_reply, "500-character answer reveals completely")
	for frame in 40: app._update_ai_presentation(DT, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	check(app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty() and app.speech_mouth.weight == 0.0, "mouth settles when continuous visible answer completes, with no accumulated tail")
	app.ai_chat.hide()
	reset(); app.ai_service.shutdown(); app.queue_free(); await process_frame
	print("Speech speed host: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
