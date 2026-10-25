extends RefCounted
## Grabbing and suspended motion. Release stays in place and eases to neutral.
var state := "idle"
var time := 0.0
var age := 0.0
var position := Vector2.ZERO
var previous_position := Vector2.ZERO
var velocity := Vector2.ZERO
var tilt := 0.0
var tilt_speed := 0.0
var bend := 0.0
var bend_speed := 0.0
var stretch := 0.0
var stretch_speed := 0.0
var hang := 0.0
var face := 0.0
var facing := 1.0
var facing_target := 1.0
var follow_position := Vector2.ZERO
var follow_velocity := Vector2.ZERO
var pointer_previous := Vector2.ZERO
var pull := Vector2.ZERO

func active() -> bool:
	return state != "idle"

func begin(at: Vector2, facing_scale: float = 1.0) -> void:
	state = "held"
	age = 0.0
	position = at
	previous_position = at
	velocity = Vector2.ZERO
	follow_position = at
	follow_velocity = Vector2.ZERO
	pointer_previous = at
	pull = Vector2.ZERO
	facing = facing_scale
	facing_target = 1.0 if facing_scale >= 0.0 else -1.0

func release() -> void:
	if state != "held":
		return
	age = 0.0
	state = "recovering"
	follow_velocity = Vector2.ZERO
	pull = Vector2.ZERO

func reposition(at: Vector2) -> void:
	position = at
	previous_position = at
	velocity = Vector2.ZERO
	follow_position = at
	follow_velocity = Vector2.ZERO
	pointer_previous = at
	pull = Vector2.ZERO

func cancel() -> void:
	state = "idle"
	hang = 0.0
	face = 0.0
	tilt = 0.0
	tilt_speed = 0.0
	bend = 0.0
	bend_speed = 0.0
	stretch = 0.0
	stretch_speed = 0.0
	follow_velocity = Vector2.ZERO
	pull = Vector2.ZERO

static func pull_stiffness(distance: float) -> float:
	# Progressive spring: force and stiffness both rise as the gap stretches.
	return lerpf(144.0, 576.0, smoothstep(0.04, 0.65, distance))

func follow_pointer(dt: float, target: Vector2, size: Vector2) -> Vector2:
	if state != "held" or not is_finite(dt) or dt <= 0.0 or size.y <= 0.0:
		return follow_position
	var elapsed := minf(dt, 0.1)
	var steps := ceili(elapsed * 240.0)
	var h := elapsed / steps
	for i in steps:
		var sample := pointer_previous.lerp(target, float(i + 1) / steps)
		var gap := sample - follow_position
		var stiffness := pull_stiffness(gap.length() / size.y)
		var damping := 2.0 * sqrt(stiffness) * 0.78
		follow_velocity += (gap * stiffness - follow_velocity * damping) * h
		follow_position += follow_velocity * h
	pointer_previous = target
	pull = (target - follow_position) / size.y
	return follow_position

func update(dt: float, at: Vector2, size: Vector2, paused: bool = false) -> bool:
	if paused or not is_finite(dt) or dt <= 0.0 or size.y <= 0.0:
		return false
	var elapsed := minf(dt, 0.1)
	time += elapsed
	age += elapsed
	var measured := Vector2.ZERO
	if state == "held":
		position = at
		pull = (pointer_previous - at) / size.y
		if dt <= 0.12 and at.distance_to(previous_position) < size.y * 0.85:
			measured = ((at - previous_position) / size.y / elapsed).limit_length(5.0)
		previous_position = at
	var steps := ceili(elapsed * 240.0)
	var h := elapsed / steps
	for i in steps:
		velocity = velocity.lerp(measured, 1.0 - exp(-18.0 * h))
		# The same stretched gap drives position, lean and torso strain. A fixed
		# distant pointer still pulls harder; mouse speed is not the driver.
		var target := deg_to_rad(20.0 * tanh(pull.x * 4.0)) if state == "held" else 0.0
		tilt_speed += ((target - tilt) * 80.0 - tilt_speed * (7.5 if state == "held" else 16.0)) * h
		tilt += tilt_speed * h
		if absf(tilt) > deg_to_rad(22.0):
			tilt = clampf(tilt, deg_to_rad(-22.0), deg_to_rad(22.0))
			if tilt * tilt_speed > 0.0: tilt_speed = 0.0
		var bend_target := deg_to_rad(5.0 * tanh(pull.x * 5.0)) if state == "held" else 0.0
		bend_speed += ((bend_target - bend) * 48.0 - bend_speed * (7.0 if state == "held" else 14.0)) * h
		bend += bend_speed * h
		# Brief pickup strain, followed by a lighter suspended shape. Only the
		# torso below the collar deforms; upward pulling adds extra give.
		var pickup := 0.055 * exp(-pow((age - 0.14) / 0.13, 2.0))
		var stretch_target := 0.0
		if state == "held":
			stretch_target = clampf(0.032 + pickup - 0.06 * tanh(pull.y * 5.0)
				+ 0.025 * tanh(pull.length() * 3.0), -0.025, 0.135)
		stretch_speed += ((stretch_target - stretch) * 120.0 - stretch_speed * 12.0) * h
		stretch += stretch_speed * h
		hang = lerpf(hang, 1.0 if state == "held" else 0.0, 1.0 - exp(-12.0 * h))
		face = move_toward(face, 1.0 if state == "held" else 0.0, h * 10.0)
		facing = move_toward(facing, facing_target, h * 6.0)
	if state != "held" and hang < 0.0001 and absf(tilt) < 0.0001 and absf(tilt_speed) < 0.001 \
			and absf(bend) < 0.0001 and absf(bend_speed) < 0.001 and absf(stretch) < 0.0001:
		var finished := state == "recovering"
		state = "idle"
		hang = 0.0
		tilt = 0.0
		tilt_speed = 0.0
		bend = 0.0
		bend_speed = 0.0
		stretch = 0.0
		stretch_speed = 0.0
		return finished
	return false

func pose() -> Dictionary:
	return {"dragHang": hang, "dragFace": face, "dragTilt": tilt,
		"dragBend": bend, "dragStretch": stretch, "dragSwingSpeed": tilt_speed,
		"dragPull": pull,
		"dragTime": time, "dragHeld": state == "held"}
