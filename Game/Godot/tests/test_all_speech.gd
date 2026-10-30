extends SceneTree
## Real host + Cubism rig. Fake transport and isolated settings; no user food/input.
class Responder extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var busy := false
	func start(_key: String, _payload: Dictionary) -> bool:
		busy = true; return true
	func cancel() -> void:
		busy = false; canceled.emit()
class Keys extends RefCounted:
	func setup(_model: Object, _root: String) -> void: pass
	func has_key() -> bool: return true
	func load_key() -> String: return "fixture-only-no-real-key"
	func save_key(_key: String) -> Error: return OK
	func clear_key() -> Error: return OK
class PassiveBridge extends RefCounted:
	func show_companion_without_activation(_handle: int) -> bool: return true

const DT := 1.0 / 60.0
var app
var responder := Responder.new()
var failures: Array[String] = []
var checks := 0
var output := ""

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): printerr("ALL SPEECH: fixture timed out"); quit(1))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	call_deferred("run")

func step(overrides: Dictionary = {}, idle: bool = false) -> Dictionary:
	var pose: Dictionary = app.behavior.update(DT, Vector2.ZERO, Vector2.ZERO, 300.0, false).duplicate()
	pose.merge(overrides, true)
	app._update_ai_presentation(DT, pose, idle)
	app.pet.apply_pose(pose, DT)
	return app.pet.secondary_pose

func reset_speech() -> void:
	app.bubble.hide(); app._clear_ai_speech(); app.speech_mouth.clear()
	app.proactive_companion.card.reset_session()
	app.behavior.command("normal")
	for frame in 20: step()

