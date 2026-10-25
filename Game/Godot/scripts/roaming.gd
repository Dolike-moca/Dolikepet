extends RefCounted
## Autonomous travel in desktop pixels. The host owns sitting and user interaction.
const MODES := ["free", "calm", "off"]
const WALK_CYCLES_PER_SECOND := 1.7 # Two alternating footfalls per full cycle.
var mode := "calm"
var state := "idle"
var rng := RandomNumberGenerator.new()
var wait_remaining := -1.0
var rest_remaining := -1.0
var rest_requested := false
var phase := 0.0
var cadence := 0.0
var weight := 0.0
var speed := 0.0
var facing := -1 # The original artwork faces left.
var facing_scale := 1.0
var direction := -1
var target_x := 0.0
var travel_position := Vector2.ZERO
var landing_from := Vector2.ZERO
var landing_to := Vector2.ZERO
var landing_duration := 1.0
var stage_time := 0.0
var turning_only := false

func _init() -> void:
	rng.randomize()

func configure(value: String) -> void:
	mode = value if value in MODES else "calm"
	interrupt()

func interrupt() -> void:
	turning_only = false
	state = "idle"
	speed = 0.0
	wait_remaining = -1.0
	rest_remaining = -1.0
	rest_requested = false
	facing_scale = -float(facing)

func request_rest() -> void:
	rest_requested = true

func turn_in_place(position: Vector2, toward: int) -> void:
	turning_only = true
	travel_position = position
	target_x = position.x
	direction = toward
	stage_time = 0.0
	state = "turning"

func stop_for_menu(position: Vector2) -> void:
	var walking := state == "walking" and speed > 0.0
	var old_speed := speed
	interrupt()
	if walking:
		state = "menu_stopping"
		travel_position = position
		speed = old_speed

func _menu_stop(dt: float, position: Vector2, size: Vector2, area: Rect2) -> Dictionary:
	var result := {"position": position, "move": false, "sit": -1}
	if state != "menu_stopping":
		interrupt()
		_settle_pose(dt)
		return result
	var old_speed := speed
	speed = move_toward(speed, 0.0, size.x * 1.2 * dt)
	var step := (old_speed + speed) * 0.5 * dt
	var left := area.position.x + 8.0
	var right := maxf(left, area.end.x - size.x - 8.0)
	var before := travel_position.x
	# Brake from the actual position even when a transparent margin is
	# outside the window bounds; clipping the origin would teleport it.
	travel_position.x = clampf(before + facing * step, minf(left,before), maxf(right,before))
	step = absf(travel_position.x - before)
	cadence = step / maxf(size.x * 0.18 * dt, 0.0001) * WALK_CYCLES_PER_SECOND
	phase += TAU * cadence * dt
	weight = move_toward(weight, speed / maxf(size.x * 0.18, 1.0), dt * 6.0)
	result.position = travel_position
	result.move = step > 0.0
	if speed == 0.0 or step == 0.0: state = "idle"
	return result

func _settle_pose(dt: float) -> void:
	# Keep following the step briefly while it fades instead of freezing mid-swing.
	cadence = move_toward(cadence, 0.0, dt * WALK_CYCLES_PER_SECOND / 0.26)
	phase += TAU * cadence * dt
	weight = move_toward(weight, 0.0, dt * 4.0)
	if weight == 0.0:
		cadence = 0.0

func travelling() -> bool:
	return state in ["landing", "turning", "walking", "settling", "rising"]

func _wait_duration() -> float:
	return rng.randf_range(4.0, 9.0) if mode == "free" else rng.randf_range(30.0, 55.0)

func _rest_duration() -> float:
	return rng.randf_range(10.0, 20.0) if mode == "free" else rng.randf_range(55.0, 100.0)

func _begin_trip(position: Vector2, size: Vector2, area: Rect2, goal_x: float = NAN) -> bool:
	var left := area.position.x + 8.0
	var right := maxf(left, area.end.x - size.x - 8.0)
	if right - left < 24.0:
		wait_remaining = _wait_duration()
		return false
	# A held/landed pet can stand closer to an edge than an autonomous goal.
	# Keep its actual origin, then walk into the goal range at normal speed.
	travel_position = position
	direction = -1 if rng.randf() < 0.5 else 1
	var distance := rng.randf_range(size.x * 0.45, size.x * 1.1)
	target_x = clampf(travel_position.x + direction * distance, left, right)
	if absf(target_x - travel_position.x) < minf(size.x * 0.2, (right - left) * 0.4):
		direction *= -1
		target_x = clampf(travel_position.x + direction * distance, left, right)
	if is_finite(goal_x): target_x = clampf(goal_x,left,right)
	direction = int(signf(target_x - travel_position.x))
	if direction == 0:
		return false
	landing_from = travel_position
	landing_to = Vector2(travel_position.x, maxf(area.position.y, area.end.y - size.y))
	landing_duration = clampf(absf(landing_to.y - position.y) / (size.y * 0.9), 0.4, 1.8)
	stage_time = 0.0
	state = "landing" if absf(landing_to.y - position.y) > 1.0 else "turning"
	return true

