extends SceneTree
const Idle = preload("res://scripts/idle_sitting.gd")
const Scene = preload("res://scenes/pet.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("IDLE SITTING: " + message)

func _run() -> void:
	var idle = Idle.new()
	_check(idle.enabled and idle.minimum_seconds == 60.0 and idle.maximum_seconds == 180.0, "fresh defaults")
	idle.configure(true, 120, 120)
	_check(not idle.advance(119.0, false, false), "sat before the deadline")
	_check(idle.advance(1.0, false, false), "missed the deadline")
	_check(not idle.advance(500.0, false, true), "repeated automatic request")
	_check(not idle.interact(false) and idle.automatically_seated, "mouse pass woke the pet")
	_check(idle.interact(), "click did not wake automatic sitting")
	idle.manual_pose()
	_check(not idle.interact(), "manual sitting was woken")
	idle.configure(false, 15.0, 15.0)
	_check(not idle.advance(900.0, false, false), "disabled automatic sitting")
	idle.configure(true, 15.0, 15.0)
	idle.advance(14.0, false, false)
	idle.interact(false)
	_check(not idle.advance(1.0, false, false), "motion failed to reset the deadline")
	idle.advance(14.0, true, false)
	_check(idle.elapsed == 0.0, "menu/drag activity should hold the deadline")
	_check(not idle.advance(14.0, false, false), "deadline not restarted after activity")
	_check(idle.advance(1.0, false, false), "deadline after activity")
	idle.configure(true, NAN, NAN)
	_check(idle.minimum_seconds == 60.0 and idle.maximum_seconds == 180.0, "invalid wait duration")
	idle.configure(true, -20.0, -10.0)
	_check(idle.minimum_seconds == 5.0 and idle.maximum_seconds == 5.0, "minimum wait duration")
	_check(not idle.advance(4.9, false, false), "five-second minimum fired early")
	_check(idle.advance(0.1, false, false), "five-second minimum was not honored")
	idle.configure(true, 9000.0, 10000.0)
	_check(idle.minimum_seconds == 3600.0 and idle.maximum_seconds == 3600.0, "maximum wait duration")
	_check(not idle.advance(NAN, false, false), "invalid delta")
	idle.configure(true, 180.0, 60.0)
	_check(idle.minimum_seconds == 60.0 and idle.maximum_seconds == 180.0, "malformed config order")
	idle.rng.seed = 20261020
	var durations := {}
	for cycle in 128:
		idle.manual_pose()
		var before_pick: int = idle.rng.state
		idle.advance(100.0, true, false)
		_check(idle.rng.state == before_pick, "busy frame drew a random wait")
		idle.advance(0.001, false, false)
		var chosen: float = idle.wait_seconds
		durations[int(chosen)] = true
		_check(chosen >= 60.0 and chosen <= 180.0, "random wait outside user range")
		var after_pick: int = idle.rng.state
		_check(not idle.advance(chosen - 0.002, false, false), "random deadline fired early")
		_check(idle.wait_seconds == chosen and idle.rng.state == after_pick, "deadline changed each frame")
		_check(idle.advance(0.002, false, false), "random deadline was not honored")
	_check(durations.size() > 20, "random waits did not vary across idle periods")
	idle.configure(true, 30.0, 40.0)
	idle.advance(15.0, false, false)
	idle.interact(false)
	_check(idle.elapsed == 0.0 and idle.needs_new_wait, "interaction did not restart random wait")
	idle.advance(0.01, false, false)
	_check(idle.wait_seconds >= 30.0 and idle.wait_seconds <= 40.0, "new range not applied")

	var folder := ProjectSettings.globalize_path("res://../../_work/tests/idle-sitting-test")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("settings.cfg")
	var seed := ConfigFile.new()
	seed.set_value("window", "size", 420)
	seed.set_value("window", "position", Vector2i(80, 80))
	seed.set_value("pet", "auto_sit_enabled", true)
	seed.set_value("pet", "auto_fall_enabled", false) # Original floating-mode regression.
	seed.set_value("pet", "auto_sit_seconds", 10.0)
	seed.set_value("future", "preserved", "yes")
	_check(seed.save(path) == OK, "test configuration could not be saved")
	var app = Scene.instantiate()
	app.settings_path = path # Never read or overwrite the user's settings.
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_process_input(false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	app.bubble.hide()
	_check(app.pet.available, app.pet.failure)
	if not app.pet.available:
		quit(1)
		return
	app._process(9.9)
	_check(not app.pet.sitting.seated, "app sat early")
	app._process(0.1)
	_check(app.pet.sitting.seated and app.idle_sitting.automatically_seated, "app did not sit")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(3, 0)
	app._input(motion)
	_check(app.pet.sitting.seated, "passing mouse woke automatic sitting")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	app._input(click)
	_check(not app.pet.sitting.seated, "press did not wake before drag")
	app.dragging = false
	app._menu_action(12)
	app._zoom(0)
	_check(app.pet.sitting.seated and not app.idle_sitting.automatically_seated,
		"manual sitting was changed by a zoom interaction")
	app._menu_action(13)
	app._process(9.0)
	app._menu_action(14)
	_check(app.settings_window.visible, "settings menu entry")
	app._process(100.0)
	_check(app.pet.sitting.seated or app.idle_sitting.elapsed>0.0, "settings froze idle sitting timer")
	_check(app.settings_window.automatic.button_pressed
		and app.settings_window.minimum_seconds.value == 10.0
		and app.settings_window.maximum_seconds.value == 10.0,
		"settings did not display saved values")
	_check(app.idle_sitting.minimum_seconds == 10.0 and app.idle_sitting.maximum_seconds == 10.0,
		"legacy fixed duration was not retained as equal endpoints")
	app.settings_window.minimum_minutes.value = 1
	app.settings_window.minimum_seconds.value = 0
	app.settings_window.maximum_minutes.value = 3
	app.settings_window.maximum_seconds.value = 0
	var window: Window = app.settings_window
	window.set_process_input(false)
	window.mouse_passthrough = true
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../../_work/reviews/godot/idle-sitting")
	DirAccess.make_dir_recursive_absolute(output)
	window.get_texture().get_image().save_png(output.path_join("settings-range.png"))
	_check(app.settings_window.save_button.get_global_rect().end.y <= window.size.y - 8,
		"save button clipped")
	_check(app.settings_window.delay_hint.get_global_rect().end.x <= window.size.x,
		"settings text clipped")
	app.settings_window.automatic.button_pressed = false
	app.settings_window.maximum_minutes.value = 4
	app.settings_window.cancel_button.pressed.emit()
	_check(app.idle_sitting.enabled and app.idle_sitting.minimum_seconds == 10.0
		and app.idle_sitting.maximum_seconds == 10.0, "cancel applied drafts")
	app._menu_action(14)
	app.settings_window.minimum_minutes.value = 2
	app.settings_window.maximum_minutes.value = 1
	await process_frame # SpinBox synchronizes its displayed text on the next draw.
	app.settings_window.save_button.pressed.emit()
	_check(app.settings_window.visible and app.settings_window.save_button.disabled,
		"reversed range was saved")
	app.settings_window.minimum_minutes.value = 0
	app.settings_window.minimum_seconds.value = 4
	_check(app.settings_window.save_button.disabled, "less-than-5-second wait was accepted")
	app.settings_window.minimum_seconds.value = 5
	app.settings_window.maximum_minutes.value = 60
	app.settings_window.maximum_seconds.value = 0
	_check(not app.settings_window.save_button.disabled, "5 seconds through 60 minutes was rejected")
	await process_frame
	app.settings_window.save_button.pressed.emit()
	_check(not app.settings_window.visible and app.idle_sitting.minimum_seconds == 5.0
		and app.idle_sitting.maximum_seconds == 3600.0, "boundary range was not saved")
	app._load_settings()
	_check(app.idle_sitting.minimum_seconds == 5.0 and app.idle_sitting.maximum_seconds == 3600.0,
		"boundary range did not survive reload")
	app._menu_action(14)
	app.settings_window.minimum_minutes.value = 1
	app.settings_window.maximum_minutes.value = 60
	app.settings_window.maximum_seconds.value = 1
	_check(app.settings_window.save_button.disabled, "over-60-minute wait was accepted")
	app.settings_window.maximum_minutes.value = 2
	app.settings_window.automatic.button_pressed = false
	_check(not app.settings_window.minimum_seconds.editable
		and not app.settings_window.maximum_minutes.editable, "disabled wait control remains editable")
	await process_frame
	app.settings_window.minimum_seconds.get_line_edit().text = "15"
	app.settings_window.maximum_seconds.get_line_edit().text = "30"
	app.settings_window.save_button.pressed.emit()
	_check(not app.settings_window.visible and not app.idle_sitting.enabled, "save did not apply and close")
	_check(app.idle_sitting.minimum_seconds == 75.0 and app.idle_sitting.maximum_seconds == 150.0,
		"typed duration range was not committed")
	app._process(100.0)
	_check(not app.pet.sitting.seated, "disabled setting was ignored")
	var saved := ConfigFile.new()
	_check(saved.load(path) == OK, "saved configuration unavailable")
	_check(saved.get_value("pet", "auto_sit_enabled") == false
		and saved.get_value("pet", "auto_sit_min_seconds") == 75.0
		and saved.get_value("pet", "auto_sit_max_seconds") == 150.0, "persistence failed")
	_check(not saved.has_section_key("pet", "auto_sit_seconds"), "stale fixed-duration preference")
	_check(saved.get_value("future", "preserved") == "yes", "unknown settings were discarded")
	app.idle_sitting.configure(true, 10, 10)
	app._load_settings()
	_check(not app.idle_sitting.enabled and app.idle_sitting.minimum_seconds == 75.0
		and app.idle_sitting.maximum_seconds == 150.0, "reload lost preferences")
	app._apply_auto_sit_settings(true, 10, 10)
	app.dragging = true
	# Prevent the live pointer from ending the synthetic drag during this check.
	_check(not app.idle_sitting.advance(100.0, app.dragging, false), "sat while dragging")
	app.dragging = false
	app.menu.popup()
	app._process(100.0)
	_check(not app.pet.sitting.seated, "sat while menu was open")
	app.menu.hide()
	app._process(9.0)
	app._input(motion)
	app._process(2.0)
	_check(not app.pet.sitting.seated, "app motion did not reset idle")
	app._menu_action(5) # A long idle frame must not interrupt the talking demo.
	app._process(11.0)
	_check(not app.pet.sitting.seated, "automatic sit interrupted talk")
	app.behavior.talk_until = 0.0
	app.idle_sitting.interact(false)
	app._process(10.0)
	_check(app.pet.sitting.seated, "automatic sitting did not resume")
	app._menu_action(14)
	var previous_mode: String = app.roaming.mode
	app.settings_window.activity.select(0)
	app.settings_window.cancel_button.pressed.emit()
	_check(app.roaming.mode == previous_mode, "cancel applied activity mode")
	for index in 3:
		app._menu_action(14)
		app.settings_window.activity.select(index)
		await process_frame
		app.settings_window.save_button.pressed.emit()
		_check(app.roaming.mode == app.roaming.MODES[index], "activity mode not applied")
		app._load_settings()
		_check(app.roaming.mode == app.roaming.MODES[index], "activity mode not persisted")
	# Exercise real host-window movement too, using this test's isolated preferences.
	app._apply_auto_sit_settings(false, 15, 25, "free")
	app.pet.set_seated(false)
	app.behavior.reaction_until = 0.0
	app.behavior.talk_until = 0.0
	app.roaming.wait_remaining = 0.0
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = area.position + Vector2i(80, 30)
	var walked := false
	var bounded := true
	for frame in 240:
		app._process(1.0 / 60.0)
		walked = walked or app.roaming.state == "walking"
		bounded = bounded and root.position.x >= area.position.x \
			and root.position.x + root.size.x <= area.end.x
	print("HOST WALK: state=%s wait=%.2f sit=%.4f window=%s area=%s menu=%s settings=%s drag=%s" %
		[app.roaming.state, app.roaming.wait_remaining, app.pet.sitting.amount,
		root.position, area, app.menu.visible, app.settings_window.visible, app.dragging])
	_check(walked and bounded, "host window did not walk within the current display")
	_check(root.position.y + root.size.y == area.end.y, "host window did not settle at work-area bottom")
	app._input(click)
	var grabbed_position := root.position
	_check(app.dragging and app.roaming.state == "idle", "click failed to take over from walking")
	app.dragging = false
	app._menu_action(14)
	app._process(0.1)
	_check(root.position == grabbed_position and app.roaming.state == "idle", "window moved while settings were open")
	app.settings_window.hide()
	# A very quick menu selection may arrive while the knee/foot gait still
	# has weight. Manual sitting must finish that gait before changing meshes.
	app._menu_action(13)
	app.roaming.configure("off")
	for frame in 180:
		app._process(1.0 / 60.0)
	app.roaming.configure("free")
	app.roaming.state = "walking"
	app.roaming.weight = 1.0
	app.roaming.cadence = app.roaming.WALK_CYCLES_PER_SECOND
	app.roaming.phase = 0.0
	app.roaming.travel_position = Vector2(root.position)
	app.roaming.target_x = root.position.x + 150.0
	app._process(0.0)
	app._menu_action(12)
	var first_sitting_frame := -1
	var settled_before_sitting := true
	var standing_meshes_retained := true
	for frame in 120:
		app._process(1.0 / 60.0)
		if app.pet.sitting.amount > 0.0:
			if first_sitting_frame == -1:
				first_sitting_frame = frame
			settled_before_sitting = settled_before_sitting and app.roaming.weight <= 0.00001
		elif app.roaming.weight > 0.0:
			standing_meshes_retained = standing_meshes_retained \
				and app.pet.meshes["ArtMesh22"].visible and app.pet.meshes["ArtMesh23"].visible
	_check(first_sitting_frame >= 13 and app.pet.sitting.amount == 1.0,
		"quick manual sit did not wait for the last step or failed to complete")
	_check(settled_before_sitting and standing_meshes_retained,
		"quick manual sit switched to straight-leg meshes during knee flex")
	_check(not app.idle_sitting.automatically_seated and app.pet.sitting.seated,
		"quick manual sit lost its manual-pose protection")
	print("IDLE SITTING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
