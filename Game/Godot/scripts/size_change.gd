extends RefCounted
## One summoned prop per enlargement; never enters the file-meal queue.
const Sizes = preload("res://scripts/pet_size.gd")
const FoodItem = preload("res://scripts/food_item.gd")
const Pickup = preload("res://scripts/pickup_motion.gd")
const Bite = preload("res://scripts/bite_motion.gd")
const RAISE := 0.30
const APPEAR := 0.20
const HOLD := 0.28
const EAT := 3.50
const GROW := 1.0
const SHRINK := 0.40
var target := Sizes.BASE
var state := "idle"
var age := 0.0
var size_age := 0.0
var start_size := 300.0
var value := 300.0
var charged := false
var release_arms := false
var finished := false
var item
var plans: Array[Dictionary] = []
var cuts := PackedVector4Array()
var rest_pose := Pickup.new().pose()

func initialize(pixels: int) -> void:
	target = Sizes.nearest(pixels)
	value = target
	state = "idle"
	charged = false
	release_arms = false
	finished = false

func pending() -> bool: return state != "idle"
func performing() -> bool: return state in ["summon", "grow", "shrink"]

func request(pixels: int, current: int) -> void:
	var requested := Sizes.nearest(pixels)
	if pending() and requested == target: return
	target = requested
	finished = false
	if not pending():
		value = current
		charged = false
		state = "waiting" if target != current else "idle"
		age = 0.0
	elif state in ["grow", "shrink"]:
		# Retarget from the currently displayed size without summoning another prop.
		start_size = value
		size_age = 0.0
		if target > value and not charged:
			state = "waiting"
			age = 0.0

func _prepare_item() -> void:
	if item != null: return
	item = FoodItem.from_texture(load("res://assets/feeding/magic_mushroom.png"), "体型蘑菇")
	# Register its opaque silhouette for this prop only. General file icons keep
	# their approved square grip, including transparent padding.
	var image: Image = item.texture.get_image()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var low := image.get_size()
	var high := Vector2i.ZERO
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a > 0.12:
				low = low.min(Vector2i(x,y))
				high = high.max(Vector2i(x+1,y+1))
	item.bounds = Rect2(low,high-low)
	item.display_scale = 450.0/item.bounds.size.x
	# Five small top-down bites, leaving a visible stem for the final mouthful.
	var profile:=PackedFloat32Array();profile.resize(FoodItem.PROFILE_COLUMNS)
	for cut in [Vector4(0.5,-0.38,0.62,0.62),Vector4(0.5,-0.16,0.72,0.64),
		Vector4(0.5,0.02,0.78,0.60),Vector4(0.5,0.14,0.90,0.60),Vector4(0.5,0.98,0.72,0.50)]:
		var before:Dictionary=item.remaining(profile)
		profile=FoodItem.cut_profile(profile,cut)
		plans.append({"before":before,"after":item.remaining(profile),"cut":cut})
		cuts.append(cut)

func update(dt: float, current: int, blocked: bool) -> void:
	finished = false
	if not pending() or not is_finite(dt) or dt <= 0.0: return
	dt = minf(dt,0.1)
	if blocked:
		# Immediate user actions own the rig. Resume a consumed mushroom's growth
		# later, but an interrupted, uneaten mushroom will be summoned again.
		state = "waiting"
		age = 0.0
		value = current
		release_arms = false
		return
	if state == "waiting":
		age += dt
		if age < 0.16: return
		value = current
		start_size = current
		size_age = 0.0
		age = 0.0
		if target == current:
			_finish()
		elif target < current:
			state = "shrink"
		elif charged:
			state = "grow"
		else:
			_prepare_item()
			state = "summon"
		return
	age += dt
	if state == "summon":
		if age >= RAISE+APPEAR+HOLD+EAT:
			charged = true
			release_arms = true
			state = "grow"
			age = 0.0
			size_age = 0.0
			start_size = current
	elif state in ["grow", "shrink"]:
		size_age += dt
		var duration := GROW if state == "grow" else SHRINK
		value = lerpf(start_size,float(target),smoothstep(0.0,duration,size_age))
		if size_age >= duration and (state == "shrink" or age >= GROW): _finish()

