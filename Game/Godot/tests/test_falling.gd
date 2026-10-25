extends SceneTree
const Fall = preload("res://scripts/falling_motion.gd")
const Hair = preload("res://scripts/falling_hair.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FALL: " + message)

func _initialize() -> void:
	var durations: Array[float] = []
	for fps in [30, 60, 120]:
		for size in [240.0, 420.0, 800.0]:
			for screen_origin in [Vector2.ZERO, Vector2(-1920, -1080)]:
				var fall = Fall.new()
				var area := Rect2(screen_origin, Vector2(size * 4, size * 4))
				var at: Vector2 = screen_origin + Vector2(size, size * 0.5)
				var initial := at
				var floor_y: float = area.end.y - size
				var previous_speed := 0.0
				var done := false
				for frame in fps * 5:
					var result: Dictionary = fall.update(1.0 / fps, at, Vector2.ONE * size, area)
					if result.move: at = result.position
					check(at.x == initial.x and at.y >= initial.y and at.y <= floor_y, "horizontal drift / floor overshoot")
					if frame < int(fps * 0.13): check(at == initial, "missing brief hover")
					check(fall.speed <= size * Fall.TERMINAL_SPEED + 0.001, "terminal speed exceeded")
					if not result.landed: check(fall.speed + 0.001 >= previous_speed, "fall did not accelerate")
					previous_speed = fall.speed
					if result.landed:
						done = true
						durations.append(float(frame + 1) / fps)
						break
				check(done and at.y == floor_y and not fall.active() and fall.speed == 0.0, "did not settle exactly at usable floor")
				check(not fall.update(0.1, at, Vector2.ONE * size, area).move, "landed pet bounced or restarted")
	for duration in durations: check(absf(duration - durations[0]) < 0.04, "fall changes with FPS or pet size")
	var fall = Fall.new()
	var area := Rect2(0, 0, 1920, 1080)
	var at := Vector2(300, 100)
	for i in 20:
		var result: Dictionary = fall.update(1.0 / 60, at, Vector2(420, 420), area)
		if result.move: at = result.position
	var age: float = fall.age
	var speed: float = fall.speed
	check(not fall.update(1.0, at, Vector2(420, 420), area, false, true).move and fall.age == age and fall.speed == speed, "menu/minimize failed to freeze fall")
	check(not fall.update(NAN, at, Vector2(420, 420), area).move, "invalid delta")
	check(not fall.update(0.1, at, Vector2(420, 420), area, true).move and not fall.active(), "regrab did not stop falling")
	fall.configure(false)
	check(not fall.update(0.1, at, Vector2(420, 420), area).move and not fall.active(), "off mode fell")
	fall.configure(true)
	check(fall.update(0.05, at, Vector2(420, 420), area).started, "enabling in midair did not start")
	fall.reposition(Vector2(320, 200))
	var moved: Dictionary = fall.update(0.05, Vector2(320, 200), Vector2(600, 600), area)
	check(moved.position == Vector2(320, 200), "resize restored old position")
	var small := Rect2(0, 0, 320, 200)
	check(not fall.update(0.1, Vector2.ZERO, Vector2(420, 420), small).started, "small display floor invalid")
	check_hair()
	check_acceleration()
	print("FALL: %d checks, %d failures, normalized-height drop %.3fs" % [checks, failures, durations[0]])
	quit(0 if failures == 0 else 1)

func check_acceleration() -> void:
	# Measure actual travel at separated times: an early high speed followed by a
	# flat cap would pass monotonicity checks, but fail this perceptual pacing check.
	for fps in [30, 60, 120]:
		var motion = Fall.new()
		var at := Vector2.ZERO
		var samples := {}
		for frame in fps * 2:
			var result: Dictionary = motion.update(1.0 / fps, at, Vector2(420, 420), Rect2(0, 0, 1920, 6000))
			if result.move: at = result.position
			for t in [0.2, 0.4, 0.6, 0.8]:
				if motion.age + 0.000001 >= Fall.HOVER_SECONDS + t and not samples.has(t):
					samples[t] = Vector2(at.y / 420.0, motion.speed / 420.0)
		check(samples[0.2].y < 0.85, "initial fall too abrupt")
		check(samples[0.6].y > 3.8 and samples[0.6].y > samples[0.2].y * 5.0, "late fall did not look faster")
		var first: float = samples[0.2].x
		var middle: float = samples[0.4].x - samples[0.2].x
		var last: float = samples[0.6].x - samples[0.4].x
		check(middle > first * 3.0 and last > middle * 1.8, "equal-time travel did not expand visibly")
		check(samples[0.6].y < Fall.TERMINAL_SPEED and is_equal_approx(samples[0.8].y, Fall.TERMINAL_SPEED), "speed cap too early / missing")
		print("ACCEL %d FPS: speed at 0.2 / 0.4 / 0.6s = %.3f / %.3f / %.3f window heights/s" % [fps, samples[0.2].y, samples[0.4].y, samples[0.6].y])

func check_hair() -> void:
	var samples: Array[Dictionary] = []
	for fps in [30, 60, 120]:
		var hair = Hair.new()
		var half_times := {}
		for frame in fps * 2:
			var offsets: Dictionary = hair.update(1.0 / fps, 2.6, true)
			for key in Hair.LAYERS:
				check(offsets[key].is_finite() and offsets[key].y <= 0.001, "hair did not trail upward")
				if -offsets[key].y >= Hair.LAYERS[key][2] * 0.5 and not half_times.has(key):
					half_times[key] = float(frame + 1) / fps
		check(half_times.hairFront < half_times.hairSide and half_times.hairSide < half_times.hairBraidNear
			and half_times.hairBraidNear <= half_times.hairBraidFar and half_times.hairBraidFar < half_times.hairBack, "layers did not respond in order")
		check(-hair.offsets.hairBack.y > -hair.offsets.hairBraidNear.y
			and -hair.offsets.hairBraidNear.y > -hair.offsets.hairBraidFar.y
			and -hair.offsets.hairSide.y > -hair.offsets.hairFront.y, "layer amplitudes lost perspective")
		samples.append(hair.offsets.duplicate())
		var frozen: Dictionary = hair.offsets.duplicate()
		hair.update(1.0, 0.0, true, true)
		check(frozen == hair.offsets, "pause changed hair")
		for i in fps:
			var before: float = hair.offsets.hairBack.length()
			hair.update(1.0 / fps, 0.0, false)
			check(hair.offsets.hairBack.length() <= before, "added landing recoil")
		check(hair.offsets.hairBack == Vector2.ZERO, "hair did not return to neutral")
		print("HAIR %d FPS half response: %s" % [fps, half_times])
	for i in range(1, samples.size()):
		for key in Hair.LAYERS: check(samples[i][key].distance_to(samples[0][key]) < 0.01, "hair depends on FPS")
