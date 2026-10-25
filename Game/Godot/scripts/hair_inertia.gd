extends RefCounted
## Screen-space root motion, normalized by pet size. An underdamped spring
## responds to acceleration; a little velocity drag keeps fast travel legible.
## [omega, slow damping ratio, fast damping ratio, inertia, drag, max X, max Y]
const LAYERS := {
	"hairFront": [13.5, 1.0, 0.65, 75.0, 2.5, 22.0, 12.0],
	"hairSide": [11.5, 0.95, 0.50, 110.0, 4.5, 32.0, 18.0],
	"hairBack": [8.8, 0.92, 0.44, 155.0, 6.5, 45.0, 24.0],
	"hairBraidNear": [10.8, 0.90, 0.48, 120.0, 4.0, 30.0, 18.0],
	"hairBraidFar": [9.8, 0.92, 0.50, 115.0, 4.2, 28.0, 18.0],
	"hairTuft": [18.0, 0.55, 0.24, 175.0, 5.0, 40.0, 22.0],
}
var offsets: Dictionary = {}
var speeds: Dictionary = {}
var initialized := false
var last_anchor := Vector2.ZERO
var last_extent := 0.0
var filtered_velocity := Vector2.ZERO
var excitement := 0.0

func _init() -> void:
	for key in LAYERS:
		offsets[key] = Vector2.ZERO
		speeds[key] = Vector2.ZERO

func update(dt: float, anchor: Vector2, extent: float, reset_sample: bool = false) -> Dictionary:
	if not is_finite(dt) or dt <= 0.0 or not anchor.is_finite() or not is_finite(extent) or extent <= 0.0:
		return offsets
	# Resizing, teleports and resume must not look like a violent drag. Preserve
	# the springs, but rebase their motion sample without an artificial impulse.
	var rebase := reset_sample or not initialized or dt > 0.12 \
		or absf(extent - last_extent) > 0.5 or anchor.distance_to(last_anchor) > extent * 0.85
	var elapsed := minf(dt, 0.1)
	var measured := Vector2.ZERO
	if rebase:
		filtered_velocity = Vector2.ZERO
	else:
		measured = ((anchor - last_anchor) / extent / elapsed).limit_length(6.0)
	last_anchor = anchor
	last_extent = extent
	initialized = true
	# Keep the low damping briefly after fast motion ends, allowing a visible
	# return swing instead of becoming critically damped at the moment of release.
	var steps := ceili(elapsed * 240.0)
	var step := elapsed / steps
	for i in steps:
		var old_velocity := filtered_velocity
		filtered_velocity = old_velocity.lerp(measured, 1.0 - exp(-22.0 * step))
		var acceleration := ((filtered_velocity - old_velocity) / step).limit_length(25.0)
		excitement = maxf(excitement * exp(-step / 0.65),
			smoothstep(0.35, 2.2, filtered_velocity.length()))
		for key in LAYERS:
			var layer: Array = LAYERS[key]
			var omega: float = layer[0]
			var damping := 2.0 * omega * lerpf(layer[1], layer[2], excitement)
			var target := -filtered_velocity * float(layer[4])
			var force := -acceleration * float(layer[3])
			force.y *= 0.70
			var offset: Vector2 = offsets[key]
			var speed: Vector2 = speeds[key]
			speed += (omega * omega * (target - offset) - damping * speed + force) * step
			offset += speed * step
			var limit := Vector2(layer[5], layer[6])
			var bounded := offset.clamp(-limit, limit)
			if bounded.x != offset.x:
				speed.x = 0.0
			if bounded.y != offset.y:
				speed.y = 0.0
			offset = bounded
			if filtered_velocity.length_squared() < 0.000001 and acceleration.length_squared() < 0.0001 \
					and offset.length_squared() < 0.000001 and speed.length_squared() < 0.0001:
				offset = Vector2.ZERO
				speed = Vector2.ZERO
			offsets[key] = offset
			speeds[key] = speed
	return offsets
