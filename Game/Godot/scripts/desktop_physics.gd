extends Node2D
## One native body owns both the held and released phases. Window coordinates
## are a presentation of that body, never an extra position integrator.
const Body = preload("res://scripts/pet_rigid_body.gd")
var body = Body.new()
var enabled := true
var state := "idle"
var size := Vector2.ZERO
var area := Rect2()
var anchor := Vector2.ZERO
var position_at := Vector2.ZERO
var physical_facing := 1.0
var walls: Array[StaticBody2D] = []
var paused := false
var saved_velocity := Vector2.ZERO
var saved_spin := 0.0
var quiet_time := 0.0
var started_pending := false
var landed_pending := false
var was_grounded := false
var initialized := false
var floor_sequence_seen := 0
var flight_consumed := true
var flight_height := 0.0

func _ready() -> void:
	body.mass = 1.0
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.max_contacts_reported = 8
	body.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	body.freeze = true
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.0
	body.physics_material_override = material
	add_child(body)
	for i in 4:
		var wall := StaticBody2D.new()
		wall.set_meta("floor", i == 3)
		wall.set_meta("boundary", ["left","right","top","bottom"][i])
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		wall.add_child(shape)
		var surface := PhysicsMaterial.new()
		surface.bounce = 0.0 if i == 3 else 0.55
		surface.friction = 1.0 if i == 3 else 0.02
		wall.physics_material_override = surface
		add_child(wall)
		walls.append(wall)

func configure(value: bool) -> void:
	enabled = value
	body.gravity_enabled = value

func active() -> bool:
	return state != "idle"

func set_geometry(new_size: Vector2, new_area: Rect2, new_anchor: Vector2) -> void:
	if size == new_size and area == new_area and anchor.is_equal_approx(new_anchor): return
	var old_at := window_position()
	var old_anchor := anchor
	var resizing := size != new_size or not anchor.is_equal_approx(new_anchor)
	size = new_size
	area = new_area
	anchor = new_anchor
	body.extent = size.y
	if resizing:
		for child in body.get_children():
			body.remove_child(child)
			child.queue_free()
		# Main head and torso/feet only. Flowing hair and transparent padding
		# do not make the pet hit a wall prematurely.
		for spec in [[Vector2(0.5, 0.35), 0.285, 0.64], [Vector2(0.5, 0.76), 0.17, 0.48]]:
			var collision := CollisionShape2D.new()
			var capsule := CapsuleShape2D.new()
			capsule.radius = size.x * spec[1]
			capsule.height = size.y * spec[2]
			collision.shape = capsule
			collision.position = size * spec[0] - anchor
			body.add_child(collision)
		body.center_of_mass = size * Vector2(0.5, 0.55) - anchor
		body.inertia = size.length_squared() * 0.085
		if initialized:
			body.position = old_at + anchor
			if body.floor_locked: body.floor_x = body.position.x
			body.attachment += old_anchor - anchor
	var thick := 256.0
	var centers := [Vector2(area.position.x - thick / 2, area.get_center().y),
		Vector2(area.end.x + thick / 2, area.get_center().y),
		Vector2(area.get_center().x, area.position.y - thick / 2),
		Vector2(area.get_center().x, area.end.y + thick / 2)]
	for i in 4:
		walls[i].position = centers[i]
		walls[i].get_child(0).shape.size = Vector2(thick, area.size.y + 2 * thick) if i < 2 else Vector2(area.size.x + 2 * thick, thick)

func window_position() -> Vector2:
	return body.position - anchor if initialized else position_at

func begin(at: Vector2, pointer: Vector2, facing: float) -> void:
	if not active():
		_sync(at)
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
	physical_facing = 1.0 if facing >= 0.0 else -1.0
	state = "held"
	body.floor_locked = false
	body.held = true
	body.pointer = pointer
	body.attachment = body.transform.affine_inverse() * pointer
	quiet_time = 0.0
	flight_consumed = true
	floor_sequence_seen = body.floor_sequence
	body.freeze = paused

func set_pointer(pointer: Vector2) -> void:
	body.pointer = pointer

func release() -> void:
	if state != "held" and not body.held: return
	state = "falling"
	body.held = false
	started_pending = true
	quiet_time = 0.0
	_arm_flight()
	# Deliberately preserve BOTH velocities; no estimated mouse fling or reset.

func cancel() -> void:
	state = "idle"
	body.floor_locked = false
	body.held = false
	body.freeze = true
	body.linear_velocity = Vector2.ZERO
	body.angular_velocity = 0.0
	body.rotation = 0.0
	quiet_time = 0.0
	started_pending = false
	landed_pending = false
	was_grounded = false
	flight_consumed = true
	floor_sequence_seen = body.floor_sequence

