extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var failures := 0
var checks := 0
var app
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL E2E: "+words)
func until(predicate: Callable, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await process_frame
	return false
func run() -> void:
	var base := ProjectSettings.globalize_path("res://../../_work/tests/bowl-e2e-%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base)
	var fixture := base.path_join("投喂 测试.txt")
	var content := "Only this generated fixture may be swallowed."
	var file := FileAccess.open(fixture,FileAccess.WRITE); file.store_string(content); file.close()
	var cfg := ConfigFile.new(); var path := base.path_join("settings.cfg")
	cfg.set_value("window","size",420); cfg.set_value("pet","roaming_mode","off")
	# This fixture starts with a settled, reachable bowl. Startup summoning
	# (including impact/dizziness) is covered by test_bowl_summon_host.
	cfg.set_value("bowl","visible",false)
	cfg.set_value("pet","auto_sit_enabled",false); cfg.save(path)
	app = Scene.instantiate(); app.settings_path = path; app.bowl_root_override = base.path_join("饭盆")
	root.add_child(app); root.mouse_passthrough = true
	app.bowl_window.mouse_passthrough = true
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x+600,area.end.y-420)
	app.bowl_window.place(Vector2i(root.position.x+15,area.end.y-app.bowl_window.size.y))
	app.bowl_enabled = true; app.bowl_window.show()
	check(await until(func(): return app.bowl_files.initialized),"native helper initialization timed out")
	check(FileAccess.file_exists(app.bowl_files.folder.path_join(".bowl.ico")),"cauldron folder icon absent")
	if "--covered" in OS.get_cmdline_user_args():
		var original: Vector2i = app.bowl_window.position
		var offset: Vector2 = app.bowl_window.surface_point()-Vector2(original)
		app.bowl_window.position = DisplayServer.mouse_get_position()-Vector2i(offset)
		root.files_dropped.emit(PackedStringArray([fixture]))
		app.bowl_window.place(original)
	else: app.bowl_window.files_received.emit(PackedStringArray([fixture]))
	check(await until(func(): return app.pickup.current!=null and app.pickup.age>2.0),"drop, scan, approach and catch did not connect")
	if app.pickup.current!=null:
		var source: Dictionary = app.pickup.current.source.duplicate()
		check(not FileAccess.file_exists(fixture) and FileAccess.file_exists(source.path),"drop did not move generated file into bowl")
		check(app.bowl_files.total_bytes==content.to_utf8_buffer().size(),"folder byte total wrong")
		check(app.bowl_window.fill>0.0,"bytes did not drive soup")
		# Cancellation must never consume an underlying file.
		app.pickup.cancel(true); app.bowl_user_cooldown = 0.6
		await create_timer(0.4).timeout
		check(FileAccess.file_exists(source.path),"interrupted meal swallowed file")
		check(await until(func(): return app.pickup.current!=null and app.pickup.age>2.0),"interrupted file did not become available again")
		if app.pickup.current!=null:
			app.pickup.age = app.pickup.food_end+app.pickup.tail_time-0.01
			check(await until(func(): return not FileAccess.file_exists(source.path)),"completed food was not swallowed")
			check(await until(func(): return app.bowl_files.total_bytes==0),"soup bytes did not clear after swallow")
			var swallowed: String = app.bowl_files.stomach_folder.path_join(fixture.get_file())
			check(FileAccess.get_file_as_string(swallowed)==content,"swallowed contents changed or disappeared")
			check(app.satiety.used==content.to_utf8_buffer().size(),"actual swallowed bytes did not update satiety")
	check(FileAccess.file_exists(app.bowl_files.folder.path_join("desktop.ini")),"folder metadata was consumed")
	print("BOWL E2E: %d checks, %d failures; fixture %s"%[checks,failures,base])
	quit(0 if failures==0 else 1)
