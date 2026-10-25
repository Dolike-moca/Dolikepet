extends RigidBody2D
## Forces only: Godot integrates movement and solves all boundary contacts.
var held := false
var gravity_enabled := true
var extent := 420.0
var pointer := Vector2.ZERO
var attachment := Vector2.ZERO
var grounded := false
var impact_count := 0
var last_impact := Vector2.ZERO
var spring_gap := Vector2.ZERO
var last_contacts := {}
var floor_sequence := 0
var wall_sequence := 0
var floor_speed := 0.0
var floor_velocity := Vector2.ZERO
var floor_spin := 0.0
var floor_angle := 0.0
var previous_velocity := Vector2.ZERO
var previous_spin := 0.0
var floor_locked := false
var floor_x := 0.0

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var previously_grounded := grounded
	grounded = false
	var contacts := {}
	var new_wall := false
	for i in state.get_contact_count():
		var collider = state.get_contact_collider_object(i)
		if not is_instance_valid(collider): continue
		contacts[collider.get_instance_id()] = true
		if collider.get_meta("floor", false): grounded = true
		if not last_contacts.has(collider.get_instance_id()):
			impact_count += 1
			last_impact = state.get_contact_impulse(i)
			# Observe contact entry only. Dragging, floor support and slow edge
			# scrapes cannot qualify; simultaneous corner contacts are one event.
			if not held and collider.get_meta("boundary","") in ["left","right","top"]:
				var inward: Vector2 = state.get_contact_local_normal(i).rotated(state.transform.get_rotation())
				if previous_velocity.dot(inward)<-extent*0.12:
					new_wall = true
	if new_wall: wall_sequence += 1
	last_contacts = contacts
	if grounded and not previously_grounded and not held:
		floor_sequence += 1
		# Contacts arrive after the solver has reduced normal velocity. Preserve
		# the preceding free-flight sample instead of measuring the stopped body.
		floor_speed = maxf(0.0, maxf(previous_velocity.y, state.linear_velocity.y))
		floor_velocity = Vector2(previous_velocity.x, floor_speed)
		floor_spin = previous_spin
		floor_angle = state.transform.get_rotation()
	previous_velocity = state.linear_velocity
	previous_spin = state.angular_velocity
	# A floor support constraint, applied inside the native physics step. A
	# landing stops sideways travel immediately; air/wall momentum is retained.
	if held:
		floor_locked = false
	elif grounded or floor_locked:
		if not floor_locked:
			floor_x = state.transform.origin.x
			floor_locked = true
		var supported := state.transform
		supported.origin.x = floor_x
		state.transform = supported
		state.linear_velocity.x = 0.0
	var angle := wrapf(state.transform.get_rotation(), -PI, PI)
	var inertia_value := 1.0 / maxf(state.inverse_inertia, 0.000001)
	# An upright spring allows a visible swing, then restores the character.
	# Progressive angular resistance prevents full flips even for edge grabs.
	var angular_accel := -angle * 58.0 - state.angular_velocity * (9.0 if held else 11.0)
	var excess := maxf(0.0, absf(angle) - deg_to_rad(16.0))
	angular_accel -= signf(angle) * excess * 1000.0
	state.apply_torque(inertia_value * angular_accel)
	if gravity_enabled:
		state.apply_central_force(Vector2(0, mass * extent * 8.8 * (0.15 if held else 1.0)))
	if held:
		var grab_world := state.transform * attachment
		var arm := grab_world - (state.transform.origin + state.center_of_mass)
		var point_velocity := state.linear_velocity + Vector2(-arm.y, arm.x) * state.angular_velocity
		spring_gap = pointer - grab_world
		var stiffness := lerpf(100.0, 360.0, smoothstep(0.04, 0.7, spring_gap.length() / extent))
		var force := mass * (spring_gap * stiffness - point_velocity * 2.0 * sqrt(stiffness) * 0.78)
		# Very long off-screen pulls are bounded; normal dragging stays progressive.
		force = force.limit_length(mass * extent * 110.0)
		state.apply_force(force, grab_world - state.transform.origin)
	else:
		spring_gap = Vector2.ZERO
		# Dampen the remaining landing motion while horizontal support is fixed.
		# Free-flight air drag stays light.
		var resistance := 8.0 if grounded else (0.24 if gravity_enabled else 2.0)
		state.apply_central_force(-state.linear_velocity * mass * resistance)
	# A joint-like angular stop is only a last resort for an extreme impulse.
	# Linear velocity and all collision impulses still belong to the solver.
	if absf(angle) > deg_to_rad(24.0):
		state.transform = Transform2D(clampf(angle, deg_to_rad(-24), deg_to_rad(24)), state.transform.origin)
		if state.angular_velocity * angle > 0.0: state.angular_velocity = 0.0
