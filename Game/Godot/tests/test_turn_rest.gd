extends SceneTree
## A rest deadline can land on any frame of the mirror turn.
const Roaming = preload("res://scripts/roaming.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
const POSITION := Vector2(300, 620)
const SIZE := Vector2(420, 420)
const AREA := Rect2(0, 0, 1920, 1040)
var checks := 0
var failures := 0
var cases := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("TURN REST: " + message)

func _turn_at(frame: int, fps: int, facing: int):
	var roam = Roaming.new()
	roam.state = "turning"
	roam.facing = facing
	roam.facing_scale = -float(facing)
	roam.direction = -facing
	roam.travel_position = POSITION
	roam.target_x = POSITION.x + roam.direction * 200.0
	for n in frame:
		roam.update(1.0 / fps, POSITION, SIZE, AREA, 0.0, false, false, false)
	return roam

func _rest_at(frame: int, fps: int, facing: int) -> void:
	var roam = _turn_at(frame, fps, facing)
	var sit = Sitting.new()
	var before: float = roam.facing_scale
	var requests := 0
	var no_walk := true
	var full_width_seated := true
	var turn_completed := true
	roam.request_rest()
	for n in fps * 2:
		var movement: Dictionary = roam.update(1.0 / fps, POSITION, SIZE, AREA,
			sit.amount, sit.seated, true, false)
		no_walk = no_walk and not movement.move and roam.weight == 0.0
		if movement.sit == 1:
			requests += 1
			turn_completed = turn_completed and roam.facing == -facing and roam.state != "turning"
			sit.set_seated(true)
		if sit.seated:
			full_width_seated = full_width_seated and is_equal_approx(absf(roam.facing_scale), 1.0)
		sit.update(1.0 / fps)
	cases += 1
	var label := "%d FPS, direction %d, frame %d, width %.3f -> %.3f" % [
		fps, -facing, frame, before, roam.facing_scale]
	_check(requests == 1 and sit.amount == 1.0, "rest did not complete once: " + label)
	_check(full_width_seated, "compressed while seated: " + label)
	_check(turn_completed, "rest abandoned the turn: " + label)
	_check(no_walk, "extra movement before pending rest: " + label)

func _takeover_at(frame: int, fps: int, facing: int) -> void:
	for takeover in ["interaction", "busy", "settings"]:
		var roam = _turn_at(frame, fps, facing)
		roam.request_rest()
		if takeover == "interaction":
			roam.interrupt() # Host click/drag/menu path, including manual sit.
		elif takeover == "settings":
			roam.configure("off")
		else:
			roam.update(1.0 / fps, POSITION, SIZE, AREA, 0.0, false, false, true)
		var stable: bool = roam.state == "idle" and not roam.rest_requested
		for n in fps:
			var movement: Dictionary = roam.update(1.0 / fps, POSITION, SIZE, AREA,
				0.0, false, false, false)
			stable = stable and not movement.move and movement.sit == -1 \
				and is_equal_approx(absf(roam.facing_scale), 1.0)
		_check(stable, "takeover retained turn/rest state: " + takeover)

func _initialize() -> void:
	# This is the user's failure case: the rest timer expires at the narrowest frame.
	var example = _turn_at(8, 60, -1)
	var width_before: float = example.facing_scale
	example.request_rest()
	var movement: Dictionary = example.update(1.0 / 60.0, POSITION, SIZE, AREA, 0.0, false, true, false)
	print("TURN DEADLINE REPRO: before width=%.3f; after state=%s width=%.3f sit=%d" % [
		width_before, example.state, example.facing_scale, movement.sit])
	for fps in [30, 60, 120]:
		for facing in [-1, 1]:
			for frame in range(1, int(ceil(0.28 * fps))):
				_rest_at(frame, fps, facing)
				_takeover_at(frame, fps, facing)
	print("TURN REST: %d deadline timings, %d checks, %d failures" % [cases, checks, failures])
	quit(0 if failures == 0 else 1)
