extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Meal = preload("res://scripts/meal_motion.gd")
const Food = preload("res://scripts/food_item.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<15: printerr("HOLD RIG: "+message)

func run() -> void:
	root.size = Vector2i(600,600)
	root.position = Vector2i(-1600,-1600)
	var pet = Pet.new()
	root.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))):
		printerr(pet.failure); quit(1); return
	pet.fit(Vector2.ONE*600)
	pet.sitting.seated = true
	pet.sitting.amount = 1.0
	var behavior = Behavior.new()
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	var meal = Meal.new()
	meal.rng.seed = 20261022
	meal.request_food([Food.from_texture(Food.DEMO_TEXTURES[0])],100,600)
	meal.state = "holding"; meal.age = 2.0
	var pose := base.duplicate()
	pose.merge(meal.pose(),true)
	pose.pickupHungry = 0.0; pose.pickupStarEyes = 0.0; pose.pickupHeadTilt = 0.0
	pet.apply_pose(pose,0.0)
	var rig = pet.pickup_pose.hold_rig
	var body: Transform2D = pet.pickup_pose.gaze_body
	var upper: Transform2D = Pet.PickupPose.upper_transform(body,pose)*Pet.PickupPose.Spine.upper_transform(body,pose)
	var inverse := (upper*body).affine_inverse()
	check((inverse*rig.near.transform*rig.NEAR_ROOT).distance_to(Vector2(-14.6757,214.0115))<0.005,"near shoulder differs from approved preview")
	check((inverse*rig.far.transform*rig.FAR_ROOT).distance_to(Vector2(-302.5,190.875))<0.005,"far shoulder differs from approved preview")
	check((inverse*rig.near.transform*rig.NEAR_PALM).distance_to(Vector2(-204.251,445.6453))<0.005,"near palm differs from approved preview")
	var approved_far_palm := Vector2(-302.5,190.875)+(Vector2(-530.3029,309.3981)-Vector2(-302.5,190.875))*1.19298833568046
	check((inverse*rig.far.transform*rig.FAR_PALM).distance_to(approved_far_palm)<0.005,"far palm differs from approved longer-arm preview")
	check(absf((inverse.basis_xform(rig.palms.ArtMesh26-rig.shoulders.ArtMesh26)).length()-306.349487304688)<0.003,"feeding arm length differs from the PSD arm")
	var icon: Transform2D = inverse*pet.pickup_pose.food.transform
	check(absf(icon.x.length()*256.0-495.05664)<0.005,"approved large icon was resized")
	check((icon*pet.pickup_pose.food.offset).distance_to(Vector2(-359.5428,377.3465))<0.01,"approved food center moved")
	for facing in [1.0,-1.0]:
		pose.facingScale = facing
		pet.apply_pose(pose,0.0)
		var bowl: Sprite2D = pet.pickup_pose.bowl
		var rect := bowl.get_rect()
		for point in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
			check(Rect2(0,0,600,600).has_point(bowl.global_transform*point),"seated bowl clipped outside pet window")
	for weight in [0.0,0.0001,0.1,0.25,0.5,0.75,1.0,0.5,0.1,0.0]:
		var turning := pose.duplicate(); turning.pickupArms = weight
		pet.apply_pose(turning,0.0)
		var turn_body: Transform2D = pet.pickup_pose.gaze_body
		var turn_upper: Transform2D = Pet.PickupPose.upper_transform(turn_body,turning)*Pet.PickupPose.Spine.upper_transform(turn_body,turning)
		var turn_inverse := (turn_upper*turn_body).affine_inverse()
		if weight==0.0:
			check((turn_inverse*rig.palms.ArtMesh26).distance_to(Vector2(-399.41357421875,457.112060546875))<0.01,"reach/release endpoint did not use the accepted 8-degree rest palm")
		if weight==0.0001:
			var first_visible_palm: Vector2 = turn_inverse*rig.far_rest_overlay.transform*rig.FAR_REST_PALM
			check(first_visible_palm.distance_to(Vector2(-399.41357421875,457.112060546875))<0.1,"first reach frame jumped from the lowered rest palm")
		if rig.far_rest_overlay.visible:
			var back_palm: Vector2 = rig.far_rest_overlay.transform*rig.FAR_REST_PALM
			check(back_palm.distance_to(rig.palms.ArtMesh26)<0.003,"hand-turn crossfade separated the two palms")
			check(absf(rig.far_rest_overlay.modulate.a+rig.far.modulate.a-1.0)<0.00001,"hand-turn fade lost its envelope")
		else:
			check(rig.far.modulate.a==1.0,"settled arm retained a partial fade")
	for override in ["dragHeld","fallActive","dizzyActive"]:
		var interrupted := pose.duplicate()
		interrupted[override] = true
		pet.apply_pose(interrupted,0.0)
		check(not rig.enabled and rig.near.visible and rig.far.visible,"physical interruption did not use shared rest arms")
		check(rig.far.texture==rig.FarRestArt and not rig.far_rest_overlay.visible,"interruption did not restore the normal far-arm art")
		check(pet.meshes.ArtMesh17.self_modulate.a==1.0,"interruption failed to restore near braid")
		check(pet.meshes.ArtMesh19.self_modulate.a==0.0 and pet.meshes.ArtMesh26.self_modulate.a==0.0,"interruption exposed obsolete arms")
	var queue = Meal.new()
	queue.rng.seed = 20261027
	queue.request_food([Food.from_texture(Food.DEMO_TEXTURES[0]),Food.from_texture(Food.DEMO_TEXTURES[1]),Food.from_texture(Food.DEMO_TEXTURES[2])],100,600)
	queue.state = "holding"
	var max_jump := 0.0
	while queue.active():
		for segment in queue.segments:
			for phase in [0.0,0.42,0.64,1.2,2.0]:
				queue.age = segment.start+segment.duration*phase
				var sample := base.duplicate()
				sample.merge(queue.pose(),true)
				pet.apply_pose(sample,0.0)
				body = pet.pickup_pose.gaze_body
				upper = Pet.PickupPose.upper_transform(body,sample)*Pet.PickupPose.Spine.upper_transform(body,sample)
				inverse = (upper*body).affine_inverse()
				var far_registration: Transform2D = rig.FAR_HOLD if rig.enabled else rig.FAR_REST
				var far_root: Vector2 = rig.FAR_ROOT if rig.enabled else rig.FAR_REST_ROOT
				for entry in [[rig.near,rig.NEAR_HOLD,rig.NEAR_ROOT],[rig.far,far_registration,far_root]]:
					var local: Transform2D = inverse*entry[0].transform
					var accepted: Transform2D = entry[1]
					var art_scale: float = 1.19298833568046 if entry[0]==rig.far and rig.enabled else 1.0
					check(absf(local.x.length()-accepted.x.length()*art_scale)<0.00001 and absf(local.y.length()-accepted.y.length()*art_scale)<0.00001,"whole-arm scale changed during meal")
					check(absf(local.x.dot(local.y))<0.00001,"whole-arm artwork sheared")
					var expected: Vector2 = accepted*entry[2]
					if entry[0]==rig.far: expected = rig.FAR_REST_SOCKET.lerp(rig.SOCKETS.ArtMesh26,Pet.PickupPose.amount(sample))
					check((local*entry[2]).distance_to(expected)<0.002,"shoulder wandered while hand lifted")
		var finish: float = queue.food_end+(queue.tail_time if queue.foods.is_empty() else (1.15 if queue.happy_kind=="finish" else 0.34))
		queue.age = finish-0.000001
		var sample := base.duplicate(); sample.merge(queue.pose(),true)
		pet.apply_pose(sample,0.0)
		var before: Dictionary = rig.palms.duplicate()
		queue.update(0.000002)
		sample = base.duplicate(); sample.merge(queue.pose(),true)
		pet.apply_pose(sample,0.0)
		if queue.active():
			for id in before: max_jump = maxf(max_jump,before[id].distance_to(rig.palms[id]))
	check(max_jump<0.1,"food handoff jumps: "+str(max_jump))
	check(not rig.enabled and rig.near.visible and rig.far.visible,"queue end did not return shared arms to rest")
	check(rig.far.texture==rig.FarRestArt and not rig.far_rest_overlay.visible,"queue end did not restore the normal far-arm art")
	var final_body: Transform2D = pet.pickup_pose.gaze_body
	check(absf((final_body.affine_inverse()*rig.far.transform).get_rotation()-deg_to_rad(-8.0))<0.001,"queue end did not restore the lowered normal angle")
	check(pet.meshes.ArtMesh17.self_modulate.a==1.0,"queue end failed to restore braid")
	print("APPROVED HOLD RIG: ",checks," passed ",checks-failures," failed ",failures,"; queue jump ",max_jump)
	quit(0 if failures==0 else 1)
