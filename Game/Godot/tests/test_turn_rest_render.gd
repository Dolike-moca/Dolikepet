extends SceneTree
## Exercise the real idle timer -> roaming -> Live2D path with isolated settings.
const Scene = preload("res://scenes/pet.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("TURN REST RENDER: " + message)

func _run() -> void:
	var output := ProjectSettings.globalize_path("res://../../_work/tests/turn-rest-frames")
	DirAccess.make_dir_recursive_absolute(output)
	var settings_path := output.path_join("settings.cfg")
	var config := ConfigFile.new()
	config.set_value("window", "size", 420)
	config.set_value("window", "position", Vector2i(80, 80))
	config.set_value("pet", "auto_sit_enabled", false)
	config.set_value("pet", "roaming_mode", "off")
	config.save(settings_path)
	var app = Scene.instantiate()
	app.settings_path = settings_path
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	root.mouse_passthrough = true
	app.bubble.hide()
	_check(app.pet.available, app.pet.failure)
	if not app.pet.available:
		quit(1)
		return
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	var origin := Vector2i(area.position.x + 80, area.end.y - root.size.y)
	root.position = origin
	for facing in [-1, 1]:
		for deadline_frame in [2, 8, 14]:
			app._menu_action(13)
			app.idle_sitting.configure(false, 5, 5)
			app.roaming.configure("off")
			# Fully restore standing between scenarios.
			for n in 180:
				app._process(1.0 / 60.0)
			app.roaming.configure("free")
			app.roaming.state = "turning"
			app.roaming.facing = facing
			app.roaming.facing_scale = -float(facing)
			app.roaming.direction = -facing
			app.roaming.stage_time = 0.0
			app.roaming.travel_position = Vector2(origin)
			app.roaming.target_x = origin.x + app.roaming.direction * 200.0
			app.idle_sitting.configure(true, 5, 5)
			app.idle_sitting.needs_new_wait = false
			app.idle_sitting.wait_seconds = 5.0
			app.idle_sitting.elapsed = 5.0 - deadline_frame / 60.0 + 0.000001
			var queued_in_turn := false
			var seated_at_full_width := true
			var window_still := true
			var first_seated := -1
			for frame in 120:
				app._process(1.0 / 60.0)
				queued_in_turn = queued_in_turn or (
					app.roaming.rest_requested and app.roaming.state == "turning")
				window_still = window_still and root.position == origin
				if app.pet.sitting.seated:
					if first_seated == -1:
						first_seated = frame
					var rendered_scale: float = app.pet.transform.x.length() / app.pet.pixel_scale
					seated_at_full_width = seated_at_full_width \
						and is_equal_approx(rendered_scale, 1.0)
				await process_frame
				await RenderingServer.frame_post_draw
				if frame in [0, 7, 8, 16, 17, 30, 60, 119]:
					var picture := root.get_texture().get_image()
					if frame >= 30:
						_check(picture.get_used_rect().size.x > root.size.x * 0.55,
							"rendered pet remained a narrow strip after turn")
					picture.save_png(output.path_join("%d-%02d-%03d.png" % [
						facing, deadline_frame, frame]))
			_check(queued_in_turn, "real idle timer did not expire during turn")
			_check(first_seated >= 16 and app.pet.sitting.amount == 1.0,
				"sit started during turn, or failed to finish")
			_check(seated_at_full_width, "Live2D remained horizontally compressed while sitting")
			_check(window_still, "pending rest started walking")
			_check(app.roaming.facing == -facing, "rest did not retain completed facing")
	print("TURN REST RENDER: 6 timer scenarios, 720 frames, %d checks, %d failures" % [
		checks, failures])
	quit(0 if failures == 0 else 1)
