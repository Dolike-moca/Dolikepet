extends "res://tests/test_expression_masks.gd"
const Motion = preload("res://scripts/pickup_motion.gd")

func closed_iris_pixels() -> int:
	var visible := {}
	for node in pet.model.get_children():
		if node is CanvasItem:
			visible[node] = node.visible
			node.hide()
	for id in ["ArtMesh10","ArtMesh11"]: pet.meshes[id].visible = visible[pet.meshes[id]]
	var rendered := await draw_image()
	var count := 0
	var rect := rendered.get_used_rect()
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if rendered.get_pixel(x,y).a > 0.04: count += 1
	for node in visible: node.visible = visible[node]
	return count

func timing_checks() -> void:
	var durations := []
	for seed_value in 24:
		var motion = Motion.new()
		motion.rng.seed = seed_value+541
		motion.request(100,600)
		durations.append(motion.admire_duration)
		check(motion.admire_duration >= 5.0 and motion.admire_duration <= 6.0,"admire duration out of range")
	check(durations.max()-durations.min()>0.65,"hold duration lacks variation")
	for fps in [30,60,120]:
		var motion = Motion.new()
		motion.rng.seed = 20261022
		motion.request(100,600)
		var events := 0
		for frame in fps*8:
			var p: Dictionary = motion.update(1.0/fps)
			if motion.take_eat_request():
				events += 1
				check(absf(motion.age-Motion.CATCH_TIME-motion.admire_duration-motion.bite_duration*Motion.Bite.CHEW_AT) <= 1.0/fps+0.00001,
					"chewing did not follow the bite after admiring")
			if motion.age > Motion.CATCH_TIME and motion.age < Motion.CATCH_TIME+5.0:
				check(p.pickupHungry == 1.0 and p.pickupStarEyes == 1.0,"craving face left before minimum hold")
			if frame == fps*2:
				var before: Dictionary = motion.pose()
				for pause_frame in fps: motion.update(1.0/fps,true,true)
				check(before == motion.pose(),"paused hold or sparkle advanced")
		check(events == 1,"eating event repeated or missing")
		check(motion.pose().pickupHungry == 0.0 and motion.pose().pickupStarEyes == 0.0,"craving expression failed to finish")
		motion.cancel(true)
		check(not motion.take_eat_request() and motion.pose().pickupHungry == 0.0,"interrupt retained craving event")
	var motion = Motion.new()
	motion.request(100,600)
	motion.state = "holding"
	motion.age = Motion.CATCH_TIME+1.0
	var first: Dictionary = motion.pose()
	motion.update(0.1)
	var second: Dictionary = motion.pose()
	check(first.pickupStarNear != second.pickupStarNear,"star stopped animating during hold")
	check(first.pickupStarNear != first.pickupStarFar,"eyes sparkle in mechanical lockstep")
	motion.cancel(true)
	for frame in 300: motion.update(1.0/60)
	check(not motion.take_eat_request(),"cancelled pickup started eating later")
	# The phase boundary must preserve velocity as well as position.
	var samples := []
	motion.state = "picking"
	for t in [Motion.DURATION-0.0001,Motion.DURATION,Motion.DURATION+0.0001]:
		motion.age = t
		samples.append(motion.pose().pickupLean)
	check(absf((samples[2]-samples[1])-(samples[1]-samples[0]))<0.000001,"hold entry changed lean velocity")

func run() -> void:
	timing_checks()
	if DisplayServer.get_name() == "headless": finish_hungry(); return
	root.size = Vector2i(600,600)
	root.position = Vector2i(24,24)
	root.mouse_passthrough = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(600,600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	pet = Pet.new()
	viewport.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))),pet.failure)
	if not pet.available: finish_hungry(); return
	pet.fit(Vector2(600,600))
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	base = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	out = "res://../../_work/tests/hungry-b2-masks"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var motion = Motion.new()
	motion.request(100,600)
	motion.state = "holding"
	motion.age = Motion.CATCH_TIME+1.8
	var hungry: Dictionary = motion.pose()
	for facing in [-1.0,1.0]:
		base.facingScale = facing
		for openness in [0.0,0.05,0.30,0.65,1.0]:
			var extras := hungry.duplicate()
			extras.merge({"eyeNear":openness,"eyeFar":openness,"gazeX":0.75*facing,"gazeY":-0.8},true)
			await sample("hungry-%d-blink-%.2f" % [int(facing),openness],extras)
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			var head: Transform2D = pet.deformation._affine("ArtMesh18",raw.ArtMesh18)
			var body: Transform2D = pet.deformation._affine("ArtMesh24",raw.ArtMesh24)
			var expected: Vector2 = Pet.PickupPose.upper_transform(body,extras) * head * Pet.ChewingPose.CENTER
			check(pet.hungry_face.mouth.position.distance_to(expected)<0.002,"mouth drifted from head while tilting")
			check(pet.hungry_face.materials.ArtMesh11.get_shader_parameter("hungry_weight") == 1.0,"native advance lost star material")
			if openness == 0.0:
				check(await closed_iris_pixels() == 0,"closed eyes retained visible iris pixels")
		for size in [240,800]:
			pet.fit(Vector2.ONE*size)
			var pose := base.duplicate()
			pose.merge(hungry,true)
			pet.apply_pose(pose,0.0)
			check(pet.food_gaze(pose).distance_to(pet.pickup_pose.food.global_position)<0.01,"admiring gaze lost food after scale/mirror")
		pet.fit(Vector2(600,600))
	for physical in ["dragHeld","fallActive","dizzyActive"]:
		var pose := base.duplicate()
		pose.merge(hungry,true)
		pose[physical] = true
		pet.apply_pose(pose,0.0)
		check(not pet.hungry_face.mouth.visible,"hungry mouth overrides "+physical)
		check(pet.hungry_face.materials.ArtMesh11.get_shader_parameter("hungry_weight") == 0.0,"star eyes override "+physical)
	await sample("normal-restored",{})
	check(not pet.hungry_face.mouth.visible and pet.hungry_face.materials.ArtMesh10.get_shader_parameter("hungry_weight") == 0.0,
		"normal expression not restored")
	finish_hungry()

func finish_hungry() -> void:
	print("HUNGRY B2 CHECKS: ",checks," passed: ",checks-failures," failed: ",failures,"; iris leak pixels: ",worst_leak)
	quit(0 if failures == 0 else 1)