func update(dt: float, position: Vector2, size: Vector2, area: Rect2,
		sit_amount: float, seated: bool, automatic_seat: bool, busy: bool, menu_open: bool = false, goal_x: float = NAN) -> Dictionary:
	var result := {"position": position, "move": false, "sit": -1}
	dt = clampf(dt, 0.0, 0.1) if is_finite(dt) else 0.0
	if dt == 0.0:
		return result
	if menu_open:
		return _menu_stop(dt, position, size, area)
	if state == "menu_stopping": interrupt()
	if busy:
		interrupt()
		_settle_pose(dt)
		return result
	# Finish landing AND the mirror turn before sitting. Leaving "turning"
	# midway would strand facing_scale at its compressed value during rest.
	if rest_requested and state not in ["landing", "turning"]:
		state = "settling"
	if state == "settling":
		speed = 0.0
		_settle_pose(dt)
		if weight == 0.0:
			state = "idle"
			wait_remaining = -1.0
			if rest_requested:
				result.sit = 1
				rest_requested = false
				rest_remaining = -1.0
		return result
	var seeking := is_finite(goal_x)
	if seated and seeking:
		_settle_pose(dt)
		result.sit = 0
		state = "rising"
		return result
	if seated:
		_settle_pose(dt)
		if not automatic_seat or mode == "off":
			return result
		if sit_amount < 0.999:
			return result
		if rest_remaining < 0.0:
			rest_remaining = _rest_duration()
		rest_remaining -= dt
		if rest_remaining <= 0.0:
			result.sit = 0
			state = "rising"
		return result
	rest_remaining = -1.0
	if mode == "off" and not seeking and not turning_only:
		_settle_pose(dt)
		return result
	if state == "rising":
		if sit_amount <= 0.0001:
			state = "idle"
			wait_remaining = 0.0
		else:
			return result
	if state == "idle":
		_settle_pose(dt)
		if seeking:
			if absf(goal_x-position.x)>1.0 and sit_amount<=0.0001 and weight==0.0:
				_begin_trip(position,size,area,goal_x)
			return result
		if wait_remaining < 0.0:
			wait_remaining = _wait_duration()
		# Keep an expired deadline ready while the standing animation finishes.
		# A negative value means "not sampled yet", so it must not be used here.
		wait_remaining = maxf(0.0, wait_remaining - dt)
		if wait_remaining <= 0.0 and sit_amount <= 0.0001 and weight == 0.0:
			_begin_trip(position, size, area)
		return result
	stage_time += dt
	if state == "landing":
		var progress := clampf(stage_time / landing_duration, 0.0, 1.0)
		travel_position = landing_from.lerp(landing_to, smoothstep(0.0, 1.0, progress))
		result.position = travel_position
		result.move = true
		if progress == 1.0:
			state = "turning"
			stage_time = 0.0
		return result
	if state == "turning":
		if direction != facing:
			var progress := clampf(stage_time / 0.28, 0.0, 1.0)
			var compression := maxf(0.12, absf(cos(PI * progress)))
			facing_scale = -float(facing if progress < 0.5 else direction) * compression
			if progress < 1.0:
				return result
		facing = direction
		facing_scale = -float(facing)
		if turning_only:
			turning_only = false
			state = "idle"
			return result
		if rest_requested:
			# The pending rest takes priority over starting a walk. Width is now
			# fully restored; the next update can settle and issue the sit command.
			state = "settling"
			return result
		state = "walking"
		stage_time = 0.0
		phase = 0.0
		cadence = 0.0
	if state == "walking":
		if seeking and signf(goal_x-travel_position.x)==direction: target_x = goal_x
		var left := area.position.x + 8.0
		var right := maxf(left, area.end.x - size.x - 8.0)
		target_x = clampf(target_x, left, right)
		var distance := absf(target_x - travel_position.x)
		var max_speed := size.x * 0.18
		var wanted := minf(max_speed, sqrt(2.0 * size.x * 0.65 * distance))
		speed = move_toward(speed, wanted, size.x * 0.65 * dt)
		var step := minf(distance, speed * dt)
		travel_position.x += signf(target_x - travel_position.x) * step
		# More, shorter steps over the same travel distance; cadence follows actual
		# displacement so acceleration, size changes and arrival stay synchronized.
		cadence = step / (max_speed * dt) * WALK_CYCLES_PER_SECOND
		phase += TAU * cadence * dt
		weight = move_toward(weight, speed / max_speed, dt * 5.0)
		result.position = travel_position
		result.move = true
		if distance <= step + 0.05:
			state = "settling"
	return result
