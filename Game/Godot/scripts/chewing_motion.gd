extends RefCounted
## A's rigid orbit, with B's decelerating finish, swallow, nod and soft squint.
const GROUPS := 3
const PERIOD_MIN := 0.54
const PERIOD_MAX := 0.68
const REST_MIN := 0.60
const REST_MAX := 1.10
const LONG_SWALLOW_CHANCE := 0.04
const LONG_REST_MIN := 1.5
const LONG_REST_MAX := 2.5
const RELIEF_MIN := 0.8
const RELIEF_MAX := 1.1
const SMILE_HOLD := 0.45
const FADE := 0.12
const ORBIT := Vector2(4.0, 4.5) # Source-model pixels; scales with the pet.
const ROLL := PI / 60.0 # Three degrees.
const Bite = preload("res://scripts/bite_motion.gd")
var rng := RandomNumberGenerator.new()
var groups: Array[Dictionary] = []
var duration := 0.0
var age := 0.0
var stop_at := -1.0
var playing := false
var from_bite := false
var first_update := false

func _init() -> void:
	rng.randomize()

func start(bite_age: float = -1.0, meal: Dictionary = {}) -> void:
	if playing and stop_at < 0.0: return
	from_bite = bite_age >= 0.0
	first_update = from_bite
	age = maxf(0.0,bite_age)
	stop_at = -1.0
	playing = true
	groups.clear()
	var entry_delay := 0.0 if from_bite else FADE
	var at := entry_delay
	var had_long_swallow: bool = not meal.get("allow_long",true)
	var swallow: bool = meal.get("swallow",true)
	var light: bool = meal.get("light",false)
	for i in int(meal.get("groups",GROUPS)):
		# Draw once per group; pausing or frame rate never re-rolls the timing.
		var roll := rng.randf()
		var chews := 3 if roll < 0.16 else (4 if roll < 0.46 else (5 if roll < 0.75 else (6 if roll < 0.93 else 7)))
		if not meal.is_empty(): chews = int(meal.get("chews",rng.randi_range(2,4)))
		var period := rng.randf_range(PERIOD_MIN, PERIOD_MAX)
		if light: period = rng.randf_range(0.44,0.56)
		var turn_times := PackedFloat64Array([0.0])
		for turn in chews:
			var step := maxf(0.41 if light else PERIOD_MIN, period * rng.randf_range(0.92, 1.08))
			# A gentler first turn takes over while the head and food settle.
			if from_bite and i == 0 and turn == 0: step *= 1.08 if light else 1.18
			if turn == chews - 2: step *= 1.08 if light else 1.25
			if turn == chews - 1: step *= (1.30 if swallow else 1.12) if light else 1.60
			turn_times.append(turn_times[-1] + step)
		var normal_time := turn_times[chews - 2]
		if light: normal_time = turn_times[chews-1]
		var chew_time := turn_times[-1]
		var slow_time := chew_time - normal_time
		var long_swallow := swallow and not had_long_swallow and rng.randf() < float(meal.get("long_chance",LONG_SWALLOW_CHANCE))
		had_long_swallow = had_long_swallow or long_swallow
		var rest := rng.randf_range(LONG_REST_MIN, LONG_REST_MAX) if long_swallow else rng.randf_range(REST_MIN, REST_MAX)
		if not swallow: rest = 0.0
		groups.append({"start": at, "chew_end": at + chew_time, "end": at + chew_time + rest,
			"swallow":swallow,
			"rest": rest, "chews": chews, "period": period, "normal_time": normal_time,
			"slow_time": slow_time, "chew_time": chew_time, "turn_times": turn_times, "long_swallow": long_swallow})
		at += chew_time + rest
	# Sample eye timing after the chewing schedule so the accepted rhythm stays
	# independent of these small expression variations.
	for group in groups:
		group.eye_depth = rng.randf_range(0.30, 0.40)
		group.eye_lead = rng.randf_range(0.30, 0.42)
		group.eye_release = rng.randf_range(0.70, 0.78)
	for group in groups:
		# Shorter episodes have fewer efforts, not a faster vibration carrier.
		group.shiver_count = 2 if group.rest < 2.0 else 3
		group.shiver_hz = rng.randf_range(5.5, 6.7)
		group.shiver_phase = rng.randf_range(0.0, TAU)
	# Sample relief after all chew/probability draws, then rebuild the schedule.
	# The 1.5–2.5 s strained swallow and the happy exhale have separate clocks.
	at = entry_delay
	for group in groups:
		group.relief = rng.randf_range(RELIEF_MIN, RELIEF_MAX) + SMILE_HOLD if group.long_swallow else 0.0
		group.start = at
		group.chew_end = at + group.chew_time
		group.end = group.chew_end + group.rest + group.relief
		at = group.end
	duration = at + FADE

