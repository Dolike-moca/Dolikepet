extends RefCounted
## Vertical travel only. The host arbitrates dragging, menus and roaming.
const HOVER_SECONDS := 0.15
const INITIAL_GRAVITY := 2.0 # Window heights / second squared.
const GRAVITY := 14.0 # Late-fall acceleration, in window heights / second squared.
const ACCEL_RAMP_SECONDS := 0.65
const TERMINAL_SPEED := 5.4 # Window heights / second; ordinary drops keep accelerating.
var enabled := true
var state := "idle"
var age := 0.0
var speed := 0.0
var position := Vector2.ZERO
var extent := 0.0

func active() -> bool:
	return state != "idle"

func configure(value: bool) -> void:
	enabled = value
	if not enabled: cancel()

func cancel() -> void:
	state = "idle"
	age = 0.0
	speed = 0.0

func reposition(at: Vector2) -> void:
	position = at

func update(dt: float, at: Vector2, size: Vector2, area: Rect2,
		held: bool = false, paused: bool = false) -> Dictionary:
	var result := {"position": at, "move": false, "started": false, "landed": false}
	if not enabled or held:
		cancel()
		return result
	if paused or not is_finite(dt) or dt <= 0.0 or not at.is_finite() or size.y <= 0.0:
		return result
	var floor_y := maxf(area.position.y, area.end.y - size.y)
	if at.y >= floor_y - 0.5:
		if active():
			result.position = Vector2(at.x, floor_y)
			result.move = true
			result.landed = true
		cancel()
		return result
	if not active():
		state = "waiting"
		position = at
		age = 0.0
		speed = 0.0
		result.started = true
	elif position.distance_to(at) > 1.1:
		# Explicit resize/reposition and display changes must not restore an old Y.
		position = at
	if extent > 0.0 and extent != size.y: speed *= size.y / extent
	extent = size.y
	position.x = at.x
	var elapsed := minf(dt, 0.1)
	var steps := ceili(elapsed * 240.0)
	var h := elapsed / steps
	for i in steps:
		age += h
		if state == "waiting":
			if age + 0.000001 < HOVER_SECONDS: continue
			state = "falling"
		# A gentle start followed by a stronger pull makes the speed change visible.
		# Sample at the substep midpoint; pause/regrab share the existing age clock.
		var fall_time := maxf(0.0, age - HOVER_SECONDS - h * 0.5)
		var gravity := lerpf(INITIAL_GRAVITY, GRAVITY,
			smoothstep(0.0, ACCEL_RAMP_SECONDS, fall_time))
		var next_speed := minf(speed + gravity * extent * h, TERMINAL_SPEED * extent)
		position.y += (speed + next_speed) * 0.5 * h
		speed = next_speed
		result.move = true
		if position.y >= floor_y:
			position.y = floor_y
			result.landed = true
			cancel()
			break
	result.position = position
	return result

func pose(paused: bool = false) -> Dictionary:
	return {"fallActive": active(), "fallSpeed": speed / maxf(1.0, extent),
		"fallPaused": paused, "fallNormalize": smoothstep(0.0, HOVER_SECONDS, age) if active() else 0.0}
