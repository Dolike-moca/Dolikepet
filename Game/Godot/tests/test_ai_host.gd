extends SceneTree
## Real host/rig with an in-memory responder; no keys, API, user files or input injection.
class Responder extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var busy := false
	var payload := {}
	func start(_key: String, body: Dictionary) -> bool:
		payload = body; busy = true; return true
	func cancel() -> void:
		busy = false; canceled.emit()
class Keys extends RefCounted:
	var value := "fixture-only"
	func setup(_model: Object, _root: String) -> void: pass
	func has_key() -> bool: return not value.is_empty()
	func load_key() -> String: return value
	func save_key(key: String) -> Error: value = key; return OK
	func clear_key() -> Error: value = ""; return OK
var failures: Array[String] = []
var checks := 0
func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/pet.tscn").instantiate()
	var folder := ProjectSettings.globalize_path("res://../../_work/tests/ai-host/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	app.settings_path = folder.path_join("pet.cfg")
	var responder := Responder.new()
	app.ai_service.configure_dependencies(responder, Keys.new())
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false)
	root.mouse_passthrough = true
	await process_frame
	verify(app.pet.available, "actual pet loads")
	verify(not app.ai_service._network_allowed and not app.ai_service.settings.enabled, "fixture and default AI stay offline")
	app.ai_service._network_allowed = true # Fake transport only.
	verify(app.ai_service.apply_settings({"enabled":true}) == OK, "settings enable fake companion")
	app.bubble.hide(); app.bowl_enabled = false; app.bowl_window.hide()
	app.bowl_summon.finish(); app.roaming.configure("off"); app.idle_sitting.enabled = false
	app.behavior.command("normal")
	verify(app.ai_service.send_message("今天陪我玩一会儿"), "chat starts")
	responder.delta.emit("谢谢你，今天也很高兴见到你。")
	var talk_until: float = app.behavior.talk_until
	var reaction_until: float = app.behavior.reaction_until
	var pose := {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}
	app._update_ai_presentation(0.2, pose, true)
	verify(app.ai_bubble_owned and app.bubble_label.text.contains("谢谢"), "stream reaches head bubble")
	verify(app.behavior.talk_until == talk_until and app.behavior.reaction_until == reaction_until, "AI never acquires behaviour locks")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review="):
			var output := argument.trim_prefix("--review=")
			DirAccess.make_dir_recursive_absolute(output)
			var area := DisplayServer.screen_get_usable_rect(root.current_screen)
			root.position = Vector2i(area.get_center().x - 150, area.end.y - 300)
			app.falling.reposition(Vector2(root.position))
			for frame in 18:
				app._process(1.0 / 60.0)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("pet-speaking.png"))
	var blocked := {"mouth":0.35,"eyeNear":0.0,"eyeFar":0.0}
	var before := blocked.duplicate()
	app._update_ai_presentation(0.1, blocked, false)
	verify(blocked.mouth == before.mouth and blocked.eyeNear == before.eyeNear and blocked.eyeFar == before.eyeFar \
		and not app.bubble.visible, "hidden AI stops speaking and yields expression without a new bubble")
	app._say("吃饱了", 3.0)
	app._update_ai_presentation(0.1, pose, true)
	verify(app.bubble_label.text == "吃饱了" and not app.ai_bubble_owned, "built-in dialogue wins")
	app.bubble.hide()
	app._update_ai_presentation(0.1, pose, true)
	verify(app.ai_bubble_owned, "AI presentation can resume when idle")
	# Exercise the same release path as physical dragging without injecting mouse input.
	app.dragging = true; app.drag_moved = true
	app.drag_pointer = root.position + Vector2i(150,150)
	app._begin_grab()
	verify(app.falling.body.held, "pet can be picked up during a streaming reply")
	app._update_drag_pointer(app.drag_pointer + Vector2i(40,-25), false)
	verify(not app.dragging and not app.falling.body.held, "release remains immediate during streaming")
	app.ai_service.cancel()
	verify(not responder.busy and app.ai_speech.current.is_empty() and not app.ai_bubble_owned, "stop clears transport and presentation")
	app.ai_service.send_message("再聊一句")
	responder.delta.emit("新的回答。"); responder.completed.emit("新的回答。")
	app.ai_service.clear_history()
	verify(app.ai_speech.queue.is_empty() and app.ai_service.history.is_empty(), "clear dialogue clears pending bubbles too")
	app._menu_action(24)
	await process_frame
	verify(app.ai_chat.visible and not app.ai_chat.transient and not app.ai_chat.exclusive, "chat opens as a nonmodal independent window")
	app.ai_chat.settings_requested.emit()
	await process_frame
	verify(app.settings_window.visible and app.settings_window.current_page == 3, "chat opens AI settings directly")
	app.settings_window.hide(); app.ai_chat.hide()
	app.ai_memory.open_panel()
	verify(app.ai_memory.visible and not app.ai_memory.exclusive, "memory editor is nonmodal")
	app.ai_memory.hide()
	verify(app.ai_service.add_memory("喜欢轻松、简短的对话"), "explicit memory can be saved")
	verify(app.ai_service.send_message("你好", app._ai_context()), "chat can resume after UI navigation")
	verify(str(responder.payload.instructions).contains("喜欢轻松"), "confirmed memory reaches request")
	verify(not str(responder.payload).contains("fixture-only"), "key is outside request body")
	app.ai_service.shutdown()
	app.queue_free(); await process_frame
	for failure in failures: printerr("AI HOST: " + failure)
	print("AI host: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
