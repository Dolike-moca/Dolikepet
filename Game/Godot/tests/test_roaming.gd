extends SceneTree
const Roaming = preload("res://scripts/roaming.gd")
const Idle = preload("res://scripts/idle_sitting.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
var failures := 0
var checks := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ROAMING: " + message)

func _simulate(mode: String, area: Rect2) -> Dictionary:
	var roam = Roaming.new()
	roam.configure(mode)
	roam.rng.seed = 20261020
	var idle = Idle.new()
	idle.configure(true, 15, 25)
	idle.rng.seed = 20
	var sit = Sitting.new()
	var size := Vector2(420, 420)
	var position := area.position + Vector2(300, 30)
	var metrics := {"walk": 0.0, "sit": 0.0, "trips": 0, "rests": 0}
	var bounded := true
	var legal_transition := true
	var no_teleport := true
	var previous := "idle"
	for frame in 60 * 900:
		if idle.advance(1.0 / 60.0, roam.rest_requested, sit.seated):
			roam.request_rest()
		var before := position
		var result: Dictionary = roam.update(1.0 / 60.0, position, size, area,
			sit.amount, sit.seated, idle.automatically_seated, false)
		if result.move:
			position = result.position
			bounded = bounded and position.x >= area.position.x and position.x + size.x <= area.end.x
			no_teleport = no_teleport and position.distance_to(before) < 10.0
		if result.sit >= 0:
			sit.set_seated(result.sit == 1)
			if result.sit == 0:
				idle.interact()
			else:
				metrics.rests += 1
				legal_transition = legal_transition and roam.weight == 0.0
		sit.update(1.0 / 60.0)
		if roam.state == "walking":
			metrics.walk += 1.0 / 60.0
			legal_transition = legal_transition and sit.amount <= 0.0001 \
				and absf(position.y + size.y - area.end.y) < 0.01
			if previous != "walking":
				metrics.trips += 1
		if sit.seated:
			metrics.sit += 1.0 / 60.0
		previous = roam.state
	_check(bounded and no_teleport, mode + " crossed display edges or teleported")
	_check(legal_transition, mode + " walked while seated/airborne or sat with moving feet")
	return metrics

func _short_steps(fps: int, width: float) -> Vector2:
	var roam = Roaming.new()
	roam.state = "walking"
	roam.travel_position = Vector2(100, 1000 - width)
	roam.target_x = 3000.0
	var size := Vector2(width, width)
	var area := Rect2(0, 0, 4000, 1000)
	for frame in fps * 6:
		roam.update(1.0 / fps, roam.travel_position, size, area, 0.0, false, false, false)
	var distance: float = roam.travel_position.x - 100.0
	var footfalls: float = roam.phase / PI
	_check(footfalls / 6.0 > 3.1 and footfalls / 6.0 < 3.6,
		"short steps lost their cadence at %d FPS / %d px" % [fps, width])
	_check(distance / footfalls < width * 0.06, "short steps became long strides")
	return Vector2(distance / width, footfalls)

func _initialize() -> void:
	var cadence_baseline := _short_steps(60, 420.0)
	for spec in [Vector2(30, 280), Vector2(120, 720)]:
		var measured := _short_steps(int(spec.x), spec.y)
		_check(measured.distance_to(cadence_baseline) < 0.1,
			"step/travel synchronization changed with frame rate or pet size")
	var area := Rect2(-1920, -200, 1920, 1080)
	var free := _simulate("free", area)
	var calm := _simulate("calm", area)
	var off := _simulate("off", area)
	_check(free.trips > calm.trips and calm.trips > 0 and off.trips == 0, "mode walking frequency")
	_check(calm.sit > free.sit and off.sit > calm.sit, "mode rest balance")
	print("ROAMING 15 minutes per mode: free=%s; calm=%s; off=%s" % [free, calm, off])
	var roam = Roaming.new()
	roam.configure("free")
	roam.wait_remaining = 0.0
	var pos := Vector2(300, 30)
	var size := Vector2(420, 420)
	var primary := Rect2(0, 0, 1920, 1040)
	var result: Dictionary = roam.update(0.1, pos, size, primary, 1.0, true, false, false)
	_check(not result.move and result.sit == -1 and roam.state == "idle", "manual sitting was interrupted")
	roam.update(0.1, pos, size, primary, 0.0, false, false, false)
	_check(roam.state == "landing", "did not return to floor before walking")
	result = roam.update(0.1, pos, size, primary, 0.0, false, false, true)
	_check(not result.move and roam.state == "idle" and roam.weight == 0.0, "interaction did not stop travel")
	roam.configure("off")
	for i in 100:
		result = roam.update(0.1, pos, size, primary, 0.0, false, false, false)
	_check(not result.move and roam.state == "idle", "off mode wandered")
	roam.configure("free")
	roam.wait_remaining = 0.0
	result = roam.update(0.1, pos, size, Rect2(0, 0, 420, 800), 0.0, false, false, false)
	_check(not result.move and roam.state == "idle", "walked on a display too narrow for pet")
	roam.configure("unknown")
	_check(roam.mode == "calm", "malformed saved mode")
	roam.configure("free")
	roam.wait_remaining = 0.0
	var rng_state: int = roam.rng.state
	roam.update(0.1, pos, size, primary, 0.5, false, false, false)
	_check(roam.wait_remaining == 0.0 and roam.rng.state == rng_state,
		"expired walking deadline was redrawn while rising")
	roam.update(0.1, pos, size, primary, 0.0, false, false, false)
	_check(roam.state == "landing", "ready trip did not start after rising")
	roam.state = "walking"
	roam.weight = 1.0
	roam.cadence = Roaming.WALK_CYCLES_PER_SECOND
	roam.phase = PI / 3.0
	roam.request_rest()
	var last_phase: float = roam.phase
	result = roam.update(1.0 / 60.0, pos, size, primary, 0.0, false, false, false)
	_check(roam.phase > last_phase and roam.weight > 0.0 and roam.weight < 1.0
		and result.sit == -1, "stop froze the gait or sat before settling")
	var requested_sit := false
	for frame in 60:
		result = roam.update(1.0 / 60.0, pos, size, primary, 0.0, requested_sit, true, false)
		requested_sit = requested_sit or result.sit == 1
	_check(requested_sit and roam.weight == 0.0 and roam.cadence == 0.0, "gait did not fully settle before rest")
	roam.state = "walking"
	roam.weight = 1.0
	roam.cadence = Roaming.WALK_CYCLES_PER_SECOND
	result = roam.update(1.0 / 60.0, pos, size, primary, 0.0, false, false, true)
	_check(not result.move and roam.state == "idle" and roam.weight > 0.0,
		"grabbing the pet must stop travel immediately while the pose relaxes")
	print("ROAMING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