func cancel() -> void:
	if playing and stop_at < 0.0: stop_at = age

func active() -> bool:
	return playing

static func turns_at(group: Dictionary, local: float) -> float:
	# Monotone Hermite phase: each chew has its own duration, but adjacent
	# chews share angular velocity, avoiding a hitch at the loop boundary.
	var times: PackedFloat64Array = group.turn_times
	for i in times.size() - 1:
		if local >= times[i + 1]: continue
		var span := times[i + 1] - times[i]
		var u := clampf((local - times[i]) / span, 0.0, 1.0)
		var v0 := 1.0 / span if i == 0 else 2.0 / (times[i + 1] - times[i - 1])
		var v1 := 0.0 if i == times.size() - 2 else 2.0 / (times[i + 2] - times[i])
		return i + (-2.0 * u * u * u + 3.0 * u * u) \
			+ (u * u * u - 2.0 * u * u + u) * span * v0 + (u * u * u - u * u) * span * v1
	return float(group.chews)

func update(dt: float, paused: bool = false) -> Dictionary:
	if playing and not paused:
		# Pickup already advanced this frame. Its exact overshoot is the initial
		# chew age, so advancing again would skip a different amount at each FPS.
		if first_update:
			first_update = false
		else:
			age += clampf(dt, 0.0, 0.1) if is_finite(dt) else 0.0
		if age >= duration - 0.000001 or (stop_at >= 0.0 and age - stop_at >= FADE - 0.000001):
			playing = false
	return pose()

func pose() -> Dictionary:
	var result := {"chewAlpha": 0.0, "chewOffset": Vector2.ZERO, "chewAngle": 0.0,
		"chewSwallow": 0.0, "chewSwallowMouth": 0.0, "chewNod": 0.0, "chewSquint": 0.0,
		"chewSqueeze": 0.0, "chewEyeClose": 0.0, "chewBend": 0.0, "chewShiver": 0.0,
		"chewReliefSmile": 0.0, "chewReliefLift": 0.0, "chewReliefRock": 0.0}
	if not playing: return result
	var alpha := smoothstep(0.0, Bite.BLEND if from_bite else FADE, age) * (1.0 - smoothstep(duration - FADE, duration, age))
	if stop_at >= 0.0: alpha *= 1.0 - smoothstep(stop_at, stop_at + FADE, age)
	result.chewAlpha = alpha
	if not from_bite and age < FADE: return result
	for i in groups.size():
		var group: Dictionary = groups[i]
		if age >= group.end: continue
		var local: float = age - group.start
		var eye_peak := 0.12 if group.long_swallow else 0.28
		# Start during the last chew, deepen before the nod peaks, then finish
		# reopening after the head has returned. Never forces a full blink.
		if group.swallow:
			result.chewSquint = group.eye_depth \
				* smoothstep(group.chew_end - group.eye_lead, group.chew_end + group.rest * eye_peak, age) \
				* (1.0 - smoothstep(group.chew_end + group.rest * group.eye_release, group.end, age)) * alpha
		if not group.swallow:
			# A small bite settles back to its closed mouth without playing a gulp.
			# Fade before the group ends so the next bite never inherits a snap.
			result.chewSquint = 0.0
			result.chewAlpha *= 1.0-smoothstep(group.chew_end-FADE,group.chew_end,age)
		if age < group.chew_end:
			var turns := turns_at(group, local)
			var amplitude := 1.0
			if local > group.normal_time:
				var t: float = local - group.normal_time
				amplitude = lerpf(1.0, 0.28, smoothstep(0.0, group.slow_time, t))
			var envelope := smoothstep(0.0, FADE, local) \
				* (1.0 - smoothstep(group.chew_time - 0.18, group.chew_time, local))
			if from_bite and i == 0:
				envelope = smoothstep(0.0,Bite.SETTLE,local) \
					* lerpf(0.55,1.0,smoothstep(0.0,group.turn_times[1],local)) \
					* (1.0-smoothstep(group.chew_time-0.18,group.chew_time,local))
			var theta := TAU * turns
			result.chewOffset = Vector2(ORBIT.x * sin(theta), ORBIT.y * (1.0 - cos(theta))) * amplitude * envelope
			result.chewAngle = ROLL * sin(theta) * amplitude * envelope
		else:
			if group.long_swallow:
				return long_swallow_pose(result, group, age - group.chew_end, alpha, i == groups.size()-1)
			var u: float = (age - group.chew_end) / group.rest
			var close := smoothstep(0.0, 0.22, u)
			var reopen := smoothstep(0.78, 1.0, u) if i < groups.size() - 1 else 0.0
			result.chewSwallow = close * (1.0 - reopen) * alpha
			result.chewSwallowMouth = result.chewSwallow
			# The final group yields softly to the normal mouth; middle groups
			# crossfade back to the chewing mouth on the existing timing.
			if i == groups.size() - 1:
				result.chewSwallowMouth *= 1.0 - smoothstep(0.86, 1.0, u)
			result.chewAlpha = alpha * (1.0 - close * (1.0 - reopen))
			# One brief dip, no bounce or forced blink. The complete head rig
			# carries it, so the neck and scarf attachment stay together.
			result.chewNod = smoothstep(0.16, 0.43, u) * (1.0 - smoothstep(0.50, 0.86, u)) * alpha
		return result
	# The final swallow settles on the normal mouth instead of flashing the
	# food mouth back on for the last fade.
	result.chewAlpha = 0.0
	return result

