extends RefCounted
## Port of the accepted Electron controllers. Values use Cubism's +Y-up axes.

const HAIR = {
	"hairFront": [150.0, 21.0, 0.00, 0.70, 0.020],
	"hairSide": [68.0, 12.0, 0.04, 0.80, 0.050],
	"hairBack": [24.0, 8.0, 0.10, 0.85, 0.075],
	"hairBraidNear": [48.0, 10.0, 0.07, 0.65, 0.060],
	"hairBraidFar": [22.0, 8.4, 0.13, 0.75, 0.070],
	"hairTuft": [125.0, 9.0, 0.02, 0.60, 0.065],
}

const BLINK_DURATION := 0.2
const DOUBLE_BLINK_CHANCE := 0.18
const ChewingMotion = preload("res://scripts/chewing_motion.gd")
var chewing = ChewingMotion.new()

var time := 0.0
var blink_rng := RandomNumberGenerator.new()
var automatic_blinks := true # Internal switch for deterministic render/parity tests.
var next_blink := 0.0
var blink_start := -10.0
var second_blink_at := -1.0
var blink_was_closed := false
var expression_eye := 1.0
var mode := "normal"
var reaction_until := 0.0
var talk_until := 0.0
var talk_start := 0.0
var values := {
	"eyeNear": 1.0, "eyeFar": 1.0, "mouth": 0.0, "breath": 0.0,
	"gazeX": 0.0, "gazeY": 0.0,
	"headX": 0.0, "headY": 0.0, "headZ": 0.0,
	"bodyX": 0.0, "bodyY": 0.0,
}
var velocity: Dictionary = {}
var previous_head := 0.0
var history: Array[Dictionary] = [{"time": 0.0, "x": 0.0, "y": 0.0, "speed": 0.0}]

func _init() -> void:
	blink_rng.randomize()
	next_blink = _blink_wait()
	for key in HAIR:
		for suffix in ["", "Y"]:
			values[key + suffix] = 0.0
			velocity[key + suffix] = 0.0

