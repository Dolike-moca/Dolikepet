extends "res://scripts/pickup_motion.gd"
## Continuous meal. All choices are sampled per food/bite, never per frame.
const Chewing = preload("res://scripts/chewing_motion.gd")
const FoodItem = preload("res://scripts/food_item.gd")
const Pose = preload("res://scripts/pickup_pose.gd")
var meal_enabled := false
var foods: Array = []
var current
var current_scale := 1.0
var segments: Array[Dictionary] = []
var cuts := PackedVector4Array()
var neutral_chew: Dictionary = Chewing.new().pose()
var food_end := 0.0
var tail_time := 0.0
var served := 0
var completed := 0
var next_happy := 1
var happy_kind := ""
var happy_start := 0.0
var happy_end := 0.0
var had_choke := false
var choke_food := -1
var style := 0
var previous_style := -1
var style_run := 0
var previous_layout: Dictionary = {}
var handoff_arms := 1.0
var handoff_eyes := 0.0
var handoff_head := 0.0
var handoff_lean := 0.24
var handoff_smile := 0.0
var handoff_release := 0.0
var late_finish := -1.0
var last_tilt_bite := false
var history: Array[Dictionary] = []
var serve_allowed := Callable() # Rechecked for EVERY bowl item, including the first reach.
var source_available := Callable()
var finished_items: Array = []

func take_finished() -> Array:
	var result := finished_items.duplicate()
	finished_items.clear()
	return result

func _may_serve(item) -> bool:
	if item.source.is_empty(): return true
	return (not serve_allowed.is_valid() or serve_allowed.call()) \
		and (not source_available.is_valid() or source_available.call(item))

func request_food(items: Array, distance: float, pet_height: float) -> bool:
	var accepted: Array = []
	for item in items:
		if item != null and item.valid(): accepted.append(item)
	if accepted.is_empty(): return false
	if meal_enabled and state in ["waiting","picking","holding"]:
		if foods.is_empty() and age > food_end: late_finish = food_end+tail_time
		foods.append_array(accepted)
		return true
	if active(): cancel(true)
	meal_enabled = false
	if not super.request(distance,pet_height): return false
	meal_enabled = true
	foods = accepted
	served = 0; completed = 0; had_choke = false
	last_tilt_bite = false
	# One small chance for the entire queue, independent of how many PNGs it contains.
	choke_food = rng.randi_range(1,accepted.size()) if rng.randf()<Chewing.LONG_SWALLOW_CHANCE else -1
	previous_style = -1; style_run = 0
	previous_layout = {}
	handoff_release = 0.0
	history.clear()
	next_happy = rng.randi_range(1,2)
	_begin_food()
	return true

