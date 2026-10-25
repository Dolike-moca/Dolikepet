extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
class Buttons extends RefCounted:
	var down := true
	func desktop_primary_pressed() -> bool: return down
	func desktop_capture_matches(_handle: int) -> bool: return false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("DIZZY GRAB: "+message)
func button(down: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = at; e.global_position = at
	return e
func reset() -> void:
	app._finish_drag(true); app.falling.cancel(); app.drag_motion.cancel()
	app.landing.cancel(); app.bowl_hit.cancel(); app.bowl_summon.finish()
	app.juggle_game.finish("fixture"); app.pet.set_seated(false)
	app.behavior.command("normal"); app.bubble.hide()
func dizzy(seconds := 5.0) -> void:
	app.landing.start({"height":1.0,"speed":5.0,"dizzy_seconds":seconds,"immediate_dizzy":true})
	app.landing.update(0.1); app.pet.set_seated(true)
func run() -> void:
	var out := ProjectSettings.globalize_path("res://../../_work/tests/dizzy-grab")
	var probe_source := ProjectSettings.globalize_path("res://tests/PointerProbe.cs")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): out = arg.trim_prefix("--fixture=")
		if arg.begins_with("--probe-source="): probe_source = arg.trim_prefix("--probe-source=")
	DirAccess.make_dir_recursive_absolute(out)
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420); cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("pet","auto_fall_enabled",false); cfg.set_value("pet","auto_sit_enabled",false)
	cfg.set_value("bowl","visible",false); cfg.save(out+"/settings.cfg")
	app = Scene.instantiate(); app.settings_path = out+"/settings.cfg"; root.add_child(app)
	app.set_process(false); app.set_process_input(false); app.bowl_window.set_process(false)
	root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	app.drag_input.bridge = Buttons.new(); app.bubble.hide()
	app._process(1.0/60); await process_frame; await RenderingServer.frame_post_draw
	app._capture_hit_area()
	var point := Vector2(210,210)
	check(app._pointer_hits_pet(point),"fixture point is not inside the cat")
	# Input may deliver a complete quick gesture before the next rendered frame.
	for state in ["normal","greeting","dizzy","summon","feeding","satisfied"]:
		reset()
		if state=="dizzy": dizzy()
		elif state=="summon": app.bowl_summon.state = "calling"
		elif state=="feeding": app._start_pickup_demo()
		elif state=="satisfied": app.behavior.command("satisfied")
		if state!="normal": app._say("出来吧，我的锅锅" if state=="summon" else "喵～",2.0)
		app._input(button(true,point))
		var motion := InputEventMouseMotion.new()
		motion.position = point+Vector2(35,0); motion.relative = Vector2(35,0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		app._input(motion)
		check(app.drag_moved and app.falling.body.held,state+": motion before process did not begin drag")
		app._input(button(false,motion.position))
		check(not app.dragging and not app.falling.body.held,state+": release remained attached")
		check(not app.bubble.visible,state+": drag became a greeting")
	reset(); app._input(button(true,point)); app._input(button(false,point))
	check(app.bubble.visible and app.bubble_label.text=="喵～","ordinary unmoved tap lost greeting")
	reset(); dizzy(); var remaining: float = app.landing.dizzy_remaining()
	app.dragging = true; app.drag_moved = true; app.drag_pointer = root.position+Vector2i(point)
	app._begin_grab()
	check(is_equal_approx(app.landing.dizzy_remaining(),remaining),"pickup erased/restarted dizziness")
	for i in 20: app._process(1.0/60)
	check(app.landing.dizzy_remaining()<remaining and app.landing.dizzy_remaining()>remaining-0.5,"held stun clock stopped")
	check(not app.pet.sitting.seated,"held dizzy cat was forced into floor sitting")
	app._finish_drag(); app._process(1.0/60)
	check(app.landing.state=="hard","release/fall cleared dizziness")
	app._on_bowl_hit({"kind":"hard","dizzy_seconds":6.0})
	check(app.landing.dizzy_remaining()>remaining,"repeated hit did not extend carried dizziness")
	for i in 8: app._on_bowl_hit({"kind":"hard","dizzy_seconds":6.0})
	check(app.landing.dizzy_remaining()<=30.0,"carried dizziness exceeded 30 seconds")
	# Re-grabbing, landing and recovering all use the same clock.
	reset(); dizzy(3.0); app.dragging = true; app.drag_moved = true; app._begin_grab()
	for i in 40: app._process(1.0/60)
	check(app.dizzy_carry.motion.weight>0.99,"limp carry did not blend in")
	check(app.pet.landing_pose.sprites[0].visible,"held cat lost its spiral eyes")
	app._finish_drag(); app._process(1.0/60)
	var before_regrab: float = app.landing.dizzy_remaining()
	app.dragging = true; app.drag_moved = true; app._begin_grab()
	check(is_equal_approx(before_regrab,app.landing.dizzy_remaining()),"re-grab restarted the clock")
	for i in 190: app._process(1.0/60)
	check(app.landing.state=="idle" and app.dizzy_carry.motion.weight==0.0,"held recovery never completed")
	check(app.falling.body.held and not app.pet.landing_pose.sprites[0].visible,"recovery dropped the cat or kept spiral eyes")
	reset(); dizzy(); app.dragging = true; app.drag_moved = true; app._begin_grab()
	for i in 20: app._process(1.0/60)
	app._finish_drag(); app.falling.cancel(); app.drag_motion.cancel()
	app._process(1.0/60)
	check(app.pet.sitting.seated and app.landing.state=="hard","grounded cat did not resume seated dizziness")
	reset(); dizzy(6.0); app._on_juggled({"walls":0,"boosted":false})
	for i in 20: app._process(1.0/60)
	app.juggle_game.finish("fixture")
	for i in 40:
		app._process(1.0/60)
		check(app.pet.landing_pose.sprites[0].modulate.a>0.99,"juggle recovery erased remaining stun eyes")
	# Real Win32 dispatch, scoped to this fixture; no global mouse input.
	reset(); app.pet.sitting.amount = 0.0; app._process(1.0/60)
	await process_frame; await RenderingServer.frame_post_draw
	root.title = "Dolike drag release fixture dizzy"
	var probe := out.path_join("PointerProbe.exe")
	var output: Array = []
	var compiler := OS.get_environment("WINDIR").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	check(OS.execute(compiler,["/nologo","/out:"+probe.replace("/","\\"),probe_source.replace("/","\\")],output,true)==0,"native helper build failed")
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,root.get_window_id())
	for state in ["normal","greeting","dizzy","summon"]:
		reset()
		if state=="dizzy": dizzy()
		if state=="summon": app.bowl_summon.state = "calling"
		if state!="normal": app._say("喵～",2.0)
		app.set_process_input(true)
		output.clear()
		check(OS.execute(probe,["fixture-gesture",str(handle),str(OS.get_process_id())],output,true)==0,"native gesture dispatch failed")
		await process_frame; await process_frame
		app.set_process_input(false)
		check(not app.dragging and not app.falling.body.held,state+": native release stuck")
		check(not app.bubble.visible and app.falling.state=="falling",state+": native gesture became click/was swallowed")
	check(app.bowl_window.unfocusable,"summoned bowl may steal pet focus")
	# Pot receives quick motions through the same event path too.
	var pot = app.bowl_window
	pot._input_window(button(true,Vector2(30,30)))
	var motion := InputEventMouseMotion.new(); motion.position = Vector2(60,30)
	pot._input_window(motion)
	check(pot.dragging,"quick pot drag was ignored")
	pot._input_window(button(false,Vector2(60,30)))
	check(not pot.pressed and pot.drop_armed,"quick pot drop was not armed")
	reset(); app.queue_free(); await process_frame
	print("DIZZY GRAB: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
