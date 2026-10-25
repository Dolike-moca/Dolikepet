extends SceneTree
const Motion = preload("res://scripts/pickup_motion.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Scene = preload("res://scenes/pet.tscn")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("PICKUP: " + message)

func run() -> void:
	for fps in [30,60,120]:
		var motion = Motion.new()
		check(not motion.request(400,600), "far bowl triggered")
		check(motion.request(180,600), "near bowl rejected")
		check(not motion.request(180,600), "duplicate request restarted action")
		for i in fps: motion.update(1.0/fps, false)
		check(motion.age == 0.0 and motion.state == "waiting", "standing/gait preparation skipped")
		for i in fps: motion.update(1.0/fps)
		var before: Dictionary = motion.pose()
		for i in fps: motion.update(1.0/fps,true,true)
		check(motion.pose() == before, "paused action advanced")
		for i in fps: motion.update(1.0/fps)
		check(motion.state == "holding" and motion.pose().pickupCatch == 0.0 \
			and motion.pose().pickupArms == 1.0, "failed to settle into hold")
		motion.cancel()
		for i in fps: motion.update(1.0/fps)
		check(not motion.active() and motion.pose().pickupAlpha == 0.0, "release left held food")
		check(motion.request(90,300), "scaled proximity rejected")
		motion.update(0.1)
		motion.cancel(true)
		check(not motion.active() and motion.pose().pickupArms == 0.0, "physical interrupt retained arms")
	# Contact cannot inject a visible velocity kick after the quintic arrival.
	var contact = Motion.new()
	contact.state = "picking"
	contact.age = Motion.CATCH_TIME
	var at_contact: Dictionary = contact.pose()
	contact.age += 0.0001
	check(absf(contact.pose().pickupCatch-at_contact.pickupCatch)/0.0001 < 0.03,
		"contact started with a sudden compression velocity")
	contact.age = Motion.DURATION-0.0001
	var before_hold: Dictionary = contact.pose()
	contact.update(0.0001)
	for key in ["pickupGrip","pickupGather","pickupCatch","pickupLean"]:
		check(absf(contact.pose()[key]-before_hold[key]) < 0.0001,"hold entry snapped: "+key)
	if DisplayServer.get_name() == "headless": finish(); return
	root.size = Vector2i(600,600)
	root.position = Vector2i(24,24)
	root.mouse_passthrough = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600,600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := TextureRect.new()
	view.texture = viewport.get_texture()
	view.size = Vector2(600,600)
	root.add_child(view)
	var pet = Pet.new()
	viewport.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))), pet.failure)
	if not pet.available: finish(); return
	pet.fit(Vector2(600,600))
	print("PICKUP geometry: bounds ",pet.bounds," pivot ",pet.pivot," scale ",pet.pixel_scale)
	var out := "res://../../_work/tests/hungry-b2-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var b = Behavior.new()
	b.automatic_blinks = false
	check_geometry(pet,b)
	var motion = Motion.new()
	motion.rng.seed = 20261022
	motion.request(180,600)
	print("HUNGRY B2 held duration: ",motion.admire_duration)
	var frame_total := 70 if "--quick" in OS.get_cmdline_user_args() else 270
	for f in frame_total:
		var p: Dictionary = motion.update(1.0/30.0) if f >= 15 else motion.pose()
		if motion.take_eat_request(): b.command("chew",p.biteChewAge)
		var anchor: Vector2 = pet.gaze_anchor()
		var gaze: Vector2 = anchor.lerp(pet.food_gaze(p),p.get("pickupLook",0.0))
		var pose: Dictionary = b.update(1.0/30.0,gaze,anchor,600,true).duplicate()
		pose.merge(p)
		if f == 110: b.command("blink")
		pet.apply_pose(pose,1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png" % f))
		if f == 100:
			print("PICKUP palms ",pet.pickup_pose.palms," food ",pet.pickup_pose.food.position)
			check(pet.pickup_pose.food.visible, "holding food invisible")
			check(pet.food_gaze(pose).distance_to(pet.pickup_pose.food.global_position)<0.01,
				"food gaze missed the carried icon after torso motion")
	# Both directions must keep the complete prop inside the transparent window.
	for facing in [1.0,-1.0]:
		for size in [240,420,800]:
			pet.fit(Vector2.ONE*size)
			var pose: Dictionary = b.update(0.0,Vector2.ZERO,Vector2.ZERO,size,false).duplicate()
			pose.merge(motion.pose())
			pose.facingScale = facing
			pet.apply_pose(pose,0.0)
			for sprite in [pet.pickup_pose.food,pet.pickup_pose.bowl]:
				var rect: Rect2 = sprite.get_rect()
				for point in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
					var at: Vector2 = sprite.global_transform*point
					check(Rect2(Vector2.ZERO,Vector2.ONE*size).has_point(at), "prop clipped at size %d facing %s: %s" % [size,facing,at])
			if size == 800:
				pet.fit(Vector2(600,600))
				pet.apply_pose(pose,0.0)
				await process_frame
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(out.path_join("facing-%d.png" % int(facing)))
	view.queue_free()
	viewport.queue_free()
	await process_frame
	check_menu()
	finish()

func check_geometry(pet, b) -> void:
	var base: Dictionary = b.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	pet.tail.automatic = false
	pet.apply_pose(base,0.0)
	var lower := {}
	for id in ["ArtMesh21","ArtMesh22","ArtMesh23"]: lower[id] = Secondary.read_points(pet.meshes[id])
	var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
	var body: Transform2D = pet.deformation._affine("ArtMesh24",raw.ArtMesh24)
	var neck := Secondary.read_points(pet.meshes.ArtMesh18)
	var motion = Motion.new()
	motion.request(180,600)
	var max_flipped_area := 0.0
	for frame in 91:
		var pose: Dictionary = base.duplicate()
		pose.merge(motion.update(1.0/60.0))
		pet.apply_pose(pose,1.0/60.0)
		for id in lower: check(Secondary.read_points(pet.meshes[id]) == lower[id], "pickup moved grounded support")
		var upper: Transform2D = Pet.PickupPose.upper_transform(body,pose)
		var head_now := Secondary.read_points(pet.meshes.ArtMesh18)
		var error := 0.0
		for i in neck.size(): error = maxf(error,head_now[i].distance_to(upper*neck[i]))
		check(error < 0.002, "pickup stretched or detached the head")
		for id in Pet.Walking.SHOULDERS:
			var bone: Dictionary = Pet.PickupPose.solve(id,pose.pickupArms,pose.pickupCatch)
			check(Pet.PickupPose.arm_point(bone.shoulder,bone).distance_to(bone.shoulder) < 0.001, "shoulder detached")
			var points := Secondary.read_points(pet.meshes[id])
			var reference: PackedVector2Array = raw[id]
			var indices: PackedInt32Array = pet.meshes[id].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var a: int = indices[i]
				var c: int = indices[i+1]
				var d: int = indices[i+2]
				var before := (reference[c]-reference[a]).cross(reference[d]-reference[a])
				var after := (points[c]-points[a]).cross(points[d]-points[a])
				if before * after < -0.01: max_flipped_area = maxf(max_flipped_area,absf(after))
	print("PICKUP flipped triangle area: ",max_flipped_area)
	check(max_flipped_area < 0.1,"arm elbow folded mesh triangles")
	var pose: Dictionary = base.duplicate()
	pose.merge(motion.pose())
	for override in ["dragHeld","fallActive","dizzyActive"]:
		pose[override] = true
		pet.apply_pose(pose,0.0)
		check(not pet.pickup_pose.food.visible and Pet.PickupPose.amount(pose) == 0.0,"physical pose lost priority")
		check(pet.meshes.ArtMesh19.self_modulate.a == 0.0 and pet.meshes.ArtMesh26.self_modulate.a == 0.0 \
			and pet.pickup_pose.hold_rig.near.visible and pet.pickup_pose.hold_rig.far.visible,
			"physical interrupt did not retain the shared arm artwork")
		pose.erase(override)
	pet.apply_pose(base,0.0)
	check(pet.meshes.ArtMesh26.z_index == pet.pickup_pose.original_order.ArtMesh26,"far arm depth not restored")
	pet.tail.automatic = true

func check_menu() -> void:
	var path := "res://../../_work/tests/pickup-test-settings.cfg"
	var settings := ConfigFile.new()
	settings.set_value("window","size",420)
	settings.set_value("pet","auto_fall_enabled",false)
	settings.set_value("pet","roaming_mode","free")
	settings.set_value("pet","auto_sit_min_seconds",5.0)
	settings.set_value("pet","auto_sit_max_seconds",5.0)
	settings.save(path)
	var app = Scene.instantiate()
	app.settings_path = path
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x+40,area.end.y-root.size.y)
	app.falling.reposition(Vector2(root.position))
	app.pet.set_seated(false)
	app.pet.sitting.amount = 0.0
	app._menu_action(15)
	check(app.pickup.state == "waiting" and app.pet.sitting.seated,"menu did not prepare the approved seated meal")
	for f in 15: app._process(1.0/60)
	check(app.pickup.age == 0.0,"pickup started before sitting finished")
	for f in 480: app._process(1.0/60)
	check(app.pickup.state == "holding" and app.pet.pickup_pose.food.visible,"menu failed to reach hold")
	check(app.roaming.weight == 0.0 and app.idle_sitting.elapsed == 0.0,"autonomous action interrupted pickup")
	app._menu_action(0)
	for f in 30: app._process(1.0/60)
	check(not app.pickup.active() and not app.pet.pickup_pose.food.visible,"normal action did not release pickup")
	app._menu_action(15)
	for f in 100: app._process(1.0/60)
	for f in 20: app._process(1.0/60)
	var age: float = app.pickup.age
	app.settings_window.show()
	for f in 20: app._process(1.0/60)
	check(app.pickup.age > age,"independent settings froze pickup timer")
	app.settings_window.hide()
	app._open_menu(root.position+Vector2i(210,160))
	for f in 20: app._process(1.0/60)
	check(app.pickup.age > age+0.25,"right menu froze pickup")
	app.menu.hide()
	app.drag_pointer = root.position+Vector2i(210,160)
	app._begin_grab()
	for f in 20: app._process(1.0/60)
	check(not app.pickup.active() and not app.pet.pickup_pose.food.visible \
		and not app.pet.pickup_pose.bowl.visible,"grab failed to interrupt food")
	app.falling.cancel()
	app.queue_free()

func finish() -> void:
	print("PICKUP CHECKS: ",checks," passed: ",checks-failures," failed: ",failures)
	quit(0 if failures == 0 else 1)
