extends RefCounted
## Reuse the accepted juggling limbs, but let LandingMotion own the stun clock
## and eye recovery. Picking up, dropping and re-grabbing never restart either.
const Limp = preload("res://scripts/juggle_motion.gd")
var motion = Limp.new()

func prepare(pose: Dictionary, dt: float, airborne: bool, held: bool, speed: float) -> Dictionary:
	var p: Dictionary = motion.prepare(pose,dt,airborne,held,speed,false)
	if motion.weight==0.0: return p
	p = p.duplicate()
	var support: float = 1.0-motion.weight
	for key in ["landingInfluence","landingKnee","dizzyUpperSway","landingUpperTilt"]:
		p[key] = float(p.get(key,0.0))*support
	# A re-hit still gives the small nod/compression, even while hanging.
	p.landingUpperBounce = float(p.get("landingUpperBounce",0.0))*support+float(p.get("dizzyRehit",0.0))*0.055*motion.weight
	p.dizzyWobble = lerpf(float(p.get("dizzyWobble",0.0)),rad_to_deg(motion.limbs)*0.20,motion.weight)
	p.fallFace = float(p.get("fallFace",0.0))*support
	return p
