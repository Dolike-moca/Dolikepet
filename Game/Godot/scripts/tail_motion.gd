extends RefCounted
## Bend the existing Cubism tail along its curved centreline, preserving its
## length and cross-section. Motion is independent of blink/roaming randomness.
const MESH_ID := "ArtMesh28"
const Secondary = preload("res://scripts/secondary_deformation.gd")
const ORIGIN := Vector2(1024, 1024)
const SEGMENTS := 24

var rng := RandomNumberGenerator.new()
var held_rng := RandomNumberGenerator.new()
var time := 0.0
var next_sway := 0.0
var sway_start := -10.0
var sway_duration := 4.5
var amplitude := 0.0
var angle := 0.0
var velocity := 0.0
var tip_angle := 0.0
var tip_velocity := 0.0
var automatic := true # Freeze for deterministic geometry inspection.
var was_held := false
var held_mix := 0.0
var group_age := 0.0
var group_cycles := 2
var group_frequency := 2.2
var group_duration := 1.0
var group_rest := 0.2
var group_amplitude := 0.0
var group_count := 0
var centreline := PackedVector2Array()
var bindings := PackedFloat32Array()

func _init() -> void:
	rng.randomize()
	held_rng.randomize()
	next_sway = rng.randf_range(0.8, 2.0)
	# PSD tail: concealed root at the hip, rounded belly, then the upturned tip.
	var a := Vector2(900, 1485) - ORIGIN
	var b := Vector2(1120, 1650) - ORIGIN
	var c := Vector2(1440, 1600) - ORIGIN
	var d := Vector2(1550, 1370) - ORIGIN
	for i in range(SEGMENTS + 1):
		var t := float(i) / SEGMENTS
		centreline.append(a.bezier_interpolate(b, c, d, t))

func setup(neutral: PackedVector2Array) -> void:
	bindings.clear()
	for point in neutral:
		var nearest := INF
		var at := 0.0
		for i in SEGMENTS:
			var edge := centreline[i + 1] - centreline[i]
			var along := clampf((point - centreline[i]).dot(edge) / edge.length_squared(), 0.0, 1.0)
			var distance := point.distance_squared_to(centreline[i] + edge * along)
			if distance < nearest:
				nearest = distance
				at = i + along
		bindings.append(at)

static func _spring(value: float, speed: float, target: float, omega: float, dt: float) -> Vector2:
	var offset := value - target
	var impulse := speed + omega * offset
	var decay := exp(-omega * dt)
	return Vector2(target + (offset + impulse * dt) * decay,
		(speed - omega * impulse * dt) * decay)

func _start_group() -> void:
	group_age = 0.0
	group_cycles = held_rng.randi_range(2, 3)
	group_frequency = held_rng.randf_range(2.1, 2.5)
	group_duration = group_cycles / group_frequency
	group_rest = held_rng.randf_range(0.15, 0.30)
	var direction := -signf(group_amplitude) if group_amplitude != 0.0 else (-1.0 if held_rng.randf() < 0.5 else 1.0)
	group_amplitude = deg_to_rad(held_rng.randf_range(32.0, 38.0)) * direction
	group_count += 1

