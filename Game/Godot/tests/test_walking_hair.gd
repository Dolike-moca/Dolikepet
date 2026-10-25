extends SceneTree
const Hair = preload("res://scripts/walking_hair.gd")
var failures := 0
var checks := 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("WALK HAIR: " + label)

func _initialize() -> void:
	var tracks := []
	var peaks := {}
	for fps in [30, 60, 120]:
		var hair := Hair.new()
		var snapshots := []
		var bounded := true
		for frame in fps * 8:
			var time: float = float(frame + 1) / fps
			var weight := smoothstep(0.0, 0.3, time) * (1.0 - smoothstep(4.0, 4.25, time))
			var values := hair.update(1.0 / fps, time * TAU * 1.7, weight, 0.0)
			for key in Hair.LAYERS:
				var point: Vector2 = values[key]
				bounded = bounded and point.is_finite() and absf(point.x) <= 20 and absf(point.y) <= 12
				if fps == 60 and time > 1 and time < 4:
					var peak: Vector2 = peaks.get(key, Vector2.ZERO)
					peaks[key] = Vector2(maxf(peak.x, absf(point.x)), maxf(peak.y, absf(point.y)))
			if (frame + 1) % fps == 0:
				snapshots.append(values.duplicate())
			if frame + 1 == fps * 5:
				# Inertia settles after the feet stop; it is not reset in one frame.
				_check(values.hairTuft.length() < 0.3, "tuft takes too long to settle")
		_check(bounded, "unsafe or nonfinite offsets")
		for value in hair.offsets.values():
			_check(value == Vector2.ZERO, "resting pose did not restore exactly")
		var saved := hair.offsets.duplicate()
		hair.update(0.0, 100.0, 1.0, 0.0)
		hair.update(NAN, 100.0, 1.0, 0.0)
		_check(hair.offsets == saved, "paused frames advanced the springs")
		tracks.append(snapshots)
	for n in 8:
		for key in Hair.LAYERS:
			_check(tracks[0][n][key].distance_to(tracks[2][n][key]) < 0.15
				and tracks[1][n][key].distance_to(tracks[2][n][key]) < 0.15, "refresh-rate dependent motion")
	_check(peaks.hairTuft.y > 6.0 and peaks.hairTuft.y > peaks.hairFront.y * 2.0, "tuft lacks distinct bounce")
	_check(peaks.hairBack.x > peaks.hairFront.x * 1.3, "back hair lacks separate sway")
	var hair := Hair.new()
	for i in 180:
		hair.update(1.0 / 60, i * TAU * 1.7 / 60, 1.0, 1.0)
	_check(hair.offsets.hairTuft == Vector2.ZERO, "seated gait must stay quiet")
	# Sudden interruption (drag/menu) should retain inertia on the next frame.
	for i in 50:
		hair.update(1.0 / 60, i * TAU * 1.7 / 60, 1.0, 0.0)
	var before: Vector2 = hair.offsets.hairTuft
	hair.update(1.0 / 60, 50 * TAU * 1.7 / 60, 0.0, 0.0)
	_check(hair.offsets.hairTuft != Vector2.ZERO
		and before.distance_to(hair.offsets.hairTuft) < 4.0, "interruption snapped the tuft")
	print("WALK HAIR: %d checks, %d failures; peaks %s" % [checks, failures, peaks])
	quit(0 if failures == 0 else 1)
