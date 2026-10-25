extends SceneTree
const Meal = preload("res://scripts/meal_motion.gd")
const FoodItem = preload("res://scripts/food_item.gd")
const PickupPose = preload("res://scripts/pickup_pose.gd")
const Burger = preload("res://assets/feeding/burger.png")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("MEAL: "+message)

static func fixture(kind: int) -> Image:
	var image := Image.create(160,160,false,Image.FORMAT_RGBA8)
	for y in 160:
		for x in 160:
			var q := Vector2(x,y)-Vector2(80,80)
			var visible := false
			match kind:
				0: visible = absf(q.x)<12 and absf(q.y)<65 # tall
				1: visible = absf(q.x)<70 and absf(q.y)<10 # wide
				2: visible = q.length()>25 and q.length()<60 # hollow
				3: visible = (q-Vector2(35,-25)).length()<13 or (q-Vector2(-30,30)).length()<19 # pieces
				4: visible = q.length()<12 # padded
				5: visible = q.length()<50 # translucent
				6: visible = false
			if visible: image.set_pixel(x,y,Color(0.3,0.75,0.9,0.08 if kind == 5 else 1.0))
	return image

func masks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for kind in 7:
		var image := fixture(kind)
		var food = FoodItem.from_texture(ImageTexture.create_from_image(image),"fixture-%d"%kind)
		if kind == 6:
			check(not food.valid(),"fully transparent food was accepted")
			continue
		check(food.valid(),"valid PNG shape rejected")
		var plan: Array[Dictionary] = food.plan_bites(10,rng)
		var mass: float = plan[0].before.mass
		for part in plan:
			check(part.after.mass < mass,"bite removed no visible food")
			mass = part.after.mass
		check(mass == 0.0,"plan left fragments")
		check(plan[0].before.top == 0.0 and plan[-1].after.top == 1.0,"layers do not cover the full icon height")
		for i in plan.size():
			check(plan[i].after.top>=plan[i].before.top,"an eaten layer grew back")
			if i>0: check(plan[i].before == plan[i-1].after,"layer boundary grows back or skips a section")
		check(food.bounds == Rect2(0,0,160,160),"icon art/transparent padding changed the square frame")
		var path := "res://../../_work/tests/meal-fixture-%d.png"%kind
		image.save_png(path)
		var disk = FoodItem.from_png(ProjectSettings.globalize_path(path))
		check(disk.valid() and disk.bounds == food.bounds,"PNG disk load differs from texture analysis")

func simulate(fps: int, seed_value: int) -> Dictionary:
	var meal = Meal.new()
	meal.rng.seed = seed_value
	var food = FoodItem.from_texture(Burger,"burger")
	check(meal.request_food([food,food,food],100,600),"meal request refused")
	var last_served := 1
	var previous := 1.0
	var happy_bites := 0
	var happy_chews := 0
	var elapsed := 0.0
	var snapshot: Dictionary = {}
	for f in fps*150:
		var p: Dictionary = meal.update(1.0/fps)
		elapsed += 1.0/fps
		if not meal.active(): break
		if meal.served != last_served:
			check(previous < 0.00001,"next food appeared before previous was eaten")
			check(p.pickupArms > 0.95,"arms reset between foods")
			previous = 1.0; last_served = meal.served
		var remaining: float = p.foodRemaining
		check(remaining <= previous+0.00001,"food grew back between bites")
		previous = remaining
		check(is_finite(p.pickupCarry.x) and is_finite(p.pickupCarry.y),"invalid carry position")
		check(p.biteAlpha+p.chewAlpha+p.chewSwallowMouth < 1.00001,"mouth weights overlap")
		if p.chewEyeClose > 0.99:
			if p.biteOpen > 0.55: happy_bites += 1
			if p.chewOffset.length()>0.5 and p.chewAlpha>0.9: happy_chews += 1
		if f == fps*8:
			snapshot = p.duplicate()
			for pause_frame in fps: meal.update(1.0/fps,true,true)
			check(meal.pose() == snapshot,"pause changed choices or food consumption")
	check(not meal.active() and meal.completed == 3,"queue failed to finish exactly three foods")
	check(meal.pose().pickupArms == 0.0 and meal.pose().pickupAlpha == 0.0,"meal left hands/food active")
	check(happy_bites > 0 and happy_chews > 0,"closed-eye delight did not include both biting and chewing")
	var chokes := 0
	for entry in meal.history: chokes += entry.chokes
	check(chokes <= 1,"more than one strained swallow in the queue")
	print("MEAL fps ",fps," seed ",seed_value," elapsed ",elapsed," choices ",meal.history)
	return {"elapsed":elapsed,"history":meal.history.duplicate(true)}

