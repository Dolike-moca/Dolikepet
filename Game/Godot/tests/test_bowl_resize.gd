extends SceneTree
## Settings must resize the presented native cauldron, not only its viewport.
## Run alone on the desktop: another window covering the fixture is a failure.
const Sizes = preload("res://scripts/pet_size.gd")
var app
var out := ""
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("BOWL RESIZE: "+message)

func capture(label: String) -> void:
	# Let DWM present the completed native frame after settings closes. The
	# fixture does not advance physics or the soup shader during this interval.
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var bowl: Window = app.bowl_window
	var expected := bowl.get_texture().get_image()
	var native_size := DisplayServer.window_get_size(bowl.get_window_id())
	check(native_size==bowl.size,label+": native client and logical bowl size agree")
	check(expected.get_size()==bowl.size,label+": viewport and logical bowl size agree")
	var desktop := DisplayServer.screen_get_image(bowl.current_screen)
	check(desktop!=null and not desktop.is_empty(),label+": desktop capture available")
	if desktop==null or desktop.is_empty(): return
	var origin := bowl.position-DisplayServer.screen_get_position(bowl.current_screen)
	var bounds := Rect2i(origin,bowl.size)
	check(Rect2i(Vector2i.ZERO,desktop.get_size()).encloses(bounds),label+": fixture remains on its monitor")
	if not Rect2i(Vector2i.ZERO,desktop.get_size()).encloses(bounds): return
	var actual := desktop.get_region(bounds)
	expected.save_png(out.path_join(label+"-viewport.png"))
	actual.save_png(out.path_join(label+"-desktop.png"))
	var counts := {"all":0,"right":0,"feet":0}
	var matched := {"all":0,"right":0,"feet":0}
	for y in expected.get_height():
		for x in expected.get_width():
			var color := expected.get_pixel(x,y)
			if color.a<0.98: continue
			var seen := actual.get_pixel(x,y)
			var same := Vector3(color.r-seen.r,color.g-seen.g,color.b-seen.b).length()<0.12
			var zones := ["all"]
			if x>=expected.get_width()*0.82: zones.append("right")
			if y>=expected.get_height()*0.86: zones.append("feet")
			for zone in zones:
				counts[zone] += 1
				if same: matched[zone] += 1
	for zone in counts:
		check(counts[zone]>=8,label+": opaque "+zone+" pixels rendered")
		check(matched[zone]>=counts[zone]*0.90,
			label+": native "+zone+" pixels preserved (%d/%d)" % [matched[zone],counts[zone]])
	samples.append({"label":label,"pet_size":root.size.x,"bowl_size":[bowl.size.x,bowl.size.y],
		"opaque":counts,"matched":matched})

func save_size(pixels: int, on_top: bool) -> void:
	var bowl_id: int = app.bowl_window.get_window_id()
	app._menu_action(14)
	await process_frame
	var settings = app.settings_window
	check(settings.visible,"settings opens through the production menu")
	settings.size_slider.value = Sizes.PIXELS.find(pixels)
	settings.topmost.set_pressed_no_signal(on_top)
	settings.save_button.pressed.emit()
	check(not settings.visible,"Save closes the independent settings window")
	check(app.size_change.target==pixels,"Save reaches the requested preset")
	for frame in 240:
		if not app.size_change.pending(): break
		app._advance_size_change(1.0/30.0,false)
		await process_frame
	check(not app.size_change.pending() and root.size.x==pixels,"saved size animation completes")
	check(root.always_on_top==on_top and app.bowl_window.always_on_top==on_top,"Save applies the chosen topmost state")
	check(app.bowl_window.get_window_id()==bowl_id,"Save preserves the existing bowl window and animation state")

func run() -> void:
	if OS.get_name()!="Windows" or DisplayServer.get_name()=="headless":
		print("BOWL RESIZE: SKIP (requires a Windows desktop)")
		quit(); return
	out = ProjectSettings.globalize_path("res://../../_work/tests/bowl-resize/%d" % OS.get_process_id())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",300)
	cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("pet","auto_sit_enabled",false)
	cfg.set_value("pet","auto_fall_enabled",false)
	check(cfg.save(out.path_join("settings.cfg"))==OK,"isolated settings saved")
	app = load("res://scenes/pet.tscn").instantiate()
	# A non-default settings path prevents the production file worker starting.
	app.settings_path = out.path_join("settings.cfg")
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false); app.bowl_files.set_process(false)
	app.bowl_summon.finish(); app.bubble.hide()
	check(app.bowl_files.helper.is_empty() and app.bowl_files.jobs.is_empty(),"real food and digestion worker never starts")
	check(app.pet.available,"production pet model loads")
	if app.pet.model.has_method("restore_desktop_visibility"):
		check(not app.pet.model.restore_desktop_visibility(0),"native visibility repair rejects invalid handles")
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.end.x-610,area.position.y+20)
	app.bowl_window.place(Vector2i(area.position.x+40,area.end.y-300))
	app.bowl_window.fill = 0.65
	app.bowl_window.soup.set_shader_parameter("fullness",0.65)
	app.bowl_window.show()
	app._setup_desktop_shell(out.path_join("shell-cache"))
	await capture("initial-100")
	check(OS.is_process_running(app.desktop_shell.helper_pid),"production desktop shell helper runs")
	# Cross the full range in both directions instead of only adjacent sizes.
	for pixels in [600,150,525,225,450,300,375]:
		await save_size(pixels,true)
		await capture("preset-%d" % pixels)
	await save_size(375,true)
	await capture("repeat-same-settings")
	await save_size(600,false)
	await capture("topmost-off-grow")
	await save_size(150,true)
	await capture("topmost-on-shrink")
	await save_size(150,false)
	await capture("topmost-off-same-size")
	await save_size(150,true)
	await capture("topmost-on-same-size")
	app._menu_action(11)
	await capture("menu-topmost-off")
	app._menu_action(11)
	await capture("menu-topmost-on")
	app.bowl_window.hide()
	await save_size(600,false)
	check(not app.bowl_window.visible,"resizing a hidden bowl does not reveal it")
	check(not app.catch_score.visible,"changing topmost does not reveal a hidden score panel")
	app.bowl_window.show()
	await capture("hidden-resize-reopen")
	var report := {"checks":checks,"failures":failures,"samples":samples}
	var file := FileAccess.open(out.path_join("result.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
	app.queue_free()
	await process_frame
	print("BOWL RESIZE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