func _finish() -> void:
	value = target
	state = "idle"
	charged = false
	finished = true

func flash() -> float:
	if state != "grow" or age >= GROW: return 0.0
	return 0.84 * pow(sin(PI*3.0*age/GROW),2.0)

func pose() -> Dictionary:
	if not state in ["summon", "grow"]: return {}
	var p := rest_pose.duplicate()
	var release := (1.0-smoothstep(0.0,0.24,age) if release_arms else 0.0) if state == "grow" else 1.0
	var raise := smoothstep(0.0,RAISE,age) if state == "summon" else release
	p.pickupArms = raise
	p.pickupFlight = 1.0
	p.pickupGrip = 1.0
	p.pickupGather = 1.0
	p.pickupLean = 0.08*raise
	p.pickupLook = raise
	p.pickupHeld = true
	p.pickupAlpha = smoothstep(RAISE,RAISE+APPEAR,age) if state == "summon" else 0.0
	p.mealActive = true
	p.sizeMushroom = true
	p.foodItem = item
	p.foodScale = item.display_scale
	p.foodCuts = cuts
	p.foodCutIndex = -1
	p.foodCutProgress = 0.0
	p.foodRemaining = 1.0
	p.foodPart = plans[0].before
	var eat_at:=RAISE+APPEAR+HOLD
	p.sizeFoodApproach=smoothstep(eat_at,eat_at+0.325,age) if state=="summon" else 1.0
	p.sizeFoodLift=lerpf(0.18,1.0,p.sizeFoodApproach)
	# Turn the supporting far palm back before lowering it over one second.
	# Bite cuts change mass quickly, so they must not drive this handoff.
	var eat_age:=age-eat_at
	p.sizeFarHandOpen=1.0-smoothstep(1.55,1.85,eat_age) if state=="summon" else 0.0
	p.sizeFarSupport=1.0-smoothstep(1.85,2.85,eat_age) if state=="summon" else 0.0
	var delight:=smoothstep(0.35,0.49,age) if state=="summon" else 1.0-smoothstep(0.32,0.78,age)
	p.chewEyeClose=delight
	p.chewReliefSmile=delight*0.75
	if state == "summon" and age >= eat_at:
		var elapsed := age-eat_at
		var duration:=EAT/float(plans.size())
		var bite_index := mini(plans.size()-1,int(elapsed/duration))
		var local := elapsed-bite_index*duration
		var bite: Dictionary = Bite.sample(local,duration)
		p.merge(bite,true)
		p.biteAlpha = smoothstep(0.0,0.06,elapsed)
		p.biteOpen *= 0.82
		p.pickupCarry = bite.biteCarry
		p.pickupHeadTilt = -3.0*bite.biteNod
		p.foodCutIndex = bite_index
		p.foodCutProgress = bite.biteCut
		p.foodPart = FoodItem.blend_parts(plans[bite_index].before,plans[bite_index].after,bite.biteCut)
		p.foodRemaining = lerpf(plans[bite_index].before.mass,plans[bite_index].after.mass,bite.biteCut)
		if bite_index == plans.size()-1 and bite.biteCut >= 1.0: p.pickupAlpha = 0.0
	if state == "grow":
		p.biteAlpha = release
		p.biteOpen = 0.0
		p.foodPart = plans[-1].after
		p.foodRemaining = 0.0
	# Keep the remnant layout reusable; the mushroom grip follows the stem.
	# Duplicate the frame data so the immutable bite plans remain reusable.
	p.foodPart = p.foodPart.duplicate()
	p.foodPart.hold_grip.x = item.bounds.get_center().x
	var layout: Dictionary = item.layout(p.foodPart)
	p.foodHold = layout.hold
	p.foodNear = layout.near
	p.foodFar = layout.far
	p.foodSourceCenter = layout.source
	p.holdRelease = 1.0-smoothstep(0.1,0.3,p.foodRemaining)
	return p
