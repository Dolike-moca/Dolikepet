extends SceneTree
const Landing = preload("res://scripts/landing_motion.gd")
const Physics = preload("res://scripts/desktop_physics.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("LANDING: " + message)
func run() -> void:
	for fps in [30, 60, 120]:
		for hard in [false, true]:
			var landing = Landing.new()
			var sitting = Sitting.new()
			landing.start({"height": 1.2 if hard else 0.15, "speed": 4.4 if hard else 1.6})
			check(landing.state == ("hard" if hard else "soft"), "classification")
			var sit_count := 0
			var finish_count := 0
			var max_knee := 0.0
			var closed_handoff := false
			var previous_angle := 0.0
			var first_speed := 0.0
			var final_speed := 0.0
			var seated_at := -1.0
			var sway_sign := 0.0
			var sway_turns := 0
			var sway_early := 0.0
			var sway_late := 0.0
			for f in fps * 4:
				var event: Dictionary = landing.update(1.0 / fps)
				if event.sit: sitting.set_seated(true, event.sit_speed)
				sitting.update(1.0 / fps)
				if seated_at < 0.0 and sitting.amount >= 0.95: seated_at = landing.age
				var pose: Dictionary = landing.pose()
				sit_count += int(event.sit)
				finish_count += int(event.finished)
				max_knee = maxf(max_knee, pose.landingKnee)
				if hard and landing.age > 2.78 and landing.age < 2.83:
					closed_handoff = closed_handoff or (pose.dizzyAlpha == 0 and pose.dizzyOpenness == 0)
				if hard and landing.age > 0.4 and landing.age < 0.6: first_speed = (pose.dizzyAngle - previous_angle) * fps
				if hard and landing.age > 2.5 and landing.age < 2.6: final_speed = (pose.dizzyAngle - previous_angle) * fps
				previous_angle = pose.dizzyAngle
				if hard:
					if absf(pose.dizzyWobble) > 0.5:
						var current_sign := signf(pose.dizzyWobble)
						if sway_sign != 0.0 and current_sign != sway_sign: sway_turns += 1
						sway_sign = current_sign
					if landing.age < 1.2: sway_early = maxf(sway_early, absf(pose.dizzyWobble))
					if landing.age >= 1.8: sway_late = maxf(sway_late, absf(pose.dizzyWobble))
					if landing.age >= 2.68:
						check(pose.dizzyWobble == 0.0 and pose.dizzyUpperSway == 0.0, "head/shoulders did not settle before eye recovery")
				elif pose.dizzyWobble != 0.0 or pose.dizzyUpperSway != 0.0:
					check(false, "soft landing started dizzy sway")
				check(pose.landingKnee >= 0 and pose.landingKnee <= 1, "knee overshoot")
				if not hard: check(pose.dizzyAlpha == 0 and not event.sit, "soft landing became dizzy/seated")
			check(sit_count == int(hard) and finish_count == 1 and not landing.active(), "event repeated or state stuck")
			check(max_knee > 0.5, "missing knee absorption")
			if hard:
				check(sway_turns >= 4 and sway_turns <= 6, "dizzy head should sway repeatedly")
				check(sway_early > 10.0 and sway_late > 3.0 and sway_late < sway_early * 0.8, "dizzy sway missing or not fading")
				check(closed_handoff and first_speed > final_speed * 2 and final_speed > 0, "dizzy slowdown/closed-eye recovery")
				check(seated_at >= 0.28 and seated_at <= 0.35, "impact collapse should finish 95% in about 0.32s: " + str(seated_at))
		# The faster impact must not carry over into ordinary sitting or a regrab.
		var normal = Sitting.new()
		var interrupted = Sitting.new()
		normal.set_seated(true)
		interrupted.set_seated(true, Landing.HARD_SIT_SPEED)
		for f in fps / 2:
			normal.update(1.0 / fps)
			interrupted.update(1.0 / fps)
		check(normal.amount > 0.93 and normal.amount < 0.95, "ordinary sit tempo changed")
		normal.amount = interrupted.amount
		normal.velocity = interrupted.velocity
		normal.set_seated(false)
		interrupted.set_seated(false)
		for f in fps:
			normal.update(1.0 / fps)
			interrupted.update(1.0 / fps)
		check(absf(normal.amount - interrupted.amount) < 0.000001, "impact speed leaked into standing")
		interrupted.set_seated(true)
		check(interrupted.sit_speed == 1.0, "ordinary sit did not reset impact entry speed")
	var landing = Landing.new()
	landing.start({"height": 0.1, "speed": 5.0})
	check(landing.state == "hard", "downward throw from low height ignored")
	landing.update(0.1)
	var before: Dictionary = landing.pose()
	landing.update(1.0, true)
	check(landing.pose() == before, "paused animation advanced")
	landing.cancel()
	check(not landing.active() and landing.pose().dizzyAlpha == 0 and landing.pose().dizzyWobble == 0.0 \
		and landing.pose().dizzyUpperSway == 0.0, "regrab did not clear dizziness")
	# Native floor contacts, actual gravity and impulses; one event per flight.
	for extent in [240.0, 420.0, 800.0]:
		for height in [0.15, 1.2]:
			var physics = Physics.new()
			root.add_child(physics)
			var area := Rect2(-2200, -1000, 2200, 3000)
			physics.set_geometry(Vector2.ONE * extent, area, Vector2(0.43, 0.25) * extent)
			var at := Vector2(-1400, area.end.y - extent * (1.0 + height))
			physics.reposition(at)
			var impacts := 0
			var measured := {}
			for frame in 480:
				var result: Dictionary = physics.update(1.0 / 120, at, physics.size, area)
				if result.move: at = result.position
				if not result.impact.is_empty():
					impacts += 1
					measured = result.impact
				await physics_frame
				await process_frame
			check(impacts == 1, "floor event repeated/missing " + str([extent, height, impacts]))
			if not measured.is_empty():
				landing.cancel()
				landing.start(measured)
				check(landing.state == ("hard" if height > 1 else "soft"), "native classification wrong " + str(measured))
				check(measured.speed > 0.5, "impact velocity sampled after stop")
			physics.free()
	print("LANDING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