func capture(name: String) -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	var fixture := ProjectSettings.globalize_path("res://../../_work/tests/all-speech/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(fixture)
	app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = fixture.path_join("pet.cfg")
	app.ai_service.configure_dependencies(responder, Keys.new())
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false); root.mouse_passthrough = true
	await process_frame
	verify(app.pet.available, "actual Cubism model loads")
	verify(not app.ai_service._network_allowed, "non-default fixture starts offline")
	app.bowl_enabled = false; app.bowl_window.hide(); app.bowl_summon.finish()
	app.roaming.configure("off"); app.idle_sitting.enabled = false
	app.behavior.automatic_blinks = false
	app.ai_service.apply_settings({"enabled":false,"proactive":false,"auto_memory_enabled":false})
	reset_speech()

	# The settings conflict hint is spoken while settings remain open, without
	# acquiring the behaviour timers that used to interfere with dragging.
	app.settings_window.show()
	verify(app._chat_blocked_by_settings(), "opening chat during settings is blocked")
	var talk_before: float = app.behavior.talk_until
	var reaction_before: float = app.behavior.reaction_until
	var maximum := 0.0
	var minimum := 1.0
	for frame in 60:
		var pose := step()
		maximum = maxf(maximum, float(pose.mouth))
		if frame > 15: minimum = minf(minimum, float(pose.mouth))
	verify(maximum > 0.25 and minimum < maximum - 0.18, "settings hint opens and closes the visible native mouth")
	verify(app.settings_window.visible and app.bubble_label.text.contains("现在不行"), "hint leaves settings and its message in place")
	verify(app.behavior.talk_until == talk_before and app.behavior.reaction_until == reaction_before, "local speech takes no behaviour lock")
	app.settings_window.hide()
	await capture("settings-hint-speaking")
	reset_speech()

	# A happy expression starts with mouth=1; a max(base, speech) blend would
	# leave it stuck open. Eyes must remain the accepted closed smiling eyes.
	app.behavior.command("closedHappy")
	app._say("吃饱了，谢谢大人喵！", 4.0)
	minimum = 1.0; maximum = 0.0
	var eyes_closed := true
	for frame in 45:
		var pose := step()
		if frame >= 20:
			minimum = minf(minimum, float(pose.mouth)); maximum = maxf(maximum, float(pose.mouth))
			eyes_closed = eyes_closed and pose.eyeNear < 0.01 and pose.eyeFar < 0.01
	verify(eyes_closed, "speech retains closed smiling eyes")
	verify(minimum < 0.15 and maximum > 0.35, "closed smile has syllabic jaw movement instead of a fixed open smile")
	await capture("closed-smile-speaking")
	var previous_weight: float = app.speech_mouth.weight
	app.bubble.hide(); step()
	verify(app.speech_mouth.weight > 0.0 and app.speech_mouth.weight < previous_weight, "hidden text fades out instead of snapping its mouth layer")
	for frame in 40: step()
	verify(app.speech_mouth.weight == 0.0 and app.pet.secondary_pose.mouth > 0.99, "after speech the original happy mouth returns exactly")
	reset_speech()

	# Mouth overlays must yield, while the eyes and body of each physical state
	# keep their own animation. Speak after grab, as a notification can arrive then.
	var special_cases := [
		{"name":"drag", "pose":{"dragHeld":true,"dragFace":1.0,"dragHang":1.0}},
		{"name":"dizzy", "pose":{"dizzyActive":true,"dizzyAlpha":1.0,"dizzyAngle":0.4,"landingInfluence":1.0}},
		{"name":"fall", "pose":{"fallActive":true,"fallSpeed":1.0}},
	]
	for item in special_cases:
		reset_speech()
		app._say("猫猫在这里喵，陪大人说句话。", 4.0)
		maximum = 0.0; minimum = 1.0
		for frame in 45:
			var pose := step(item.pose)
			if frame > 15:
				maximum = maxf(maximum, float(pose.mouth)); minimum = minf(minimum, float(pose.mouth))
		verify(maximum > 0.25 and minimum < maximum - 0.18, item.name + " speaks through its expression override")
		verify(app.pet.meshes.ArtMesh3.self_modulate.a > 0.99 and app.pet.meshes.ArtMesh4.self_modulate.a > 0.99, item.name + " exposes native speaking mouth without double drawing")
		if item.name == "drag":
			verify(app.pet.drag_pose.sprites[0].modulate.a > 0.99 and app.pet.drag_pose.sprites[1].modulate.a > 0.99, "drag eye sprites remain visible while speaking")
			verify(app.pet.drag_pose.sprites[2].modulate.a < 0.01, "drag static mouth yields only while speaking")
		elif item.name == "dizzy":
			verify(app.pet.landing_pose.sprites[0].modulate.a > 0.99 and app.pet.landing_pose.sprites[1].modulate.a > 0.99, "dizzy eye sprites remain visible while speaking")
			verify(app.pet.landing_pose.sprites[2].modulate.a < 0.01, "dizzy static mouth yields only while speaking")
		else:
			verify(app.pet.falling_pose.sprite.modulate.a < 0.01, "falling static mouth yields while speaking")
		await capture(item.name + "-speaking")
		app.bubble.hide()
		for frame in 40: step(item.pose)
		verify(app.pet.meshes.ArtMesh3.self_modulate.a < 0.01, item.name + " restores original mouth visibility after speech")
	reset_speech()

	# The host's actual release path must remain available despite repeated text.
	app.dragging = true; app.drag_moved = true
	app.drag_pointer = root.position + Vector2i(150,150); app._begin_grab()
	verify(app.falling.body.held, "real host can acquire a grab")
	for index in 4:
		app._say("喵～", 1.8); step({"dragHeld":true,"dragFace":1.0})
	app._update_drag_pointer(app.drag_pointer + Vector2i(40,-25), false)
	verify(not app.dragging and not app.falling.body.held, "release is immediate even after repeated spoken notifications")
	reset_speech()

	# A visible full conversation can continue speaking during busy expressions;
	# this must not create another action or replace the closed eyes.
	app.ai_service._network_allowed = true # Only the fake responder above.
	verify(app.ai_service.apply_settings({"enabled":true}) == OK, "fake AI is enabled")
	app.ai_chat.open_panel(); app.behavior.command("closedHappy")
	verify(app.ai_service.send_message("陪猫猫说句话"), "fake full-window reply starts")
	responder.delta.emit("猫猫陪大人一起玩，今天也要开开心心喵。")
	maximum = 0.0; minimum = 1.0
	for frame in 60:
		var pose := step({}, false)
		if frame > 20:
			maximum = maxf(maximum, float(pose.mouth)); minimum = minf(minimum, float(pose.mouth))
	verify(maximum > 0.2 and minimum < maximum - 0.15, "visible AI reply animates its jaw even while host is busy")
	verify(app.pet.secondary_pose.eyeNear < 0.01 and app.pet.secondary_pose.eyeFar < 0.01, "AI speech does not reopen the user's closed expression")
	app.settings_window.show()
	for frame in 18: step({}, false)
	verify(app.speech_mouth.weight > 0.9 and not app.ai_speech.current.is_empty(), "visible full reply continues its mouth while settings are open")
	app.settings_window.hide(); app.ai_chat.hide(); app.ai_service.cancel()
	reset_speech()

	# Closing the compact conversation must silence remaining streaming chunks,
	# while normal visible compact replies use the same jaw driver.
	app.proactive_companion.environment_enabled = true
	app.proactive_companion.activity_override = func(): return {"idle_seconds":0.0,"locked":false,"fullscreen":false}
	app.proactive_companion.native_bridge = PassiveBridge.new()
	app.proactive_companion.card.native_bridge = app.proactive_companion.native_bridge
	app._menu_action(25)
	var card = app.proactive_companion.card
	card.input.text = "猫猫说一句话"; card._send_message()
	responder.delta.emit("猫猫一直陪大人说说话喵。")
	for frame in 35: step({}, true)
	verify(card.visible and app.ai_compact_speech and app.speech_mouth.weight > 0.9, "visible compact response shares the spoken mouth layer")
	verify(not app.bubble.visible, "compact response does not duplicate its text in a head bubble")
	var remaining: float = app.ai_speech.remaining
	for frame in 40: step({}, false)
	verify(not card.visible and app.speech_mouth.weight == 0.0, "suspended compact text fades its mouth without speaking offscreen")
	verify(is_equal_approx(app.ai_speech.remaining, remaining), "temporarily hidden compact sentence pauses instead of losing words")
	for frame in 20: step({}, true)
	verify(card.visible and app.speech_mouth.weight > 0.9 and app.ai_speech.remaining < remaining, "returning compact text resumes its unfinished mouth animation")
	card._dismiss_user(); responder.delta.emit("这段已经关闭的文字不应再播放。")
	for frame in 40: step({}, true)
	verify(app.speech_mouth.weight == 0.0 and app.ai_speech.current.is_empty(), "closed compact reply fades out and late chunks stay silent")
	app.ai_service.cancel(); app.ai_service.shutdown()
	app.queue_free(); await process_frame
	for failure in failures: printerr("ALL SPEECH: " + failure)
	print("All speech: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