func _begin_food() -> void:
	current = foods.pop_front()
	late_finish = -1.0
	served += 1
	if served > 1:
		var pick := rng.randf()
		style = 0 if pick < 0.55 else (1 if pick < 0.85 else 2)
		if style == previous_style and style_run >= 2: style = (style+1+rng.randi_range(0,1))%3
		style_run = style_run+1 if style == previous_style else 1
		previous_style = style
		admire_duration = rng.randf_range(2.0,2.5) if style == 0 else rng.randf_range(2.5,3.0)
		sparkle_period = rng.randf_range(0.95,1.35)
		sparkle_phase = rng.randf_range(0.0,TAU)
	happy_kind = ""
	if served >= next_happy:
		happy_kind = "savor" if rng.randf() < 0.78 else "finish"
		next_happy = served+rng.randi_range(2,4)
	var count := rng.randi_range(8,10)
	var plan: Array[Dictionary] = current.plan_bites(count,rng)
	current_scale = current.display_scale
	segments.clear()
	cuts.clear()
	var at := CATCH_TIME+admire_duration
	# Partition the food into groups of two or three bites. Avoid leaving a
	# lone final bite that would need a second immediate swallow.
	var swallow_at := PackedInt32Array()
	var planned := 0
	while planned < count:
		var left := count-planned
		var cluster := left if left <= 3 else (2 if left == 4 else rng.randi_range(2,3))
		planned += cluster
		swallow_at.append(planned-1)
	var choke_bite: int = swallow_at[rng.randi_range(0,swallow_at.size()-1)] if served == choke_food else -1
	var food_chokes := 0
	var tilted_bites := 0
	for i in plan.size():
		var swallow := i in swallow_at
		var follow_on := i > 0 and not (i-1 in swallow_at)
		var prepare := rng.randf_range(0.14,0.24) if follow_on else rng.randf_range(0.22,0.36)
		if i > 0: at += prepare
		var tilt := 0.0
		if not last_tilt_bite and rng.randf()<0.15:
			tilt = deg_to_rad(rng.randf_range(4.0,6.0))*(1.0 if rng.randf()<0.5 else -1.0)
			last_tilt_bite = true
			tilted_bites += 1
		else: last_tilt_bite = false
		var lift := rng.randf_range(24.0,32.0)
		var gentle_finish := happy_kind == "finish" and i >= plan.size()-2
		if gentle_finish: lift *= 0.80
		var chew = Chewing.new()
		chew.rng.seed = rng.randi()
		chew.start(0.0,{"groups":1,"chews":2 if rng.randf()<0.70 else 3,"light":true,"swallow":swallow,
			"allow_long":not had_choke and i == choke_bite,"long_chance":1.0})
		had_choke = had_choke or chew.groups[0].long_swallow
		if chew.groups[0].long_swallow: food_chokes += 1
		var duration := rng.randf_range(0.82,1.00)
		if gentle_finish: duration *= 1.14
		var end: float = at+duration*Bite.CHEW_AT+chew.duration
		var smile: bool = swallow and i<count-1 and not chew.groups[0].long_swallow and rng.randf()<0.35
		var gap := rng.randf_range(0.28,0.44) if smile else (rng.randf_range(0.18,0.30) if swallow else rng.randf_range(0.06,0.14))
		segments.append({"start":at,"prepare":prepare,"tilt":tilt,"lift":lift,
			"duration":duration,"chew":chew,"end":end,"open":rng.randf_range(0.68,0.80),"smile":smile,
			"next":end+gap,"plan":plan[i]})
		cuts.append(plan[i].cut)
		at = segments[-1].next
	bite_duration = segments[0].duration
	food_end = segments[-1].end
	tail_time = rng.randf_range(1.4,1.8)
	happy_start = 0.0; happy_end = 0.0
	if happy_kind == "savor":
		var first := rng.randi_range(1,maxi(1,segments.size()-2))
		var last := mini(segments.size()-1,first+rng.randi_range(0,1))
		happy_start = segments[first].start-0.16
		happy_end = segments[last].end+(0.60 if last == segments.size()-1 else 0.12)
	elif happy_kind == "finish":
		happy_start = segments[maxi(0,segments.size()-2)].start-0.16
		happy_end = food_end+1.15
	history.append({"food":current.label,"bites":segments.size(),"happy":happy_kind,
		"style":style,"duration":food_end,"chokes":food_chokes,"tilts":tilted_bites,"swallows":swallow_at.size()})

func take_eat_request() -> bool:
	return false if meal_enabled else super.take_eat_request()

func cancel(immediate: bool = false) -> void:
	if not meal_enabled: super.cancel(immediate); return
	if not active(): return
	foods.clear()
	if immediate:
		state = "idle"; meal_enabled = false; current = null
	else:
		if state == "releasing": return
		release_pose = pose()
		state = "releasing"; fade = 1.0

func update(dt: float, ready: bool = true, paused: bool = false) -> Dictionary:
	if not meal_enabled: return super.update(dt,ready,paused)
	if paused or not is_finite(dt) or dt <= 0.0: return pose()
	dt = minf(dt,0.1)
	if state == "releasing":
		fade = move_toward(fade,0.0,dt/0.30)
		if fade == 0.0:
			state = "idle"; meal_enabled = false; current = null
		return pose()
	if state == "waiting" and ready: state = "picking"
	if state in ["picking","holding"]:
		if age < CATCH_TIME and not _may_serve(current):
			cancel(false)
			return pose()
		age += dt
		if age >= DURATION: state = "holding"
		var finish: float = food_end+(tail_time if foods.is_empty() else (1.15 if happy_kind == "finish" else 0.34))
		if late_finish > 0.0: finish = late_finish
		if age >= finish:
			completed += 1
			finished_items.append(current)
			# Never skip a blocked FIFO head and take a younger file instead.
			if not foods.is_empty() and not _may_serve(foods[0]): foods.clear()
			if not foods.is_empty():
				var final_pose := pose()
				previous_layout = {"near":final_pose.foodNear,"far":final_pose.foodFar}
				handoff_arms = final_pose.pickupArms
				handoff_eyes = final_pose.chewEyeClose
				handoff_head = final_pose.pickupHeadTilt
				handoff_lean = final_pose.pickupLean
				handoff_smile = final_pose.chewReliefSmile
				handoff_release = final_pose.get("holdRelease",0.0)
				age -= finish
				_begin_food()
				state = "picking"
			else:
				state = "idle"; meal_enabled = false; current = null
	return pose()