func update(dt: float, walk_phase: float, walk_weight: float, seated: float, held: bool = false, paused: bool = false, limp := 0.0, limp_sway := 0.0) -> void:
	if not automatic or paused or not is_finite(dt) or dt <= 0.0:
		return
	if held and not was_held: _start_group()
	was_held = held
	dt = minf(dt, 0.1)
	var steps := ceili(dt * 120.0)
	var step := dt / steps
	for i in steps:
		time += step
		held_mix = lerpf(held_mix, 1.0 if held else 0.0, 1.0 - exp(-(24.0 if held else 14.0) * step))
		if not held and held_mix < 0.0001: held_mix = 0.0
		if held or held_mix > 0.0:
			group_age += step
			if held and group_age >= group_duration + group_rest:
				var remainder := group_age - group_duration - group_rest
				_start_group()
				group_age = remainder
		if time >= next_sway:
			sway_start = time
			sway_duration = rng.randf_range(3.6, 5.6)
			amplitude = deg_to_rad(rng.randf_range(19.0, 24.0)) * (-1.0 if rng.randf() < 0.5 else 1.0)
			next_sway = time + sway_duration + rng.randf_range(1.8, 4.5)
		var u := clampf((time - sway_start) / sway_duration, 0.0, 1.0)
		# A complete soft sweep, then a quiet pause; no constant metronomic wag.
		var envelope := pow(sin(PI * u), 2.0) if u < 1.0 else 0.0
		var relaxed := lerpf(1.0, 0.58, clampf(seated, 0.0, 1.0))
		var target := amplitude * sin(TAU * u) * envelope * relaxed
		# A small balancing curve while walking, slower than the individual steps.
		target += deg_to_rad(-3.0 + 2.3 * sin(walk_phase * 0.5 - 0.6)) * clampf(walk_weight, 0.0, 1.0)
		# Two or three fast sweeps, then a short breather. Gate the whole burst
		# smoothly, and keep the spring states intact when released or regrabbed.
		var burst := smoothstep(0.0, 0.10, group_age) * (1.0 - smoothstep(group_duration - 0.12, group_duration, group_age))
		var phase := TAU * group_frequency * minf(group_age, group_duration)
		# Carry the tail slightly upward when suspended. The inward curl has a
		# wider arc than the outward sweep, leaving room for the whole-body tilt.
		var held_target := (group_amplitude * sin(phase) * 0.60 - absf(group_amplitude) * 0.40) * burst
		target = lerpf(target, held_target, held_mix)
		if limp>0.0: target = lerpf(target,deg_to_rad(63.0)+limp_sway,limp)
		var spring := _spring(angle, velocity, target, lerpf(5.0, 34.0, held_mix), step)
		angle = spring.x
		velocity = spring.y
		var tip_target := angle * 0.55 + deg_to_rad(3.2) * sin(TAU * 2.0 * u) * envelope * relaxed
		tip_target = lerpf(tip_target, angle * 0.52 + group_amplitude * 0.12 * sin(phase - 0.6) * burst, held_mix)
		if limp>0.0: tip_target = lerpf(tip_target,deg_to_rad(28.0)+limp_sway*0.7,limp)
		spring = _spring(tip_angle, tip_velocity, tip_target, lerpf(3.8, 21.0, held_mix), step)
		tip_angle = spring.x
		tip_velocity = spring.y

func _bend_at(t: float) -> float:
	# The first section stays attached under the skirt. Bending spreads along
	# the tail, while its last section has a separate, slower response.
	return angle * smoothstep(0.12, 0.82, t) + tip_angle * smoothstep(0.52, 1.0, t)

func deform_points(raw: PackedVector2Array, body: Transform2D) -> PackedVector2Array:
	if absf(angle) < 0.0000001 and absf(tip_angle) < 0.0000001:
		return raw.duplicate()
	var bent := PackedVector2Array([centreline[0]])
	for i in SEGMENTS:
		var edge := centreline[i + 1] - centreline[i]
		bent.append(bent[i] + edge.rotated(_bend_at((i + 0.5) / SEGMENTS)))
	var inverse := body.affine_inverse()
	var points := raw.duplicate()
	for n in points.size():
		var at := float(bindings[n])
		var i := mini(int(at), SEGMENTS - 1)
		var along := at - i
		var centre := centreline[i].lerp(centreline[i + 1], along)
		var offset := inverse * raw[n] - centre
		points[n] = body * (bent[i].lerp(bent[i + 1], along) + offset.rotated(_bend_at(at / SEGMENTS)))
	return points

func apply(node: MeshInstance2D, raw: PackedVector2Array, body: Transform2D) -> void:
	Secondary.write_points(node, deform_points(raw, body))