static func smooth(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

static func blink_openness(age: float) -> float:
	if age < 0.0 or age >= BLINK_DURATION:
		return 1.0
	if age < 0.06:
		return 1.0 - smooth(age / 0.06)
	if age < 0.1:
		return 0.0
	return smooth((age - 0.1) / 0.1)

func _blink_wait() -> float:
	# Animation pacing: mostly medium pauses with occasional shorter/longer ones.
	return clampf(blink_rng.randfn(3.8, 1.3), 1.5, 7.5)

func _update_blink(closed: bool, dt: float) -> void:
	if closed:
		second_blink_at = -1.0
		blink_start = -10.0
		blink_was_closed = true
		return
	if blink_was_closed:
		blink_was_closed = false
		next_blink = time + _blink_wait()
	if not automatic_blinks:
		second_blink_at = -1.0
		return
	if dt <= 0.0:
		return
	if second_blink_at >= 0.0:
		if time >= second_blink_at:
			blink_start = time
			second_blink_at = -1.0
			# A second blink cannot schedule a third one.
			next_blink = time + BLINK_DURATION + _blink_wait()
		return
	if time >= next_blink and time - blink_start >= BLINK_DURATION:
		blink_start = time
		if blink_rng.randf() < DOUBLE_BLINK_CHANCE:
			# Finish reopening before a brief pause and the second closure.
			second_blink_at = time + BLINK_DURATION + blink_rng.randf_range(0.10, 0.18)
		else:
			next_blink = time + BLINK_DURATION + _blink_wait()

static func gaze_target(cursor: Vector2, anchor: Vector2, size: float, active: bool) -> Vector2:
	if not active or size <= 0.0 or not cursor.is_finite() or not anchor.is_finite():
		return Vector2.ZERO
	var offset := (cursor - anchor) / size
	offset.y = -offset.y
	var distance := offset.length()
	var attention := 1.0 - smooth(clampf((distance - 1.0) / 0.6, 0.0, 1.0))
	return offset / maxf(0.45, distance) * attention

func command(action: String, bite_age: float = -1.0) -> void:
	if action in ["normal", "closed", "happy", "closedHappy", "talk", "pet"]:
		chewing.cancel()
	match action:
		"chew":
			mode = "normal"
			talk_until = 0.0
			reaction_until = 0.0
			chewing.start(bite_age)
		"normal", "closed", "happy", "closedHappy":
			mode = action
			reaction_until = 0.0
			talk_until = 0.0
		"talk":
			talk_start = time
			talk_until = time + 5.0
			reaction_until = 0.0
		"pet":
			reaction_until = time + 1.4
		"satisfied":
			mode = "normal"
			talk_until = 0.0
			reaction_until = time + 2.1
		"blink":
			blink_start = time
			second_blink_at = -1.0
			next_blink = time + BLINK_DURATION + _blink_wait()

func _follow(key: String, target: float, rate: float, dt: float) -> void:
	values[key] += (target - values[key]) * (1.0 - exp(-rate * dt))
	if absf(target - values[key]) < 0.0001:
		values[key] = target

func _delayed(at: float) -> Dictionary:
	var before: Dictionary = history[0]
	for i in range(1, history.size()):
		var after: Dictionary = history[i]
		if after.time >= at:
			var blend := clampf((at - before.time) / (after.time - before.time), 0.0, 1.0)
			return {
				"x": lerpf(before.x, after.x, blend),
				"y": lerpf(before.y, after.y, blend),
				"speed": lerpf(before.speed, after.speed, blend),
			}
		before = after
	return before

func _hair(dt: float) -> void:
	if dt <= 0.0:
		return
	var turn := clampf(values.headZ / 18.0, -1.0, 1.0)
	var speed := clampf((turn - previous_head) / dt, -6.0, 6.0)
	previous_head = turn
	var vertical: float = values.gazeY
	history.append({
		"time": time, "x": values.gazeX,
		"y": vertical * (0.25 if vertical > 0.0 else 0.4), "speed": speed,
	})
	var steps := ceili(dt * 240.0)
	var step := dt / steps
	for i in steps:
		for base_key in HAIR:
			var settings: Array = HAIR[base_key]
			var sample := _delayed(time - dt + (i + 1) * step - settings[2])
			for axis in 2:
				var key: String = base_key + ("Y" if axis else "")
				var stiffness: float = settings[0] * (0.7 if axis else 1.0)
				var damping: float = settings[1] * (1.15 if axis else 1.0)
				var target: float = sample.y if axis else clampf(
					sample.x * settings[3] - sample.speed * settings[4], -1.0, 1.0)
				velocity[key] += (stiffness * (target - values[key]) - damping * velocity[key]) * step
				values[key] += velocity[key] * step
				if absf(values[key]) > 1.15:
					values[key] = clampf(values[key], -1.15, 1.15)
					velocity[key] = 0.0
				if absf(target - values[key]) < 0.00001 and absf(velocity[key]) < 0.0001:
					values[key] = target
					velocity[key] = 0.0
	while history.size() > 2 and history[1].time <= time - 0.13:
		history.pop_front()

static func speaking_openness(phase: float) -> float:
	var phrase := fmod(phase, 1.65)
	var syllable := fmod(phrase, 0.3) / 0.3
	var strength := 0.72 + 0.22 * sin(phase * 4.1)
	return strength * pow(sin(PI * syllable), 2.0) if phrase < 1.2 else 0.0

func update(dt: float, cursor: Vector2, anchor: Vector2, size: float, active: bool, paused: bool = false) -> Dictionary:
	dt = clampf(dt, 0.0, 0.1) if is_finite(dt) else 0.0
	time += dt
	var reacting := time < reaction_until
	var closed := mode in ["closed", "closedHappy"] or reacting
	_update_blink(closed, dt)
	var eye_target := 0.0 if closed else 1.0
	expression_eye += (eye_target - expression_eye) * (1.0 - exp(-28.0 * dt))
	if absf(eye_target - expression_eye) < 0.001:
		expression_eye = eye_target
	var mouth_target := 1.0 if mode in ["happy", "closedHappy"] or reacting else 0.0
	if time < talk_until:
		mouth_target = speaking_openness(time - talk_start)
	var eye := minf(blink_openness(time - blink_start), expression_eye)
	if eye < 0.1:
		eye = 0.0
	values.eyeNear = eye
	values.eyeFar = eye
	values.mouth += (mouth_target - values.mouth) * (1.0 - exp(-22.0 * dt))
	values.breath = (1.0 - cos(time * TAU / 4.5)) / 2.0
	var target := gaze_target(cursor, anchor, size, active)
	var rate := 3.5 if target == Vector2.ZERO else 10.0
	_follow("gazeX", target.x, rate, dt)
	_follow("gazeY", target.y, rate, dt)
	_follow("headZ", values.gazeX * 18.0, 8.0, dt)
	_follow("bodyX", values.gazeX, 6.0, dt)
	# The accepted rig has no head translation, neck extension or body pitch.
	values.headX = 0.0
	values.headY = 0.0
	values.bodyY = 0.0
	_hair(dt)
	values.merge(chewing.update(dt, paused), true)
	return values
