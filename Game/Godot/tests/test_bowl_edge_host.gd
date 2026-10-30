extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<12: printerr("BOWL EDGE HOST: "+message)
func tick() -> void:
	app._process(1.0/60)
	await process_frame
func run() -> void:
	var path := "res://../../_work/tests/screen-edge-report/host-settings.cfg"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())==OK,"isolated settings directory was not created")
	var cfg := ConfigFile.new()
	# The host migrates saved sizes to supported presets. Keep the edge geometry
	# proportional to the actual 150% window instead of the obsolete 420px size.
	cfg.set_value("window","size",450)
	cfg.set_value("pet","auto_fall_enabled",false)
	cfg.set_value("pet","auto_sit_enabled",false)
	cfg.set_value("pet","roaming_mode","off")
	check(cfg.save(path)==OK,"isolated settings could not be saved")
	if failures>0: quit(1); return
	app = Scene.instantiate(); app.settings_path = path
	root.add_child(app); app.set_process(false); app.set_process_input(false)
	check(root.size==Vector2i.ONE*450,"host did not load the fixture's supported size")
	root.mouse_passthrough = true
	app.bowl_window.set_process(false); app.bowl_window.mouse_passthrough = true
	app.bowl_files.set_process(false); app.bowl_files.initialized = true; app.bowl_files.storage_ready = true
	app.bowl_window.show()
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	var extent := root.size.y
	var scale_factor := float(extent)/420.0
	var margin := roundi(59.0*scale_factor)
	for side in [-1,1]:
		app.bowl_jump.cancel(); app.bowl_jump.cooldown = 0.0
		app.roaming.interrupt(); app.roaming.weight = 0.0
		app.pet.sitting.amount = 0.0; app.pet.sitting.seated = false
		app.pet.sitting.velocity = 0.0
		var x := area.position.x-margin if side<0 else area.end.x-extent+margin
		root.position = Vector2i(x,area.end.y-extent)
		var origin := root.position
		app.bowl_window.place(origin+Vector2i((Vector2(70,25)*scale_factor).round())); app.bowl_window.dragging = true
		var raised := false; var airborne := false
		for frame in (540 if side<0 else 210):
			if frame==(390 if side<0 else 65): app.bowl_window.dragging = false
			await tick()
			check(root.position.x==origin.x,"host changed edge standing x")
			raised = raised or app.bowl_jump.active()
			airborne = airborne or root.position.y<origin.y-2
		check(raised and airborne,"edge bowl did not trigger real hop")
		check(not app.bowl_jump.active() and root.position==origin,"edge recovery did not return to exact origin")
		# B3 waits for the bowl; lowering a distant bowl must not move the pet.
		app.bowl_window.place(Vector2i(origin.x-side*roundi(260.0*scale_factor),area.end.y-app.bowl_window.size.y))
		app.bowl_window.dragging = true
		var walked := false
		for frame in 150:
			var before := root.position
			await tick()
			check(abs(root.position.x-before.x)<=3,"host snapped when following bowl after hop")
			walked = walked or root.position.x!=before.x
		check(not walked,"B3 edge pet followed a distant bowl")
		app.bowl_window.dragging = false
	print("BOWL EDGE HOST: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