func append_and_cancel() -> void:
	var food = FoodItem.from_texture(Burger)
	var meal = Meal.new()
	meal.rng.seed = 32
	meal.request_food([food],100,600)
	meal.state = "holding"
	meal.age = meal.food_end-0.05
	var before: Dictionary = meal.pose()
	meal.request_food([food,food],100,600)
	check(meal.pose().foodCutProgress == before.foodCutProgress and meal.served == 1,"appending restarted current food")
	for frame in 1000: meal.update(0.1)
	check(meal.completed == 3 and not meal.active(),"appended queue did not finish")
	meal.request_food([food,food],100,600)
	for frame in 70: meal.update(0.1)
	meal.cancel()
	for frame in 5: meal.update(0.1)
	check(not meal.active() and meal.foods.is_empty(),"cancel left queued actions")
	meal.request_food([food],100,600)
	meal.cancel(true)
	check(not meal.active() and meal.pose().pickupAlpha == 0.0,"grab did not immediately clear food")
	meal.request_food([food],100,600)
	meal.state = "holding"
	meal.age = meal.food_end+meal.tail_time*0.8
	var finishing: Dictionary = meal.pose()
	meal.request_food([food],100,600)
	var appended: Dictionary = meal.pose()
	check(absf(appended.pickupArms-finishing.pickupArms)<0.00001 and absf(appended.chewEyeClose-finishing.chewEyeClose)<0.00001,
		"late append snapped the finishing hands/eyes")

