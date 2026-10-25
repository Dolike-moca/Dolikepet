extends RefCounted
## Independent root-fixed tip response. Values are original PSD pixels.
## [frequency, damping ratio, upward tip displacement, slight lateral curl]
const LAYERS := {
	"hairFront": [18.0, 1.0, 18.0, 0.0],
	"hairSide": [12.8, 0.95, 48.0, 3.0],
	"hairBraidNear": [10.5, 1.0, 66.0, -3.0],
	"hairBraidFar": [9.2, 1.0, 51.0, 2.0],
	"hairBack": [7.8, 0.95, 120.0, 6.0],
	"hairTuft": [20.0, 0.78, 22.0, 10.0],
}
var offsets: Dictionary = {}
var velocities: Dictionary = {}

func _init() -> void:
	for key in LAYERS:
		offsets[key] = Vector2.ZERO
		velocities[key] = Vector2.ZERO

func update(dt: float, speed: float, active: bool, paused: bool = false) -> Dictionary:
	if paused or not is_finite(dt) or dt <= 0.0: return offsets
	var elapsed := minf(dt, 0.1)
	var strength := smoothstep(0.0, 2.6, maxf(0.0, speed)) if active else 0.0
	var steps := ceili(elapsed * 240.0)
	var h := elapsed / steps
	for i in steps:
		for key in LAYERS:
			var layer: Array = LAYERS[key]
			var offset: Vector2 = offsets[key]
			var velocity: Vector2 = velocities[key]
			if not active:
				# No landing choreography yet: settle without a new recoil impulse.
				offset *= exp(-h * 14.0)
				velocity = Vector2.ZERO
			else:
				var target := Vector2(layer[3], -layer[2]) * strength
				var omega: float = layer[0]
				velocity += (omega * omega * (target - offset) - 2.0 * omega * layer[1] * velocity) * h
				offset += velocity * h
			if offset.length_squared() < 0.000001 and velocity.length_squared() < 0.0001:
				offset = Vector2.ZERO
				velocity = Vector2.ZERO
			offsets[key] = offset
			velocities[key] = velocity
	return offsets
