extends RefCounted
## One real floor impact -> knee absorption -> optional seated dizziness.
const HIGH_HEIGHT := 0.93 # One visible character height, in window heights.
const HIGH_SPEED := 4.045 # sqrt(2 * 8.8 * HIGH_HEIGHT).
const Recoil = preload("res://scripts/landing_recoil.gd")
const Rehit = preload("res://scripts/rehit_motion.gd")
const KNEE_DURATION := 0.42
const SOFT_DURATION := 1.10
const HARD_DURATION := 3.0
const HARD_SIT_DELAY := 0.06
const HARD_SIT_SPEED := 2.0
var state := "idle"
var age := 0.0
var strength := 0.0
var sit_sent := false
var last_impact := {}
var recoil = Recoil.new()
var rehit = Rehit.new()
var extra_hold := 0.0
const MAX_DIZZY_REMAINING := 30.0
var extension_age := -1.0
var extension_face := Vector2.ZERO
var immediate_dizzy := false
var suspended := false

func set_suspended(value: bool) -> void:
	if value and not suspended and state=="hard": sit_sent = false
	suspended = value

func active() -> bool: return state != "idle"

func start(impact: Dictionary) -> void:
	if impact.is_empty() or active(): return
	last_impact = impact.duplicate()
	state = "hard" if impact.height >= HIGH_HEIGHT or impact.speed >= HIGH_SPEED else "soft"
	immediate_dizzy = state=="hard" and impact.get("immediate_dizzy",false)
	extra_hold = clampf(float(impact.get("dizzy_seconds",HARD_DURATION))-HARD_DURATION,0.0,MAX_DIZZY_REMAINING-HARD_DURATION) if state=="hard" else 0.0
	extension_age = -1.0
	strength = lerpf(0.45, 1.0, smoothstep(0.0, HIGH_SPEED, impact.speed))
	age = 0.0
	sit_sent = false
	recoil.start(impact)
	rehit.reset()
	if immediate_dizzy:
		recoil.compression_velocity *= 1.25
		recoil.angular_velocity *= 0.75

func dizzy_remaining() -> float:
	return maxf(0.0,HARD_DURATION+extra_hold-age) if state=="hard" else 0.0

func extend_dizziness(seconds: float) -> bool:
	if state!="hard" or not is_finite(seconds) or seconds<=0.0: return false
	var current := pose()
	extension_face = Vector2(current.dizzyAlpha,current.dizzyOpenness)
	extension_age = age
	extra_hold = age+minf(MAX_DIZZY_REMAINING,dizzy_remaining()+seconds)-HARD_DURATION
	rehit.bump()
	return true

func cancel() -> void:
	state = "idle"
	age = 0.0
	sit_sent = false
	recoil.reset()
	rehit.reset()
	immediate_dizzy = false
	suspended = false

func update(dt: float, paused: bool = false) -> Dictionary:
	var result := {"sit": false, "sit_speed": HARD_SIT_SPEED, "finished": false}
	if not active() or paused or not is_finite(dt) or dt <= 0.0: return result
	age += minf(dt, 0.1)
	recoil.update(minf(dt, 0.1))
	rehit.update(minf(dt, 0.1))
	if state == "hard" and age >= HARD_SIT_DELAY and not sit_sent and not suspended:
		sit_sent = true
		result.sit = true
	if age >= (HARD_DURATION+extra_hold if state == "hard" else SOFT_DURATION):
		result.finished = true
		state = "idle"
		recoil.reset()
		rehit.reset()
	return result

func pose() -> Dictionary:
	var knee := 0.0
	var alpha := 0.0
	var spin := 0.0
	var openness := 1.0
	var wobble := 0.0
	var upper_sway := 0.0
	var upper_bounce := 0.0
	var upper_pitch := 0.0
	if active():
		var settle := 1.0 - smoothstep(0.75, SOFT_DURATION, age)
		upper_pitch = recoil.angle * settle
		upper_bounce = recoil.compression * settle
	if state == "soft":
		knee = smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(0.10, KNEE_DURATION, age)) * strength
	elif state == "hard":
		# Brief absorption feeds directly into the faster collapse, without a
		# separate crouch/hold before the ordinary seated texture hand-off.
		knee = smoothstep(0.0, 0.07, age) * (1.0 - smoothstep(0.10, 0.30, age))
		alpha = (1.0 if immediate_dizzy else smoothstep(0.20, 0.30, age)) * (1.0 - smoothstep(2.65+extra_hold, 2.78+extra_hold, age))
		# Integrated speed curve: starts near 0.9 turn/s, slows continuously.
		var t := clampf(age - (0.0 if immediate_dizzy else 0.20), 0.0, 2.58+extra_hold)
		spin = TAU * (0.12 * t + 0.78 * (1.0 - exp(-1.05 * t)) / 1.05)
		openness = smoothstep(2.83+extra_hold, 3.0+extra_hold, age)
		# After the pelvis lands, sway a few times rather than a single faint
		# head twitch. Slow down and fade out before the eyes start recovering.
		# Let the first impact lean and opposite recovery read clearly before
		# the independent dizzy head sway starts.
		var sway_time := maxf(0.0, age - 0.50)
		var envelope := smoothstep(0.0, 0.22, sway_time) * exp(-0.22 * minf(sway_time,6.0)) \
			* (1.0 - smoothstep(1.75+extra_hold, 2.15+extra_hold, sway_time))
		var phase_time := minf(sway_time,6.0)
		var phase := TAU * (1.25 * phase_time - 0.065 * phase_time * phase_time + 0.47*maxf(0.0,sway_time-6.0))
		wobble = 14.0 * sin(phase) * envelope
		upper_sway = deg_to_rad(1.1) * sin(phase - 0.45) * envelope
		if extension_age>=0.0:
			var blend := smoothstep(0.0,0.15,age-extension_age)
			alpha = lerpf(extension_face.x,alpha,blend)
			openness = lerpf(extension_face.y,openness,blend)
		upper_bounce += 0.12 * rehit.amount
		upper_pitch -= deg_to_rad(1.0) * rehit.amount
	return {"landingActive": active(), "landingKnee": knee,
		"landingInfluence": smoothstep(0.0, 0.07, age) if active() else 0.0,
		"dizzyActive": state == "hard", "dizzyAlpha": alpha, "dizzyAngle": spin,
		"dizzyEyeOverride": state == "hard" and (immediate_dizzy or age >= 0.20),
		"dizzyOpenness": openness, "dizzyWobble": wobble, "dizzyUpperSway": upper_sway,
		"dizzyRehit": rehit.amount if state == "hard" else 0.0,
		"landingUpperBounce": upper_bounce, "landingUpperTilt": upper_pitch}
