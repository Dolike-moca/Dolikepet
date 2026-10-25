extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL DROP: "+words)
func run() -> void:
	var settings := "res://../../_work/tests/bowl-drop-settings.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420)
	cfg.set_value("pet","roaming_mode","off")
	cfg.save(settings)
	app = Scene.instantiate(); app.settings_path = settings
	root.add_child(app); app.set_process(false); app.set_process_input(false)
	root.mouse_passthrough = true
	var bowl: Window = app.bowl_window
	bowl.set_process(false); bowl.mouse_passthrough = true
	app.bowl_files.set_process(false)
	check(root.files_dropped.is_connected(app._on_pet_files_dropped),"pet window drops not connected")
	var paths := PackedStringArray(["C:/generated fixture/食物 A.txt","C:/generated fixture/食物 B.png"])
	for height in [240,420,780]:
		bowl.fit_pet(height); bowl.show()
		for origin in [Vector2i(120,120),Vector2i(-900,50),Vector2i(15,-800)]:
			bowl.position = origin
			var point: Vector2 = bowl.surface_point()
			root.position = origin-Vector2i(20,20)
			check(bowl.receive_covered_drop(paths,point),"overlapping pet did not forward drop")
			check(app.bowl_files.jobs.size()==1,"duplicate or missing import")
			check(app.bowl_files.jobs[0].paths==Array(paths),"batch paths changed")
			app.bowl_files.jobs.clear()
			check(not bowl.receive_covered_drop(paths,Vector2(origin)-Vector2.ONE),"outside drop accepted")
			check(not bowl.receive_covered_drop(paths,Vector2(origin)+Vector2.ONE),"transparent corner accepted")
			check(not bowl.receive_covered_drop(PackedStringArray(),point),"empty drop accepted")
			bowl.hide()
			check(not bowl.receive_covered_drop(paths,point),"hidden bowl accepted drop")
			check(app.bowl_files.jobs.is_empty(),"rejected drop queued an import")
			bowl.show()
	# Exercise the actual host signal connection at the current desktop pointer.
	bowl.fit_pet(420)
	var offset: Vector2 = bowl.surface_point()-Vector2(bowl.position)
	bowl.position = DisplayServer.mouse_get_position()-Vector2i(offset)
	root.files_dropped.emit(paths)
	check(app.bowl_files.jobs.size()==1,"host drop signal did not reach importer")
	app.bowl_files.jobs.clear()
	bowl.hide(); root.files_dropped.emit(paths)
	check(app.bowl_files.jobs.is_empty(),"host accepted hidden bowl drop")
	bowl.show(); bowl.files_dropped.emit(paths)
	check(app.bowl_files.jobs.size()==1,"ordinary bowl drop regressed")
	print("BOWL DROP: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