func _arm_flight() -> void:
	body.floor_locked = false
	flight_consumed = false
	floor_sequence_seen = body.floor_sequence
	flight_height = maxf(0.0, (area.end.y - window_position().y - size.y) / maxf(size.y, 1.0))

func reposition(at: Vector2) -> void:
	_sync(at)
	# Resizing/rebasing is not a new throw: retain existing momentum.

func _sync(at: Vector2) -> void:
	position_at = at
	body.position = at + anchor
	if body.floor_locked: body.floor_x = body.position.x
	initialized = true

func _pause(value: bool) -> void:
	if paused == value: return
	paused = value
	if paused:
		saved_velocity = body.linear_velocity
		saved_spin = body.angular_velocity
		var frozen_at: Vector2 = body.position
		body.freeze = true
		body.position = frozen_at
	elif active():
		body.freeze = false
		body.linear_velocity = saved_velocity
		body.angular_velocity = saved_spin

func update(dt: float, at: Vector2, new_size: Vector2, new_area: Rect2, held: bool = false, pause: bool = false) -> Dictionary:
	var impact := {}
	set_geometry(new_size, new_area, anchor if size != Vector2.ZERO else new_size * Vector2(0.43, 0.25))
	_pause(pause)
	if not active():
		_sync(at)
		body.rotation = 0.0
		if enabled and not held and not paused and at.y + size.y < area.end.y - 2.0:
			state = "falling"
			body.freeze = false
			body.linear_velocity = Vector2.ZERO
			body.angular_velocity = 0.0
			started_pending = true
			_arm_flight()
	if active() and not paused:
		# The support constraint now stops lateral motion. Let the contacting
		# capsule rotate upright without static friction fighting that constraint.
		body.physics_material_override.friction = 0.0 if body.floor_locked else 0.9
		# Restitution changes smoothly with incident speed; the physics solver
		# still supplies the actual normal impulse, including corner contacts.
		for i in 3:
			var speed := absf(body.linear_velocity.x if i < 2 else body.linear_velocity.y) / size.y
			walls[i].physics_material_override.bounce = lerpf(0.4, 0.65, smoothstep(0.4, 4.0, speed))
		if state != "held":
			if not flight_consumed:
				flight_height = maxf(flight_height, (area.end.y - window_position().y - size.y) / size.y)
				if body.floor_sequence != floor_sequence_seen:
					flight_consumed = true
					var impact_speed: float = body.floor_speed / size.y
					if impact_speed > 0.12 or flight_height > 0.012:
						impact = {"height": flight_height, "speed": impact_speed,
							"lateral_speed": body.floor_velocity.x / size.y,
							"spin": body.floor_spin, "angle": body.floor_angle, "facing": physical_facing}
			floor_sequence_seen = body.floor_sequence
			if body.grounded and not was_grounded: landed_pending = true
			var resting: bool = (body.grounded or not enabled) and body.linear_velocity.length() < size.y * 0.035 \
				and absf(body.rotation) < deg_to_rad(0.8) and absf(body.angular_velocity) < 0.05
			quiet_time = quiet_time + minf(dt, 0.1) if resting else 0.0
			if quiet_time > 0.18:
				var settled := window_position()
				if body.grounded: settled.y = area.end.y - size.y
				cancel()
				_sync(settled)
				landed_pending = true
		was_grounded = body.grounded
	var result := {"position": window_position(), "move": active() or landed_pending,
		"started": started_pending, "landed": landed_pending, "impact": impact}
	started_pending = false
	landed_pending = false
	return result

func pose(pause: bool = false) -> Dictionary:
	var airborne: bool = state == "falling" and not body.grounded and not flight_consumed and enabled
	return {"fallActive": airborne, "fallSpeed": maxf(0.0, body.linear_velocity.y / maxf(size.y, 1.0)),
		"fallPaused": pause, "fallNormalize": 0.0,
		"floorSupported": state == "falling" and body.floor_locked,
		# Correct the tilted capsule's vertical settling while the native floor
		# constraint holds its horizontal position.
		"landingGroundOffset": area.end.y - size.y - window_position().y \
			if state == "falling" and flight_consumed and enabled else 0.0,
		"physicsActive": active(), "physicsAngle": body.rotation,
		"physicsSpin": body.angular_velocity, "physicsPull": body.spring_gap / maxf(size.y, 1.0)}
