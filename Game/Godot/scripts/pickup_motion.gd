extends RefCounted
## One proximity-gated pickup. Holding persists until another action releases it.
const DURATION := 1.72
const CATCH_TIME := 1.04
const REACH_RATIO := 0.36
const ADMIRE_MIN := 5.0
const ADMIRE_MAX := 6.0
const Bite = preload("res://scripts/bite_motion.gd")
var rng := RandomNumberGenerator.new()
var admire_duration := 5.5
var bite_duration := 1.0
var sparkle_period := 1.16
var sparkle_phase := 0.0
var eat_requested := false
var eating_started := false
var state := "idle"
var age := 0.0
var fade := 0.0
var release_pose: Dictionary = {}

func _init() -> void:
	rng.randomize()

func take_eat_request() -> bool:
	var requested := eat_requested
	eat_requested = false
	return requested

func active() -> bool:
	return state != "idle"

func request(distance: float, pet_height: float) -> bool:
	if active() or not is_finite(distance) or not is_finite(pet_height) \
		or pet_height <= 0.0 or distance < 0.0 or distance > pet_height * REACH_RATIO:
		return false
	state = "waiting"
	age = 0.0
	fade = 1.0
	# Sample once per pickup, so pausing and frame rate cannot change the act.
	admire_duration = rng.randf_range(ADMIRE_MIN, ADMIRE_MAX)
	sparkle_period = rng.randf_range(0.95, 1.35)
	sparkle_phase = rng.randf_range(0.0, TAU)
	bite_duration = rng.randf_range(Bite.MIN_DURATION, Bite.MAX_DURATION)
	eat_requested = false
	eating_started = false
	return true

func cancel(immediate: bool = false) -> void:
	if not active(): return
	eat_requested = false
	if immediate:
		state = "idle"
		fade = 0.0
	else:
		if state == "releasing": return
		release_pose = pose()
		state = "releasing"
		fade = 1.0

func update(dt: float, ready: bool = true, paused: bool = false) -> Dictionary:
	if paused or not is_finite(dt) or dt <= 0.0: return pose()
	dt = minf(dt, 0.1)
	if state == "waiting" and ready: state = "picking"
	if state in ["picking", "holding"]:
		age += dt
		if age >= DURATION: state = "holding"
		if not eating_started and age >= CATCH_TIME + admire_duration + bite_duration * Bite.CHEW_AT:
			eating_started = true
			eat_requested = true
	elif state == "releasing":
		fade = move_toward(fade, 0.0, dt / 0.30)
		if fade == 0.0: state = "idle"
	return pose()

func pose() -> Dictionary:
	var p := {"pickupArms": 0.0, "pickupFlight": 0.0, "pickupAlpha": 0.0,
		"pickupBowl": 0.0, "pickupCatch": 0.0, "pickupLean": 0.0,
		"pickupLook": 0.0, "pickupGrip": 0.0, "pickupGather": 0.0,
		"pickupHeld": false, "pickupHungry": 0.0, "pickupStarEyes": 0.0,
		"pickupHeadTilt": 0.0, "pickupCarry": Vector2.ZERO,
		"pickupStarNear": Vector2(0.85, 1.0), "pickupStarFar": Vector2(0.85, 1.0)}
	p.merge(Bite.sample(-1.0,bite_duration))
	if state == "idle": return p
	if state == "releasing":
		p = release_pose.duplicate()
		var envelope := smoothstep(0.0, 1.0, fade)
		for key in ["pickupArms", "pickupAlpha", "pickupBowl", "pickupCatch", "pickupLean", "pickupLook",
			"pickupHungry", "pickupStarEyes", "pickupHeadTilt", "pickupCarry", "biteAlpha"]:
			p[key] *= envelope
		return p
	p.pickupBowl = 1.0
	if state == "waiting": return p
	# Look first, then open the arms; let the icon approach the prepared hands.
	p.pickupArms = smoothstep(0.10, 0.78, age)
	p.pickupAlpha = smoothstep(0.29, 0.44, age)
	p.pickupGrip = smoothstep(0.76, CATCH_TIME, age)
	p.pickupGather = smoothstep(CATCH_TIME, 1.50, age)
	# Quintic position has zero velocity and acceleration at release/catch.
	var u := clampf((age - 0.34) / (CATCH_TIME - 0.34), 0.0, 1.0)
	p.pickupFlight = u*u*u*(10.0 + u*(-15.0 + 6.0*u))
	# A single soft compression then a smaller rebound, entirely above the waist.
	if age > CATCH_TIME and age < CATCH_TIME + 0.56:
		var t := age - CATCH_TIME
		# Each join has zero velocity, including the initial contact: no kick
		# after the approaching food has already eased to a complete stop.
		p.pickupCatch = 0.82 * smoothstep(0.0,0.13,t) \
			- smoothstep(0.13,0.34,t) + 0.18 * smoothstep(0.34,0.56,t)
	p.pickupLean = lerpf(0.32, 0.24, p.pickupGather) * p.pickupArms + 0.18 * p.pickupCatch
	p.pickupLook = smoothstep(0.0, 0.22, age)
	p.pickupHeld = age >= CATCH_TIME
	var held := maxf(0.0, age - CATCH_TIME)
	var end := CATCH_TIME + admire_duration
	var expression := 1.0 - smoothstep(end, end + 0.10, age)
	# Eyes lead the little mouth; the full craving face stays until eating.
	p.pickupStarEyes = smoothstep(0.29, 0.47, age) * (1.0-smoothstep(end,end+0.22,age))
	p.pickupHungry = smoothstep(0.43, 0.65, age) * expression
	var admire := smoothstep(0.32, 1.10, held) \
		* (1.0 - smoothstep(admire_duration-0.75, admire_duration, held))
	var tilt := smoothstep(0.72, 1.45, held) \
		* (1.0 - smoothstep(admire_duration-1.05, admire_duration-0.20, held))
	p.pickupLean += 0.13 * admire
	p.pickupHeadTilt = 12.0 * tilt
	# Hands and food use the same carried offset, including the small breath.
	p.pickupCarry = Vector2(10.0, -8.0) * admire \
		+ Vector2(0.0, 1.2 * sin(held * TAU / 2.8)) * admire
	var bite := Bite.sample(age-end,bite_duration)
	p.merge(bite,true)
	p.pickupCarry += bite.biteCarry
	p.pickupLean += bite.biteLean
	p.pickupHeadTilt -= 12.0 * bite.biteNod
	for i in 2:
		var t := age - (0.12 if i == 1 else 0.0)
		var wave := 0.5 + 0.5 * sin(t * TAU / sparkle_period \
			+ 0.48 * sin(t * 1.31 + sparkle_phase))
		var catch_flash := smoothstep(CATCH_TIME, CATCH_TIME+0.12, t) \
			* (1.0 - smoothstep(CATCH_TIME+0.12, CATCH_TIME+0.42, t))
		p["pickupStarNear" if i == 0 else "pickupStarFar"] = Vector2(
			clampf(0.70 + 0.28 * wave + 0.18 * catch_flash, 0.0, 1.0),
			0.95 + 0.12 * wave + 0.065 * catch_flash)
	return p