func variety_and_boundaries() -> void:
	var food = FoodItem.from_texture(Burger)
	var savor := 0
	var content := 0
	var chokes := 0
	var max_jump := 0.0
	var tilt_count := 0
	var bite_count := 0
	var short_chews := 0
	var swallow_count := 0
	var max_palm_error := 0.0
	var worst_palm := ""
	var far_backward := -INF
	var far_foldback := -INF
	var far_stretch := 0.0
	for seed_value in range(1500,1700):
		var meal = Meal.new()
		meal.rng.seed = seed_value
		meal.request_food([food,food,food,food,food,food],100,600)
		meal.state = "holding"
		var previous_tilt := false
		while meal.active():
			check(meal.current_scale == food.display_scale,"a bite plan resized the icon")
			check(meal.segments.size()>=8 and meal.segments.size()<=10,"food is not divided into 8–10 small bites")
			var cluster := 0
			for segment in meal.segments:
				bite_count += 1
				cluster += 1
				var group: Dictionary = segment.chew.groups[0]
				check(group.chews>=2 and group.chews<=3,"small bite chewing is too long")
				check(segment.open>=0.68 and segment.open<=0.80,"small bite opens too wide")
				if group.swallow:
					swallow_count += 1
					check(cluster>=2 and cluster<=3,"swallow did not follow two or three bites")
					cluster = 0
				else:
					short_chews += 1
					check(group.rest == 0.0 and not group.long_swallow,"light chew includes a swallow/rest")
					for phase in [0.0,0.5,0.95,1.0,1.05]:
						segment.chew.age = group.chew_end*phase
						var light_pose: Dictionary = segment.chew.pose()
						check(light_pose.chewSwallowMouth == 0.0 and light_pose.chewNod == 0.0 and light_pose.chewSquint == 0.0,"between-bite chew plays a gulp")
					segment.chew.age = group.chew_end-0.00001
					check(segment.chew.pose().chewAlpha<0.0001,"light chew snaps off at its end")
				var removed: float = segment.plan.before.mass-segment.plan.after.mass
				check(removed>=0.06 and removed<=0.17,"bite is empty or too large: "+str(removed))
				if segment != meal.segments[-1]:
					check(segment.plan.cut.y<=segment.plan.before.top+0.001,"circle detached from the eaten upper edge")
				var tilted: bool = segment.tilt != 0.0
				if tilted: tilt_count += 1
				check(not (tilted and previous_tilt),"C slanted bites repeated consecutively")
				previous_tilt = tilted
				check(not tilted or absf(rad_to_deg(segment.tilt))>=4.0 and absf(rad_to_deg(segment.tilt))<=6.0,"C tilt exceeds the agreed small angle")
				for phase in [-0.2,0.0,0.42,0.57,0.62,0.85,1.15,2.0]:
					meal.age = segment.start+segment.duration*phase
					var p: Dictionary = meal.pose()
					check(p.pickupCarry.length()<40.0,"icon reaches toward the mouth instead of a little chest lift")
					var held: Dictionary = p.foodPart
					check(p.foodSourceCenter == held.center,"remnant registration changed")
					check(p.foodNear.distance_to(FoodItem.NEAR_HOLD)<17.0,"near wrist chased a bite instead of staying in its embrace")
					for key in ["near","far"]:
						var grip: Vector2 = held[key]
						var expected: Vector2 = p.foodHold+((grip-held.center)*food.display_scale).rotated(p.pickupIconTilt)
						check(expected.distance_to(p.foodNear if key == "near" else p.foodFar)<0.01,"hands failed to follow the remaining layer/tilt")
						if key == "near": check(grip.y >= held.bounds.position.y and grip.y <= food.bounds.end.y,"near hand is above the remaining food")
						if p.pickupAlpha>0.01:
							var id := "ArtMesh19" if key == "near" else "ArtMesh26"
							var target: Vector2 = p.foodNear if key == "near" else p.foodFar
							var bone := PickupPose.solve(id,1.0,p.pickupCatch,1.0,1.0,p.pickupCarry,target)
							var palm := PickupPose.arm_point(bone.palm,bone)
							if key == "near": check(rad_to_deg(bone.lower)<45.0,"near wrist/cuff folded instead of a relaxed diagonal embrace")
							var error := palm.distance_to(target+p.pickupCarry+Vector2(0,11.0*p.pickupCatch))
							if error>max_palm_error:
								max_palm_error = error
								worst_palm = "seed %d %s phase %.2f target %s"%[seed_value,key,phase,target]
							if key == "far":
								check(rad_to_deg(bone.lower)<20.0,"far arm bent beyond a gentle forward reach")
								var root := PickupPose.arm_point(bone.shoulder,bone)
								var near_root: Vector2 = PickupPose.Walking.SHOULDERS.ArtMesh19
								var shoulder_slope := rad_to_deg((root-near_root).angle_to(Vector2.LEFT))
								check(shoulder_slope>4.0 and shoulder_slope<8.0,"far shoulder must sit slightly below the near shoulder")
								far_backward = maxf(far_backward,palm.x-bone.shoulder.x)
								far_foldback = maxf(far_foldback,palm.x-PickupPose.arm_point(bone.elbow,bone).x)
								far_stretch = maxf(far_stretch,bone.reach_scale)
					if p.foodCutProgress>0.0: check(p.biteOpen<0.31,"a chunk disappeared before the mouth closed")
			check(cluster == 0,"last morsel was not swallowed before the next food")
			check(meal.food_end<42.0,"small bites unnecessarily stretch one food past 42 seconds")
			# All body and face channels remain continuous at each nibble handoff.
			for s in meal.segments.size()-1:
				meal.age = meal.segments[s].next-0.000001
				var pre: Dictionary = meal.pose()
				meal.age += 0.000002
				var post: Dictionary = meal.pose()
				for key in ["biteAlpha","chewAlpha","chewSquint","chewEyeClose","chewReliefSmile","pickupHeadTilt","pickupLean","pickupIconTilt"]:
					check(absf(pre[key]-post[key])<0.001,"nibble handoff jumps: "+key)
				check(pre.pickupCarry.distance_to(post.pickupCarry)<0.001,"hands jump between small bites")
			meal.age = meal.segments[0].start-0.000001
			var craving: float = meal.pose().pickupHungry
			meal.age += 0.000002
			check(absf(meal.pose().pickupHungry-craving)<0.001,"craving mouth snapped off before opening")
			var finish: float = meal.food_end+(meal.tail_time if meal.foods.is_empty() else (1.15 if meal.happy_kind == "finish" else 0.34))
			meal.age = finish-0.000001
			var before: Dictionary = meal.pose()
			var after: Dictionary = meal.update(0.000002)
			if meal.active():
				for key in ["pickupArms","pickupLean","pickupHeadTilt","chewEyeClose","chewReliefSmile"]:
					max_jump = maxf(max_jump,absf(before[key]-after[key]))
				max_jump = maxf(max_jump,before.foodNear.distance_to(after.foodNear))
				max_jump = maxf(max_jump,before.foodFar.distance_to(after.foodFar))
		var last_happy := -1
		var meal_chokes := 0
		for i in meal.history.size():
			var entry: Dictionary = meal.history[i]
			meal_chokes += entry.chokes
			if entry.happy == "savor": savor += 1
			if entry.happy == "finish": content += 1
			if not entry.happy.is_empty():
				if last_happy >= 0: check(i-last_happy >= 2 and i-last_happy <= 4,"delight spacing outside 2–4 foods")
				last_happy = i
			if i >= 3: check(not (entry.style == meal.history[i-1].style and entry.style == meal.history[i-2].style),"three identical pickups in a row")
		check(meal_chokes <= 1,"long queue repeated a strained swallow")
		chokes += meal_chokes
	check(savor > content*2 and content > 15,"B is not dominant or C endings are absent")
	check(chokes > 1 and chokes < 20,"rare swallow chance grows with the queue")
	check(max_jump < 0.1,"food-to-food hand/eye/head transition jumps: "+str(max_jump))
	check(max_palm_error<10.0,"random bite detached a hand: %.3f %s"%[max_palm_error,worst_palm])
	check(far_backward<0.0,"far wrist crossed behind its shoulder: "+str(far_backward))
	check(far_foldback<0.0,"far forearm doubled back at the elbow: "+str(far_foldback))
	check(far_stretch<=1.00001,"far arm stretched instead of foreshortening")
	print("EMBRACE random palm error ",max_palm_error,"; far shoulder margin ",-far_backward,"; far elbow margin ",-far_foldback)
	var tilt_ratio := float(tilt_count)/bite_count
	check(tilt_ratio>=0.10 and tilt_ratio<=0.15,"C is not a small 10–15 percent variation: "+str(tilt_ratio))
	print("SQUARE B2 slanted bites ",tilt_count,"/",bite_count," ",tilt_ratio)
	print("SMALL BITES light chews ",short_chews," grouped swallows ",swallow_count)
	print("MEAL VARIETY savor ",savor," content ",content," rare queues ",chokes,"/200; largest boundary change ",max_jump)

