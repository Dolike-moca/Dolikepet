extends SceneTree
const Physics = preload("res://scripts/desktop_physics.gd")
var motion
var at := Vector2.ZERO
var checks := 0
var failures := 0
var landed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 25: printerr("NATIVE PHYSICS: " + message)
func setup(extent: float = 420.0, rect: Rect2 = Rect2(0, 0, 1920, 1080)) -> void:
	if is_instance_valid(motion):
		motion.free()
	motion = Physics.new()
	root.add_child(motion)
	motion.set_geometry(Vector2.ONE * extent, rect, Vector2(0.43, 0.25) * extent)
	at = rect.position + Vector2(300, 60)
	landed = false
	motion.reposition(at)
func step(count: int = 1, pause: bool = false) -> void:
	for i in count:
		var r: Dictionary = motion.update(1.0 / 120, at, motion.size, motion.area, motion.state == "held", pause)
		if r.move: at = r.position
		landed = landed or r.landed
		await physics_frame
		await process_frame
		check(motion.body.position.is_finite() and motion.body.linear_velocity.is_finite(), "nonfinite state")
		check(absf(motion.body.rotation) < deg_to_rad(28), "angular stop escaped")
		if motion.body.floor_locked:
			check(absf(motion.body.position.x - motion.body.floor_x) < 0.05, "floor support slid sideways")
			check(absf(motion.body.linear_velocity.x) < 0.1, "floor retained horizontal momentum")
func throw_velocity(value: Vector2, spin: float = 0.0) -> void:
	motion.begin(at, at + motion.anchor, 1.0)
	motion.body.linear_velocity = value
	motion.body.angular_velocity = spin
	motion.release()
func run() -> void:
	setup()
	throw_velocity(Vector2(500, -700), 0.8)
	check(motion.body.linear_velocity == Vector2(500, -700), "release changed linear momentum")
	check(is_equal_approx(motion.body.angular_velocity, 0.8), "release changed angular momentum")
	var before_y := at.y
	await step(10)
	check(at.y < before_y, "upward throw did not rise")
	await step(35)
	check(motion.body.linear_velocity.y > 0, "gravity did not turn upward throw downward")
	await step(500)
	check(landed and not motion.active(), "floor failed to settle: " + motion.state + str(motion.body.linear_velocity))
	check(absf(at.y + motion.size.y - motion.area.end.y) < 1.5, "floor handoff moved foot height")
	var resting_x := at.x
	motion.begin(at, at + motion.anchor, 1.0)
	motion.set_pointer(at + motion.anchor + Vector2(150, -100))
	await step(90)
	check(not motion.body.floor_locked and at.x > resting_x + 80.0, "regrab did not release floor support")
	setup()
	throw_velocity(Vector2.ZERO)
	await step(12)
	var first: float = motion.body.linear_velocity.y
	await step(12)
	var second: float = motion.body.linear_velocity.y
	check(first > 200 and second > first * 1.8, "clear constant-gravity acceleration missing")
	var saved_at: Vector2 = motion.body.position
	var saved_v: Vector2 = motion.body.linear_velocity
	var saved_w: float = motion.body.angular_velocity
	await step(40, true)
	check(motion.body.position.distance_to(saved_at) < 0.01, "pause moved body " + str(motion.body.position - saved_at))
	await step(1)
	check(motion.body.linear_velocity.distance_to(saved_v) < 40, "resume lost velocity")
	check(absf(motion.body.angular_velocity - saved_w) < 0.1, "resume lost spin")
	# Catch an active trajectory without teleporting or discarding its velocity.
	saved_at = motion.body.position
	saved_v = motion.body.linear_velocity
	motion.begin(at, saved_at + Vector2(-60, 0), -1)
	check(motion.body.position == saved_at and motion.body.linear_velocity == saved_v, "regrab reset body")
	motion.set_pointer(saved_at + Vector2(130, -100))
	await step(90)
	check(motion.body.position.distance_to(saved_at) > 60, "native spring failed to pull")
	check(motion.body.spring_gap.length() < 45, "spring did not catch up")
	# Both screen sides and the top: genuine native contact changes direction.
	for direction in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)]:
		setup()
		motion.configure(false)
		at = Vector2(720, 300)
		motion.reposition(at)
		throw_velocity(direction * 5000)
		var bounced := false
		for frame in 100:
			await step()
			if motion.body.linear_velocity.dot(direction) < -50: bounced = true
		check(bounced and motion.body.impact_count > 0, "no native rebound " + str(direction))
		check(at.x > -420 and at.x < 1920 and at.y > -420, "CCD left monitor")
	# High speed corner contacts and all supported pet sizes, negative monitors.
	for extent in [240.0, 420.0, 800.0]:
		setup(extent, Rect2(-1920, -200, 1920, 1440))
		throw_velocity(Vector2(-4200, -2700), 1.5)
		var minimum_vy := 0.0
		var touched_floor := false
		for frame in 650:
			await step()
			if motion.body.grounded: touched_floor = true
			if touched_floor: minimum_vy = minf(minimum_vy, motion.body.linear_velocity.y)
			check(at.x > -1920 - extent and at.x < 0 and at.y > -200 - extent, "corner tunneled")
		check(touched_floor and not motion.active(), "scaled/negative-monitor floor did not settle " + str([extent, motion.body.rotation, motion.body.angular_velocity, motion.body.linear_velocity, at]))
		check(minimum_vy > -extent * 0.7, "floor bounced strongly")
	# With gravity disabled, a release still retains inertia and then stops.
	setup()
	motion.configure(false)
	throw_velocity(Vector2(220, 80), 0.4)
	await step(550)
	check(not motion.active() and at.y < 600, "floating mode failed to stop in midair")
	motion.free()
	print("NATIVE PHYSICS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
