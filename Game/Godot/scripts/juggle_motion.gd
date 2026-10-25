extends RefCounted
## A separate damped limp pose; normal dragging and landing are untouched.
var weight := 0.0
var time := 0.0
var recovery := 1.0
var was_active := false
var sway := 0.0
var sway_speed := 0.0
var limbs := 0.0
var limb_speed := 0.0
var tail := 0.0
var tail_speed := 0.0
var bump_age := 10.0

func struck() -> void: bump_age = 0.0

func prepare(pose: Dictionary, dt: float, playing: bool, held: bool, horizontal_speed: float, face_override := true) -> Dictionary:
	var step := clampf(dt,0,0.1)
	if was_active and not playing: recovery = 0.0
	was_active = playing; recovery += step; time += step; bump_age += step
	weight = move_toward(weight,1.0 if playing else 0.0,step*(9.0 if playing else 4.0))
	if not playing and recovery>0.55 and weight==0.0: return pose
	var steps := maxi(1,ceili(step*240.0)); var h := step/steps
	for i in steps:
		var target := clampf(-horizontal_speed*0.10,-0.22,0.22) if held and playing else 0.0
		sway_speed += ((target-sway)*50.0-sway_speed*6.8)*h
		sway = clampf(sway+sway_speed*h,-0.28,0.28)
		limb_speed += ((-sway*0.85-limbs)*32.0-limb_speed*5.8)*h
		limbs = clampf(limbs+limb_speed*h,-0.25,0.25)
		tail_speed += ((limbs*1.2-tail)*20.0-tail_speed*5.0)*h
		tail = clampf(tail+tail_speed*h,-0.30,0.30)
	var p := pose.duplicate()
	var bump := sin(PI*clampf(bump_age/0.26,0,1))
	p.juggleWeight = weight; p.juggleLimbs = limbs; p.juggleTail = tail
	p.dragHang = maxf(float(p.get("dragHang",0.0)),weight if held else weight*0.45)
	p.dragTilt = clampf(float(p.get("dragTilt",0.0))+sway*weight,-0.45,0.45)
	p.dragBend = float(p.get("dragBend",0.0))+limbs*0.30*weight
	p.dragStretch = lerpf(float(p.get("dragStretch",0.0)),0.025,weight)
	p.dragFace = float(p.get("dragFace",0.0))*(1.0-weight)
	p.walkWeight = 0.0; p.bowlReach = 0.0; p.bowlCalling = false
	if not face_override: return p
	p.dizzyActive = true
	p.dizzyAlpha = 1.0 if playing else 1.0-smoothstep(0.0,0.22,recovery)
	p.dizzyAngle = time*TAU*0.65
	p.dizzyWobble = rad_to_deg(limbs)*0.20
	p.dizzyRehit = bump*0.65
	p.dizzyEyeOverride = true
	p.dizzyOpenness = 0.0 if playing else smoothstep(0.24,0.48,recovery)
	p.landingUpperBounce = float(p.get("landingUpperBounce",0.0))+bump*0.055
	p.fallFace = 0.0
	return p
