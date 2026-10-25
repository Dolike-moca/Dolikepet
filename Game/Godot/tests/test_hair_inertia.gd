extends SceneTree
const Inertia = preload("res://scripts/hair_inertia.gd")
var failures := 0
var checks := 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("HAIR INERTIA: " + label)

func _travel(t: float, speed: float) -> float:
	return clampf(t - 0.5, 0.0, 0.75) * speed

func _simulate(speed: float, fps: int, extent: float = 420.0, vertical: bool = false) -> Dictionary:
	var hair := Inertia.new()
	hair.update(1.0 / fps, Vector2.ZERO, extent)
	var samples := []
	var trailing := {}
	var rebound := {}
	var peak_time := {}
	var bounded := true
	var tuft_return := 0.0
	for key in Inertia.LAYERS:
		trailing[key] = 0.0
		rebound[key] = 0.0
		peak_time[key] = 0.0
	for frame in fps * 8:
		var t := float(frame + 1) / fps
		var p := Vector2(_travel(t, speed) * extent, 0.0)
		if vertical:
			p = Vector2(0, p.x)
		var values := hair.update(1.0 / fps, p, extent)
		for key in Inertia.LAYERS:
			var point: Vector2 = values[key]
			var layer: Array = Inertia.LAYERS[key]
			bounded = bounded and point.is_finite() and absf(point.x) <= layer[5] and absf(point.y) <= layer[6]
			var v: float = point.y if vertical else point.x
			if t < 1.25:
				trailing[key] = minf(trailing[key], v)
			elif v > rebound[key]:
				rebound[key] = v
				peak_time[key] = t
			if key == "hairTuft" and t > 1.6:
				tuft_return = minf(tuft_return, v)
		if (frame + 1) % (fps / 10) == 0:
			samples.append(values.duplicate())
	_check(bounded, "bounded finite motion")
	for offset in hair.offsets.values():
		_check(offset == Vector2.ZERO, "failed to restore neutral after settling")
	return {"samples": samples, "trail": trailing, "rebound": rebound, "peakTime": peak_time, "tuftReturn": tuft_return}

func _initialize() -> void:
	var slow := _simulate(0.15, 60)
	var fast := _simulate(2.4, 60)
	print("SLOW: trail=", slow.trail, " rebound=", slow.rebound)
	print("FAST: trail=", fast.trail, " rebound=", fast.rebound, " peakTime=", fast.peakTime, " tuftReturn=", fast.tuftReturn)
	_check(fast.trail.hairBack < slow.trail.hairBack * 4.0, "fast travel lacks stronger trailing")
	_check(fast.rebound.hairBack > 5.0 and fast.rebound.hairBack > slow.rebound.hairBack * 4.0,
		"fast stop lacks visible reverse swing")
	_check(fast.peakTime.hairBack > fast.peakTime.hairFront, "layers lack different catch-up timing")
	_check(fast.tuftReturn < -0.5, "tuft lacks smaller return bounce")
	var large := _simulate(2.4, 60, 840.0)
	var coarse := _simulate(2.4, 30)
	var fine := _simulate(2.4, 120)
	var worst := 0.0
	for i in fast.samples.size():
		for key in Inertia.LAYERS:
			_check(fast.samples[i][key].distance_to(large.samples[i][key]) < 0.001, "size changed normalized response")
			worst = maxf(worst, coarse.samples[i][key].distance_to(fine.samples[i][key]))
	# The abrupt stop at 1.25 s falls between 30-FPS samples. Allow less than
	# one display pixel at normal size for that unavoidable sampling difference.
	_check(worst < 3.0, "refresh-rate response diverged")
	var vertical := _simulate(2.4, 60, 420, true)
	_check(vertical.trail.hairBack < -2.0 and vertical.rebound.hairBack > 2.0, "vertical movement lacks inertia")
	var hair := Inertia.new()
	hair.update(1.0 / 60, Vector2.ZERO, 420)
	hair.update(1.0 / 60, Vector2(2000, 2000), 420)
	hair.update(1.0 / 60, Vector2(2100, 2100), 720)
	hair.update(1.0, Vector2(2300, 2300), 720)
	hair.update(1.0 / 60, Vector2(2400, 2400), 720, true)
	_check(hair.offsets.hairBack == Vector2.ZERO, "resize/teleport/resume generated a fake impulse")
	var saved := hair.offsets.duplicate()
	hair.update(0.0, Vector2(2500, 2500), 720)
	hair.update(NAN, Vector2.ZERO, 720)
	_check(hair.offsets == saved, "invalid/paused frame moved hair")
	print("HAIR INERTIA: %d checks, %d failures; 30/120 FPS max difference %.3f model px" % [checks, failures, worst])
	quit(0 if failures == 0 else 1)
