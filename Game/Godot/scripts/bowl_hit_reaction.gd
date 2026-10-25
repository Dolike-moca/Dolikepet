extends RefCounted
## A light knock borrows the drag face; a hard knock requests existing dizziness.
const LIGHT_SECONDS := 0.78
var kind := ""
var age := 0.0
var hard_started := false
var cooldown := 0.0
var grounded := true
var dizzy_seconds := 3.0
var immediate_dizzy := false

func active() -> bool: return not kind.is_empty()
func waiting_for_floor() -> bool: return kind=="hard" and not hard_started
func start(value: String, duration := 3.0, direct_dizzy := false) -> bool:
	if active() or cooldown>0.0 or value not in ["light","hard"]: return false
	kind = value; age = 0.0; hard_started = false
	immediate_dizzy = direct_dizzy and kind=="hard"
	dizzy_seconds = clampf(duration,3.0,6.0)
	return true
func extend_pending(duration: float) -> bool:
	if not waiting_for_floor(): return false
	dizzy_seconds = minf(30.0,dizzy_seconds+clampf(duration,3.0,6.0))
	return true
func cancel() -> void:
	kind = ""; age = 0.0; hard_started = false; cooldown = 0.5
	immediate_dizzy = false
func update(dt: float, on_floor: bool, landing_active: bool, paused: bool) -> bool:
	if paused: return false
	var step := clampf(dt,0.0,0.05)
	cooldown = maxf(0.0,cooldown-step); grounded = on_floor
	if not active(): return false
	age += step
	if kind=="light":
		if age>=LIGHT_SECONDS: cancel()
	elif not hard_started:
		if on_floor: hard_started = true; return true
	elif not landing_active: cancel()
	return false

func prepare(pose: Dictionary) -> Dictionary:
	if not active(): return pose
	var p := pose.duplicate()
	p.bowlHitActive = true
	# Keep the held icon/arm anchors while pausing all bite and chewing clocks.
	for key in ["chewNod","chewReliefLift","chewReliefSmile","chewSquint","chewEyeClose",
		"chewBend","chewShiver","chewSwallow","chewReliefRock","pickupHeadTilt"]:
		p[key] = 0.0
	p.bowlReach = pose.get("bowlReach",0.0)*(1.0-smoothstep(0.0,0.12,age))
	p.bowlCalling = false; p.bowlTilt = 0.0
	if immediate_dizzy and waiting_for_floor():
		# Show the head-hit expression immediately even if the physical body
		# still has to reach the floor before beginning its seated motion.
		p.dizzyActive = true; p.dizzyAlpha = 1.0; p.dizzyEyeOverride = true
		p.dizzyOpenness = 0.0; p.dizzyAngle = age*TAU*0.9
		p.dragFace = 0.0; p.mouth = 0.0
		return p
	if kind=="light" or waiting_for_floor():
		var face := smoothstep(0.0,0.045,age)*(1.0-smoothstep(0.40,0.55,age)) if kind=="light" else smoothstep(0.0,0.045,age)
		p.dragHeld = face>0.00001
		p.dragFace = maxf(pose.get("dragFace",0.0),face)
		p.mouth = 0.0
		var bump := sin(PI*clampf(age/0.62,0.0,1.0))
		p.headZ = lerpf(pose.headZ,-8.0,bump)
		p.headY = lerpf(pose.headY,-0.12,bump)
		p.landingKnee = maxf(pose.get("landingKnee",0.0),0.48*bump if grounded else 0.0)
		p.landingUpperBounce = pose.get("landingUpperBounce",0.0)+0.055*bump
	return p
