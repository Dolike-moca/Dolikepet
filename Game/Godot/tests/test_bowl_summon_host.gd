extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
var area: Rect2
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("SUMMON HOST: "+message)
func tick(count: int, physics := false) -> void:
	for i in count:
		app._process(1.0/60)
		if physics and app.bowl_window.visible:
			if app.bowl_window.arrival.active(): app.bowl_window._advance_arrival(1.0/60)
			else: app.bowl_window._advance_fall(1.0/60,area)
		await process_frame
func run() -> void:
	var path := "res://../../_work/tests/summon-settings.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420); cfg.set_value("pet","auto_fall_enabled",false)
	cfg.set_value("pet","auto_sit_enabled",false); cfg.set_value("pet","roaming_mode","off"); cfg.save(path)
	app = Scene.instantiate(); app.settings_path = path; root.add_child(app)
	app.set_process(false); app.set_process_input(false); root.mouse_passthrough = true
	app.bowl_window.set_process(false); app.bowl_files.set_process(false)
	check(app.pet.available,"model unavailable")
	if not app.pet.available: quit(1); return
	area = Rect2(DisplayServer.screen_get_usable_rect(root.current_screen))
	root.position = Vector2i(area.position+Vector2(200,area.size.y-420))
	await tick(3)
	app._set_bowl_visible(true); await tick(40,true)
	check(app.bowl_summon.state=="calling" and app.bowl_window.arrival.active(),"opening did not summon")
	check(app.bubble_label.text=="出来吧，我的锅锅","summon words overwritten")
	check(app.pet.bowl_reach.summoning and not app.pet.bowl_reach.eyes[0].visible,"muttering used shouting eyes")
	check(app.pet.bowl_reach.chant_face==1.0 and not app.pet.bowl_reach.shout.visible,"chant did not use closed smiling speech face")
	check(app.pet.params[app.pet.mapping.eyeNear].get("value")==0.0 and app.pet.params[app.pet.mapping.eyeFar].get("value")==0.0,"rendered chant eyes stayed open")
	check(app.pet.pickup_pose.hold_rig.far.z_index==app.pet.meshes.ArtMesh26.z_index,"far arm moved in front of face")
	var locked_x: float = app.bowl_window.at.x
	var age: float = app.bowl_window.arrival.age
	app._set_bowl_visible(true)
	check(app.bowl_window.arrival.age==age,"visible pot was summoned twice")
	# An actual drag start owns a rescue ticket. Shift beyond the entire pot,
	# then finish the real drag controller before the deferred thank-you.
	app.drag_pointer = root.position+Vector2i(210,80); app._begin_grab()
	check(app.bowl_summon.user_dragged,"real grab did not register")
	app.falling.cancel(); app.drag_motion.cancel(); root.position.x += 350
	await tick(180,true)
	check(absf(app.bowl_window.at.x-locked_x)<0.01,"pot retargeted moving cat")
	check(app.bubble_label.text=="谢谢喵","safe rescue did not thank")
	check(app.bowl_summon.state=="thanking","reward failed to settle")
	app._set_bowl_visible(false)
	check(not app.bowl_summon.active() and not app.bowl_window.arrival.active(),"hide stranded summon")
	app._set_bowl_visible(true); await tick(40,true)
	app._begin_grab(false)
	check(not app.bowl_summon.user_dragged,"menu pin counted as rescue")
	app.falling.cancel(); app.drag_motion.cancel()
	app.bowl_window.cancel_arrival(); app.bowl_window.intercepted.emit()
	check(not app.bowl_summon.active(),"grabbing pot did not cancel gesture")
	app._set_bowl_visible(false)
	app._set_bowl_visible(true); await tick(40,true)
	app._on_bowl_hit({"kind":"hard","dizzy_seconds":3.0})
	check(app.bowl_summon.state=="recover","hit did not end summoning")
	await tick(1)
	check(app.landing.immediate_dizzy and app.landing.pose().dizzyAlpha==1.0,"summon impact delayed dizziness")
	check(app.pet.landing_pose.sprites[0].visible and app.pet.landing_pose.sprites[0].modulate.a==1.0,"first contact frame did not render dizzy eye")
	check(not app.pet.bowl_reach.shout.visible and app.pet.bowl_reach.chant_face==0.0,"chant lingered after impact")
	app._set_bowl_visible(false)
	# Queue while an incompatible physical action is active, cancel safely.
	app.dragging = true; app._set_bowl_visible(true); await tick(1)
	app._set_bowl_visible(false); app.dragging = false
	check(not app.bowl_summon.active(),"queued opening could not be cancelled")
	print("SUMMON HOST: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