func content_independence() -> void:
	var baseline: Array[Dictionary] = []
	for kind in 6:
		var food = FoodItem.from_texture(ImageTexture.create_from_image(fixture(kind)))
		var random := RandomNumberGenerator.new()
		random.seed = 321
		var plan: Array[Dictionary] = food.plan_bites(10,random)
		if kind == 0: baseline = plan
		else: check(plan == baseline,"PNG contents changed the generic square bite sequence")
		for part in plan:
			for held in [part.before,part.after]:
				var layout: Dictionary = food.layout(held)
				check(layout.hold == FoodItem.HOLD and layout.source == held.center,"cropping moved the held portion out of the chest")
				check(held.bounds.size.x == food.bounds.size.x,"layer eating shrank the icon width")

func run() -> void:
	masks()
	content_independence()
	var baseline := simulate(30,20261022)
	for fps in [60,120]:
		var sample := simulate(fps,20261022)
		check(sample.history == baseline.history,"random schedule changes with frame rate")
		check(absf(sample.elapsed-baseline.elapsed)<1.0/30.0+0.001,"meal timing changes with frame rate")
	append_and_cancel()
	variety_and_boundaries()
	print("MEAL CHECKS: ",checks," passed: ",checks-failures," failed: ",failures)
	quit(0 if failures == 0 else 1)