static func long_swallow_pose(result: Dictionary, group: Dictionary, elapsed: float, alpha: float, last: bool) -> Dictionary:
	var u := clampf(elapsed / group.rest, 0.0, 1.0)
	var close := smoothstep(0.0, 0.10, u)
	result.chewAlpha = (1.0-close)*alpha
	result.chewSwallow = close*alpha
	result.chewSwallowMouth = close*alpha
	# Hold the successful final gulp into the relief, rather than reopening
	# the eyes or straightening before the last effort has finished.
	var first := 0.55*smoothstep(0.025,0.095,u)*(1.0-smoothstep(0.13,0.21,u))
	result.chewNod = (first+1.20*smoothstep(0.68,0.80,u))*alpha
	result.chewEyeClose = smoothstep(0.13,0.19,u)*alpha
	result.chewSqueeze = smoothstep(0.19,0.25,u)*alpha
	result.chewBend = (0.32*smoothstep(0.015,0.14,u)+0.58*smoothstep(0.14,0.42,u) \
		+0.10*smoothstep(0.42,0.60,u))*alpha
	result.chewSquint = group.eye_depth*smoothstep(-group.eye_lead,group.rest*0.12,elapsed)*alpha
	for burst in group.shiver_count:
		var start: float = 0.24+burst*0.52/group.shiver_count
		var span: float = 0.52/group.shiver_count*0.76
		var phase := clampf((u-start)/span,0.0,1.0)
		var envelope := smoothstep(0.0,0.16,phase)*(1.0-smoothstep(0.18,1.0,phase))
		var strength := 1.0 if burst == group.shiver_count-1 else (0.94 if burst == group.shiver_count-2 else 0.80)
		result.chewShiver += envelope*sin((u-start)*group.rest*TAU*group.shiver_hz+group.shiver_phase)*strength*alpha
	if elapsed < group.rest: return result
	var relief_time: float = elapsed-group.rest
	var body_duration: float = group.relief-SMILE_HOLD
	var r := clampf(relief_time/body_duration,0.0,1.0)
	# Hold the fully formed closed-eye smile while the body keeps settling.
	# All face channels are flat at 0.40, so entering/leaving the hold is smooth.
	var held := clampf(relief_time-body_duration*0.40,0.0,SMILE_HOLD)
	var face_r := clampf((relief_time-held)/body_duration,0.0,1.0)
	# Squeezed artwork -> closed native eyes -> happy mouth -> relaxed reopening.
	result.chewSqueeze = (1.0-smoothstep(0.0,0.16,face_r))*alpha
	result.chewEyeClose = (1.0-smoothstep(0.70,0.99,face_r))*alpha
	result.chewSquint *= 1.0-smoothstep(0.40,0.96,face_r)
	result.chewSwallowMouth = (1.0-smoothstep(0.04,0.20,face_r))*alpha
	result.chewSwallow = (1.0-smoothstep(0.80,1.0,face_r))*alpha
	result.chewReliefSmile = 0.95*smoothstep(0.08,0.28,face_r)*(1.0-smoothstep(0.56,0.88,face_r))*alpha
	result.chewNod = 1.20*(1.0-smoothstep(0.02,0.24,r))*alpha
	result.chewBend = (1.0-smoothstep(0.06,0.63,r))*alpha
	result.chewShiver = 0.0
	# A small upper-body overshoot and softer settle; the support never moves.
	result.chewReliefRock = (smoothstep(0.40,0.63,r)*(1.0-smoothstep(0.66,0.87,r)) \
		-0.18*smoothstep(0.72,0.84,r)*(1.0-smoothstep(0.84,1.0,r)))*alpha
	result.chewReliefLift = smoothstep(0.12,0.40,r)*(1.0-smoothstep(0.54,0.90,r))*alpha
	result.chewAlpha = (smoothstep(0.90,1.0,face_r) if not last else 0.0)*alpha
	return result
