extends RefCounted
## Secondary motion driven by the actual stride phase. Kept separate from
## mouse-follow springs so stopping cannot change the accepted resting pose.
## [horizontal px, vertical px, phase lag, stiffness, damping]
const LAYERS := {
	"hairFront": [7.0, 3.0, 0.10, 240.0, 24.0],
	"hairSide": [11.0, 4.5, 0.25, 160.0, 17.0],
	"hairBack": [16.0, 6.0, 0.50, 95.0, 13.0],
	"hairBraidNear": [8.0, 4.0, 0.35, 190.0, 15.0],
	"hairBraidFar": [7.0, 3.5, 0.52, 130.0, 13.0],
	"hairTuft": [12.0, 6.5, 0.14, 420.0, 14.0],
}
var offsets: Dictionary = {}
var speeds: Dictionary = {}
var previous_phase := 0.0
var previous_weight := 0.0
var initialized := false

func _init() -> void:
	for key in LAYERS:
		offsets[key] = Vector2.ZERO
		speeds[key] = Vector2.ZERO

func update(dt: float, phase: float, weight: float, sitting_amount: float) -> Dictionary:
	if not is_finite(dt) or dt <= 0.0:
		return offsets
	dt = minf(dt, 0.1)
	if not initialized:
		previous_phase = phase
		initialized = true
	var envelope := smoothstep(0.0, 1.0, weight) * (1.0 - smoothstep(0.0, 0.15, sitting_amount))
	var phase_delta := wrapf(phase - previous_phase, -PI, PI)
	var steps := ceili(dt * 240.0)
	var step := dt / steps
	for i in steps:
		var fraction := float(i + 1) / steps
		var sample_phase := previous_phase + phase_delta * fraction
		var sample_weight := lerpf(previous_weight, envelope, fraction)
		for key in LAYERS:
			var layer: Array = LAYERS[key]
			# Side sway alternates with the legs; vertical inertia follows each
			# footfall (twice per full stride). Roots remain fixed in the mesh.
			var target := Vector2(
				layer[0] * sin(sample_phase - layer[2]),
				layer[1] * cos(sample_phase * 2.0 - layer[2])) * sample_weight
			var offset: Vector2 = offsets[key]
			var speed: Vector2 = speeds[key]
			speed += (float(layer[3]) * (target - offset) - float(layer[4]) * speed) * step
			offset += speed * step
			# Safety limits also bound unusual interrupted or low-FPS frames.
			var bounded := offset.clamp(Vector2(-20, -12), Vector2(20, 12))
			if bounded.x != offset.x:
				speed.x = 0.0
			if bounded.y != offset.y:
				speed.y = 0.0
			offset = bounded
			if envelope == 0.0 and offset.length_squared() < 0.000001 and speed.length_squared() < 0.0001:
				offset = Vector2.ZERO
				speed = Vector2.ZERO
			offsets[key] = offset
			speeds[key] = speed
	previous_phase = phase
	previous_weight = envelope
	return offsets