func pose() -> Dictionary:
	if not meal_enabled: return super.pose()
	if state == "releasing":
		var released := release_pose.duplicate()
		var weight := smoothstep(0.0,1.0,fade)
		for key in ["pickupArms","pickupAlpha","pickupBowl","pickupLean","pickupLook","pickupHungry",
			"pickupStarEyes","pickupHeadTilt","pickupCarry","pickupIconTilt","biteAlpha","chewAlpha","chewSwallowMouth",
			"chewNod","chewSquint","chewSqueeze","chewEyeClose","chewBend","chewShiver",
			"chewSwallow","chewReliefSmile","chewReliefLift","chewReliefRock"]:
			released[key] *= weight
		return released
	var p := super.pose()
	p.merge(Bite.sample(-1.0,bite_duration),true)
	p.merge(neutral_chew,true)
	p.mealActive = true
	p.foodItem = current
	p.foodScale = current_scale
	p.foodCuts = cuts
	p.foodTop = 0.0
	p.foodCutIndex = -1
	p.foodCutProgress = 0.0
	p.foodRemaining = 1.0
	p.pickupBowlLook = 0.0
	p.pickupIconTilt = 0.0
	var initial: Dictionary = segments[0].plan.before
	p.foodPart = initial
	var layout: Dictionary = current.layout(initial,current_scale)
	if state == "waiting":
		_apply_layout(p,layout)
		return p
	if served > 1:
		p.pickupArms = lerpf(handoff_arms,1.0,smoothstep(0.0,0.50,age))
		p.pickupLean = lerpf(handoff_lean,0.24,smoothstep(0.0,0.35,age))+0.18*p.pickupCatch
		p.pickupHeadTilt = handoff_head*(1.0-smoothstep(0.0,0.35,age))
		p.pickupCarry = Vector2.ZERO
		var admire := smoothstep(CATCH_TIME,CATCH_TIME+0.25,age) \
			* (1.0-smoothstep(segments[0].start-0.25,segments[0].start,age))
		p.pickupHungry = smoothstep(CATCH_TIME-0.08,CATCH_TIME+0.12,age) \
			* (1.0-smoothstep(segments[0].start,segments[0].start+0.10,age))
		p.pickupHeadTilt += (12.0 if style == 1 else 4.0)*admire
		p.pickupCarry = Vector2(10.0,-9.0)*admire if style == 2 else Vector2(0.0,-4.0)*admire
		p.chewEyeClose = handoff_eyes*(1.0-smoothstep(0.0,0.28,age))
		p.chewReliefSmile = handoff_smile*(1.0-smoothstep(0.0,0.25,age))
	if age >= segments[0].start-segments[0].prepare:
		# Keep the inherited short craving-to-open-mouth fade on the first bite.
		var entry := smoothstep(segments[0].start-segments[0].prepare,segments[0].start,age)
		p.pickupHeadTilt *= 1.0-entry
		p.pickupCarry *= 1.0-entry
		p.pickupLean = lerpf(p.pickupLean,0.24,entry)
		var index := segments.size()-1
		for i in segments.size():
			if age < segments[i].next: index = i; break
		var segment: Dictionary = segments[index]
		var local: float = age-segment.start
		var bite: Dictionary = Bite.sample(local,segment.duration)
		bite.biteOpen *= segment.open
		bite.biteNod *= 0.80
		p.merge(bite,true)
		p.foodCutIndex = index
		p.foodCutProgress = smoothstep(segment.duration*0.56,segment.duration*0.62,local)
		var plan: Dictionary = segment.plan
		var u: float = local/segment.duration
		var prepare := smoothstep(-segment.prepare,-0.04,local)*(1.0-smoothstep(0.0,0.25,u))
		var lift := smoothstep(0.08,0.42,u)*(1.0-smoothstep(0.60,1.15,u))
		var recoil := smoothstep(0.62,0.78,u)*(1.0-smoothstep(0.78,1.15,u))
		# B2: a little anticipation, a chest-level lift and a soft return.
		# There is deliberately no target at the mouth or at the image's edge.
		p.pickupCarry += Vector2(6.0,-4.0)*prepare+Vector2(4.0,-segment.lift)*lift+Vector2(-1.5,3.0)*recoil
		p.pickupIconTilt = segment.tilt*lift
		p.pickupLean += 0.04*prepare+0.08*lift-0.01*recoil
		p.pickupHeadTilt += -8.0*bite.biteNod+rad_to_deg(p.pickupIconTilt)*0.65
		p.foodRemaining = lerpf(plan.before.mass,plan.after.mass,p.foodCutProgress)/initial.mass
		p.foodTop = lerpf(plan.before.top,plan.after.top,p.foodCutProgress)
		# The bite disappears at closure; palms settle onto the remaining piece
		# during the return, rather than snapping sideways with the cut.
		p.foodPart = FoodItem.blend_parts(plan.before,plan.after,smoothstep(0.56,1.10,u))
		layout = current.layout(p.foodPart,current_scale)
		var chew = segment.chew
		if bite.biteChewAge >= 0.0:
			chew.age = bite.biteChewAge
			p.merge(chew.pose(),true)
		if plan.after.mass == 0.0 and p.foodCutProgress >= 1.0: p.pickupAlpha = 0.0
		if index == segments.size()-1 and not foods.is_empty():
			var look_at: float = segment.start+segment.duration*Bite.CHEW_AT+chew.groups[0].chew_end-0.35
			p.pickupBowlLook = smoothstep(look_at,look_at+0.40,age)
		var happy := 0.0
		if not happy_kind.is_empty():
			happy = smoothstep(happy_start,happy_start+0.28,age) \
				* (1.0-smoothstep(happy_end-0.28,happy_end,age))
		# A strained swallow takes over completely; delight resumes after relief.
		var strain: float = maxf(p.chewBend,p.chewSqueeze)
		happy *= 1.0-smoothstep(0.0,0.12,strain)
		p.chewEyeClose = maxf(p.chewEyeClose,happy)
		p.pickupHeadTilt += happy*(7.0+3.0*sin((age-happy_start)*TAU/2.8))
		p.pickupLean += happy*0.025*sin((age-happy_start)*TAU/2.3)
		if happy_kind == "finish": p.pickupCarry += Vector2(5.0,-3.0)*happy
		var free_mouth := 1.0-clampf(p.biteAlpha+p.chewAlpha+p.chewSwallowMouth,0.0,1.0)
		p.chewReliefSmile = maxf(p.chewReliefSmile,0.92*happy*free_mouth)
		if segment.smile:
			var smile := smoothstep(segment.end-0.08,segment.end+0.10,age) \
				* (1.0-smoothstep(segment.next-0.12,segment.next,age))
			p.chewReliefSmile = maxf(p.chewReliefSmile,0.70*smile*free_mouth)
			p.chewSquint = maxf(p.chewSquint,0.18*smile)
		if not happy_kind.is_empty() and age >= happy_end and age < food_end:
			p.pickupStarEyes = smoothstep(happy_end,happy_end+0.18,age)*(1.0-smoothstep(happy_end+1.20,happy_end+1.60,age))
		if age >= food_end:
			var end_age := age-food_end
			var ending := foods.is_empty() or late_finish > 0.0
			var finish: float = tail_time if ending else (1.15 if happy_kind == "finish" else 0.34)
			var delight := smoothstep(0.0,0.20,end_age)*(1.0-smoothstep(finish-0.35,finish,end_age))
			if ending or happy_kind == "finish":
				p.chewEyeClose = maxf(p.chewEyeClose,delight)
				p.chewReliefSmile = maxf(p.chewReliefSmile,0.95*delight)
				p.chewReliefLift = 0.35*delight
			p.pickupAlpha = 0.0
			if ending:
				p.pickupArms = 1.0-smoothstep(finish-0.65,finish,end_age)
				p.pickupLean *= p.pickupArms
				p.pickupBowl = 1.0-smoothstep(finish-0.50,finish,end_age)
	_apply_layout(p,layout)
	p.holdRelease = 1.0-smoothstep(0.15,0.45,p.foodRemaining)
	if served>1:
		p.holdRelease = lerpf(handoff_release,p.holdRelease,smoothstep(0.0,CATCH_TIME,age))
	return p

func _apply_layout(p: Dictionary, layout: Dictionary) -> void:
	# Tilt around the supporting near palm so the wrist never chases a corner.
	p.foodHold = layout.near+(layout.hold-layout.near).rotated(p.pickupIconTilt)
	p.foodSourceCenter = layout.source
	p.foodNear = layout.near
	p.foodFar = layout.near+(layout.far-layout.near).rotated(p.pickupIconTilt)
	if served > 1 and not previous_layout.is_empty():
		var reach := smoothstep(0.0,CATCH_TIME,age)
		p.foodNear = previous_layout.near.lerp(p.foodNear,reach)
		p.foodFar = previous_layout.far.lerp(p.foodFar,reach)
	if p.pickupArms>0.999 and p.pickupFlight>0.999:
		p.pickupCarry = Pose.fit_carry(p.foodNear,p.foodFar,p.pickupCarry,p.pickupCatch)
