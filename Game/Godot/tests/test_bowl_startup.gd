extends SceneTree
## Check the desktop's presented pixels, not just the correctly rendered viewport.
## A Win32 style rebuild used to leave this viewport behind an opaque gray region.
const Scene = preload("res://scenes/pet.tscn")
var app
var out := ""
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL STARTUP: "+message)
func capture(label: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var bowl: Window = app.bowl_window
	var expected := bowl.get_texture().get_image()
	var desktop := DisplayServer.screen_get_image(bowl.current_screen)
	check(desktop!=null and not desktop.is_empty(),label+": desktop capture unavailable")
	if desktop==null or desktop.is_empty(): return
	var origin := bowl.position-DisplayServer.screen_get_position(bowl.current_screen)
	var actual := desktop.get_region(Rect2i(origin,bowl.size))
	expected.save_png(out.path_join(label+"-viewport.png"))
	actual.save_png(out.path_join(label+"-desktop.png"))
	var gold := 0
	var matched := 0
	for y in expected.get_height():
		for x in expected.get_width():
			var color := expected.get_pixel(x,y)
			if color.a<0.98 or color.r<0.65 or color.g<0.4 or color.b>0.5: continue
			gold += 1
			var seen := actual.get_pixel(x,y)
			if Vector3(color.r-seen.r,color.g-seen.g,color.b-seen.b).length()<0.12: matched += 1
	check(gold>100,label+": cauldron texture not rendered")
	check(matched>gold*0.9,label+": native window covered the rendered cauldron (%d/%d gold pixels)"%[matched,gold])
func run() -> void:
	out = ProjectSettings.globalize_path("res://../../_work/tests/bowl-startup")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420); cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("pet","auto_fall_enabled",false); cfg.set_value("pet","auto_sit_enabled",false)
	check(cfg.save(out.path_join("settings.cfg"))==OK,"isolated settings save failed")
	app = Scene.instantiate(); app.settings_path = out.path_join("settings.cfg")
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false); app.bowl_files.set_process(false)
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = area.position+Vector2i(10,10)
	app.bowl_window.place(area.position+Vector2i(area.size/2))
	# Exercise startup with a restored visible bowl, before tray registration.
	app.bowl_window.show()
	app._setup_desktop_shell(out.path_join("cache"))
	await capture("first")
	check(OS.is_process_running(app.desktop_shell.helper_pid),"desktop shell helper did not start")
	app.bowl_window.hide(); await process_frame
	app.bowl_window.show()
	await capture("reopened")
	# The new summon path creates its native window after tray initialization.
	app.bowl_window.hide(); await process_frame
	app.bowl_window.begin_arrival(float(area.get_center().x),Rect2(area))
	app.bowl_window.cancel_arrival()
	app.bowl_window.place(area.position+Vector2i(area.size/2))
	await capture("summoned")
	print("BOWL STARTUP: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
