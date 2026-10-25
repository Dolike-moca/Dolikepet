extends SceneTree
## Exercise visible eyelid output, scheduling, interruptions, and optional Live2D rendering.
const Behavior = preload("res://scripts/pet_behavior.gd")
const LivePet = preload("res://scripts/live2d_pet.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BLINK: " + message)

func _step(controller, dt: float) -> float:
	return controller.update(dt, Vector2.ZERO, Vector2.ZERO, 420, false).eyeNear

func _double_seed() -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(1, 1000):
		rng.seed = candidate
		if rng.randf() < 0.18:
			return candidate
	return 0

func _simulation(fps: int) -> void:
	var controller = Behavior.new()
	controller.blink_rng.seed = 20261020
	controller.next_blink = 1.0
	var starts: Array[float] = []
	var last_start := -10.0
	var closures := 0
	var previous_eye := 1.0
	var valid_eyes := true
	var has_half_open := false
	for frame in 300 * fps:
		var eye := _step(controller, 1.0 / fps)
		valid_eyes = valid_eyes and is_finite(eye) and eye >= 0.0 and eye <= 1.0 \
			and eye == controller.values.eyeFar
		has_half_open = has_half_open or (eye > 0.1 and eye < 0.9)
		if eye == 0.0 and previous_eye > 0.0:
			closures += 1
		if controller.blink_start != last_start:
			starts.append(controller.blink_start)
			last_start = controller.blink_start
		previous_eye = eye
	var pairs := 0
	var group_size := 1
	var largest_group := 1
	var shortest_pause := INF
	var longest_pause := 0.0
	var valid_gaps := true
	for index in range(1, starts.size()):
		var gap := starts[index] - starts[index - 1]
		if gap < 1.0:
			pairs += 1
			group_size += 1
			valid_gaps = valid_gaps and gap >= 0.30 - 0.00001 and gap <= 0.38 + 1.0 / fps
		else:
			group_size = 1
			shortest_pause = minf(shortest_pause, gap)
			longest_pause = maxf(longest_pause, gap)
		largest_group = maxi(largest_group, group_size)
	_check(valid_eyes and has_half_open, "eyelids invalid or not smoothly interpolated at %d fps" % fps)
	_check(starts.size() > 40, "automatic blinking stopped at %d fps" % fps)
	_check(abs(closures - starts.size()) <= 1, "a scheduled blink never visibly closed at %d fps" % fps)
	_check(pairs > 0 and pairs < starts.size() / 2, "missing or excessive double blinks")
	_check(largest_group == 2 and valid_gaps, "overlapping blinks or more than two in a group")
	_check(shortest_pause >= 1.7 - 0.00001 and longest_pause <= 7.7 + 1.0 / fps,
		"ordinary pause out of range")
	_check(longest_pause - shortest_pause > 2.0, "pauses did not vary")
	print("BLINK %d fps / 300 seconds: %d blinks, %d pairs, pauses %.2f–%.2f s" %
		[fps, starts.size(), pairs, shortest_pause, longest_pause])

func _run() -> void:
	for fps in [30, 60]:
		_simulation(fps)
	# Interrupt a real scheduled double with each type of closed-eye expression.
	for action in ["closed", "closedHappy", "pet"]:
		var controller = Behavior.new()
		controller.blink_rng.seed = _double_seed()
		controller.next_blink = 0.0
		_step(controller, 1.0 / 60.0)
		_check(controller.second_blink_at > controller.time, "failed to schedule double")
		controller.command(action)
		for frame in 30:
			_step(controller, 1.0 / 60.0)
		_check(controller.second_blink_at < 0.0 and controller.values.eyeNear == 0.0,
			"closed expression did not cancel double: " + action)
		controller.command("normal")
		for frame in 60:
			_step(controller, 1.0 / 60.0)
		_check(controller.values.eyeNear == 1.0 and controller.blink_start < 0.0,
			"reopening immediately replayed a stale blink")
	var manual = Behavior.new()
	manual.blink_rng.seed = _double_seed()
	manual.next_blink = 0.0
	_step(manual, 1.0 / 60.0)
	manual.command("blink")
	_check(manual.second_blink_at < 0.0, "manual blink left a queued second blink")
	var manual_closures := 0
	var previous_eye := 1.0
	for frame in 60:
		var eye := _step(manual, 1.0 / 60.0)
		if eye == 0.0 and previous_eye > 0.0:
			manual_closures += 1
		previous_eye = eye
	_check(manual_closures == 1 and manual.values.eyeNear == 1.0, "manual blink was not a single cycle")
	var paused = Behavior.new()
	paused.next_blink = 0.0
	var rng_state: int = paused.blink_rng.state
	for dt in [0.0, -1.0, NAN]:
		_step(paused, dt)
	_check(paused.blink_start < 0.0 and paused.blink_rng.state == rng_state,
		"zero/invalid time advanced random schedule")
	if "--render" in OS.get_cmdline_user_args():
		await _render_double()
	print("BLINK: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _render_double() -> void:
	root.size = Vector2i(420, 420)
	root.transparent_bg = true
	root.mouse_passthrough = true
	var pet = LivePet.new()
	root.add_child(pet)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	_check(pet.load_pet(config), pet.failure)
	if not pet.available:
		return
	pet.fit(Vector2(root.size))
	var controller = Behavior.new()
	controller.blink_rng.seed = _double_seed()
	controller.next_blink = 0.2
	var folder := ProjectSettings.globalize_path("res://../../_work/reviews/godot/blinking")
	DirAccess.make_dir_recursive_absolute(folder)
	# Actual rendered eye region across one automatically scheduled double.
	var samples := [11, 14, 17, 21, 26, 30, 33, 36, 39, 43, 48, 55]
	var strip := Image.create(220 * 6, 180 * 2, false, Image.FORMAT_RGBA8)
	strip.fill(Color("#24212b"))
	var sample_index := 0
	var visible_closures := 0
	var previous_eye := 1.0
	for frame in 60:
		var pose: Dictionary = controller.update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO, 420, false)
		pet.apply_pose(pose, 1.0 / 60.0)
		if pose.eyeNear == 0.0 and previous_eye > 0.0:
			visible_closures += 1
		previous_eye = pose.eyeNear
		await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.save_png(folder.path_join("frame-%03d.png" % frame))
		if frame in samples:
			var face := Rect2i(Vector2i(pet.gaze_anchor()) - Vector2i(110, 85), Vector2i(220, 180))
			strip.blend_rect(screenshot, face, Vector2i(sample_index % 6 * 220, sample_index / 6 * 180))
			sample_index += 1
	_check(visible_closures == 2 and controller.values.eyeNear == 1.0,
		"rendered double did not complete two closures and reopen")
	_check(strip.save_png(folder.path_join("double-blink-frames.png")) == OK, "could not save rendered frames")
