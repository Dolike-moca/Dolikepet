extends RefCounted
## Impact excites two damped springs above a planted waist. Screen travel stays
## entirely with the native body; this response never moves the support point.
var angle := 0.0
var angular_velocity := 0.0
var compression := 0.0
var compression_velocity := 0.0

func reset() -> void:
	angle = 0.0
	angular_velocity = 0.0
	compression = 0.0
	compression_velocity = 0.0

func start(impact: Dictionary) -> void:
	reset()
	var speed := clampf(float(impact.get("speed", 0.0)), 0.0, 7.0)
	var facing := -1.0 if float(impact.get("facing", 1.0)) < 0.0 else 1.0
	var lateral := clampf(float(impact.get("lateral_speed", 0.0)) * facing, -4.0, 4.0)
	var spin := clampf(float(impact.get("spin", 0.0)) * facing, -3.0, 3.0)
	var tilt := float(impact.get("angle", 0.0)) * facing
	# Local forward is left in the source drawing. Determine the first lean
	# from the stopped travel BEFORE friction, in character space, not screen
	# left/right. For a near-vertical fall, continue the existing lean/spin.
	var direction := -1.0
	if absf(lateral) >= 0.12:
		direction = signf(lateral)
	elif absf(tilt + spin * 0.08) > 0.035:
		direction = signf(tilt + spin * 0.08)
	var energy := sqrt(speed * speed + lateral * lateral * 0.65)
	var impulse := 2.8 * pow(energy / 4.045, 1.2)
	angular_velocity = direction * clampf(impulse + spin * direction * 0.28, 0.0, 4.0)
	compression_velocity = minf(speed * 0.38, 2.0)

static func spring(value: float, velocity: float, stiffness: float, damping: float, dt: float) -> Vector2:
	# Exact underdamped solution: preserve momentum through the zero crossing,
	# with the same response at 30/60/120 FPS, including pauses and frame jitter.
	var decay := damping * 0.5
	var frequency := sqrt(stiffness - decay * decay)
	var phase := frequency * dt
	var c := cos(phase)
	var s := sin(phase)
	var e := exp(-decay * dt)
	return Vector2(e * (value * c + (velocity + decay * value) / frequency * s),
		e * (velocity * c - (decay * velocity + stiffness * value) / frequency * s))

func update(dt: float) -> void:
	var angular := spring(angle, angular_velocity, 155.0, 7.4, dt)
	angle = angular.x
	angular_velocity = angular.y
	# A quicker, smaller vertical squash supports the rocking instead of
	# stretching the whole character or bouncing the seated skirt and boots.
	var axial := spring(compression, compression_velocity, 320.0, 14.0, dt)
	compression = axial.x
	compression_velocity = axial.y
