extends SceneTree
const Meal = preload("res://scripts/meal_motion.gd")
const FoodItem = preload("res://scripts/food_item.gd")
const Fixtures = preload("res://tests/test_meal.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Scene = preload("res://scenes/pet.tscn")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("MEAL RENDER: "+message)

func run() -> void:
	root.size = Vector2i(600,600)
	root.position = Vector2i(24,24)
	root.mouse_passthrough = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600,600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new()
	viewport.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))),pet.failure)
	if not pet.available: finish(); return
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	var out := "res://../../_work/tests/meal-render-check"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var max_grip_error := 0.0
	var worst_grip := ""
	var flipped := 0.0
	var max_attachment_error := 0.0
	var smallest_mouth_gap := INF
	var worst_flip := ""
	for kind in range(-3,6):
		var food = FoodItem.from_texture(FoodItem.DEMO_TEXTURES[-kind-1]) if kind < 0 else FoodItem.from_texture(ImageTexture.create_from_image(Fixtures.fixture(kind)))
		var meal = Meal.new()
		meal.rng.seed = 20261089
		meal.request_food([food],100,600)
		meal.state = "holding"
		for size in [320,600]:
			pet.fit(Vector2.ONE*size)
			for facing in [1.0,-1.0]:
				base.facingScale = facing
				pet.apply_pose(base,0.0)
				var feet := {}
				for id in ["ArtMesh21","ArtMesh22","ArtMesh23"]: feet[id] = Pet.Secondary.read_points(pet.meshes[id])
				for segment in meal.segments:
					segment.tilt = deg_to_rad(6.0 if meal.segments.find(segment)%2 == 0 else -6.0)
					for phase in [0.0,0.25,0.46,0.60,0.85,1.15,2.0]:
						meal.age = segment.start+segment.duration*phase
						var p: Dictionary = meal.pose()
						var pose := base.duplicate()
						pose.merge(p,true)
						pet.apply_pose(pose,0.0)
						check(pet.pickup_pose.food.z_index>pet.meshes.ArtMesh5.z_index,"food/scarf order changed")
						var rig = pet.pickup_pose.hold_rig
						check(rig.near.z_index>pet.pickup_pose.food.z_index,"whole near arm must stay in front of food and scarf")
						check(rig.far.z_index<pet.pickup_pose.food.z_index,"far hand crossed in front of the icon")
						var body: Transform2D = pet.pickup_pose.gaze_body
						var upper: Transform2D = Pet.PickupPose.upper_transform(body,pose)*Pet.PickupPose.Spine.upper_transform(body,pose)
						var held: Dictionary = p.foodPart
						var icon_grip: Vector2 = pet.pickup_pose.food.global_transform*(held.hold_grip-rig.food_source)
						var actual: Vector2 = pet.model.global_transform*rig.palms.ArtMesh19
						max_attachment_error = maxf(max_attachment_error,actual.distance_to(icon_grip)*600.0/size)
						for arm in [rig.near,rig.far]:
							var local: Transform2D = (upper*body).affine_inverse()*arm.transform
							check(absf(local.x.length()-local.y.length())<0.0001 and absf(local.x.dot(local.y))<0.0001,"held arm stretched or sheared")
						var mouth: Vector2 = pet.bite_face.mouth.global_transform*pet.bite_face.closed_center
						for corner in [held.bounds.position,Vector2(held.bounds.end.x,held.bounds.position.y)]:
							var top: Vector2 = pet.pickup_pose.food.global_transform*(corner-rig.food_source)
							smallest_mouth_gap = minf(smallest_mouth_gap,(top.y-mouth.y)*600.0/size)
						for id in feet: check(feet[id] == Pet.Secondary.read_points(pet.meshes[id]),"feeding moved foot/hip support")
						if pose.chewEyeClose == 1.0:
							check(pet.params[pet.mapping.eyeNear].get("value") == 0.0 and pet.params[pet.mapping.eyeFar].get("value") == 0.0,"happy chewing reopened an eye")
						var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
						for id in Pet.Walking.SHOULDERS:
							var target: Vector2 = pose.foodNear if id == "ArtMesh19" else pose.foodFar
							var bone: Dictionary = Pet.PickupPose.solve(id,1.0,pose.pickupCatch,1.0,1.0,pose.pickupCarry,target)
							var grip_error: float = Pet.PickupPose.arm_point(bone.palm,bone).distance_to(target+pose.pickupCarry+Vector2(0,11.0*pose.pickupCatch))
							if grip_error > max_grip_error:
								max_grip_error = grip_error
								worst_grip = "kind %d %s phase %.2f target %s shoulder %s projected_scale %.3f"%[kind,id,phase,target+pose.pickupCarry,bone.shoulder,bone.reach_scale]
							var points := Pet.Secondary.read_points(pet.meshes[id])
							var reference: PackedVector2Array = raw[id]
							var tris: PackedInt32Array = pet.meshes[id].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
							for at in range(0,tris.size(),3):
								var a := tris[at]; var b := tris[at+1]; var c := tris[at+2]
								var before := (reference[b]-reference[a]).cross(reference[c]-reference[a])
								var after := (points[b]-points[a]).cross(points[c]-points[a])
								if before*after < -0.01 and absf(after)>flipped:
									flipped = absf(after); worst_flip = "kind %d %s phase %.2f"%[kind,id,phase]
						if size == 600 and facing == 1.0 and phase == 0.46:
							await process_frame
							await RenderingServer.frame_post_draw
							viewport.get_texture().get_image().save_png(out.path_join("kind-%d-bite-%d.png"%[kind,meal.segments.find(segment)]))
		if kind < 0:
			var previous_coverage := INF
			for index in meal.segments.size()-1:
				var segment: Dictionary = meal.segments[index]
				meal.age = segment.start+segment.duration*1.20
				var grip_pose := base.duplicate()
				grip_pose.merge(meal.pose(),true)
				pet.apply_pose(grip_pose,0.0)
				for node in pet.model.get_children():
					if node is CanvasItem: node.hide()
				pet.pickup_pose.food.show()
				await process_frame
				await RenderingServer.frame_post_draw
				var held_pixels := viewport.get_texture().get_image()
				held_pixels.convert(Image.FORMAT_RGBA8)
				var rgba := held_pixels.get_data()
				var coverage := 0.0
				for at in range(3,rgba.size(),4): coverage += rgba[at]/255.0
				check(coverage>0.0 and coverage<previous_coverage-20.0,"a small bite did not remove rendered pixels (including cuts beyond five)")
				previous_coverage = coverage
				var held: Dictionary = grip_pose.foodPart
				# The near palm grips the remnant; the far open hand cups its
				# underside late in the meal, so its palm center may be below it.
				for grip in [held.hold_grip]:
					var at: Vector2 = pet.pickup_pose.food.global_transform*(grip-pet.pickup_pose.hold_rig.food_source)
					check(held_pixels.get_pixelv(Vector2i(at.round())).a>0.5,"hand did not follow remaining food: kind %d bite %d grip %s"%[kind,index,grip])
				# Sample both margins above the new layer: the old guarded strips
				# must be gone even while a lower portion is still being held.
				for x in [0.03,0.50,0.97]:
					var edge: float = segment.plan.after.profile[clampi(int(x*FoodItem.PROFILE_COLUMNS),0,FoodItem.PROFILE_COLUMNS-1)]
					if edge<0.06: continue
					var source: Vector2 = food.bounds.position+food.bounds.size*Vector2(x,edge-0.045)
					var at: Vector2 = pet.pickup_pose.food.global_transform*(source-pet.pickup_pose.hold_rig.food_source)
					check(held_pixels.get_pixelv(Vector2i(at.round())).a<0.01,"eaten layer left a side strip or center pixel")
				if index == 0:
					# The curved cap must cut deeper at its center than at its side;
					# a straight horizontal wipe would erase both sampled pixels.
					var cut: Vector4 = segment.plan.cut
					var y := (FoodItem.cut_edge(cut.x,cut)+FoodItem.cut_edge(cut.x+0.27,cut))*0.5
					for probe in [Vector2(cut.x,y),Vector2(cut.x+0.27,y)]:
						var source: Vector2 = food.bounds.position+food.bounds.size*probe
						var at: Vector2 = pet.pickup_pose.food.global_transform*(source-pet.pickup_pose.hold_rig.food_source)
						var alpha := held_pixels.get_pixelv(Vector2i(at.round())).a
						check(alpha<0.01 if probe.x == cut.x else alpha>0.5,"first bite is not a local rounded notch")
				for node in pet.model.get_children():
					if node is MeshInstance2D: node.show()
		# Force final material cut at full opacity to test actual shader coverage.
		meal.age = meal.segments[-1].start+meal.segments[-1].duration*0.62
		var final_pose := base.duplicate()
		final_pose.merge(meal.pose(),true)
		final_pose.pickupAlpha = 1.0
		pet.apply_pose(final_pose,0.0)
		for node in pet.model.get_children():
			if node is CanvasItem: node.hide()
		pet.pickup_pose.food.show()
		await process_frame
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().get_used_rect().size == Vector2i.ZERO,"GPU final bite left food pixels")
		for node in pet.model.get_children():
			if node is MeshInstance2D: node.show()
	check(max_grip_error < 12.0,"palm missed food: %.3f (%s)"%[max_grip_error,worst_grip])
	check(flipped < 0.1,"arm triangle folded: %.3f (%s)"%[flipped,worst_flip])
	check(max_attachment_error<3.0,"hands detached from slanted icon: "+str(max_attachment_error))
	check(smallest_mouth_gap>10.0,"raised icon approaches/covers the mouth: "+str(smallest_mouth_gap))
	print("SQUARE attachment gap ",max_attachment_error," px at 600; icon below mouth ",smallest_mouth_gap," px")
	print("MEAL RENDER grip ",max_grip_error," ",worst_grip,"; flipped ",flipped," ",worst_flip)
	# Reuse the same texture across a queue, then change PNG shape. Every new
	# food must recover its full visible image and an embrace-sized footprint.
	var burger = FoodItem.from_texture(FoodItem.DEMO_TEXTURES[0])
	var ring = FoodItem.from_texture(FoodItem.DEMO_TEXTURES[1])
	var queue = Meal.new()
	queue.rng.seed = 20261106
	queue.request_food([burger,burger,burger,ring],100,600)
	queue.state = "holding"
	base.facingScale = 1.0
	pet.fit(Vector2.ONE*600)
	while queue.active():
		queue.age = queue.segments[0].start-0.10
		var held := base.duplicate()
		held.merge(queue.pose(),true)
		pet.apply_pose(held,0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("queue-%d-full.png"%queue.served))
		for node in pet.model.get_children():
			if node is CanvasItem: node.hide()
		pet.pickup_pose.food.show()
		await process_frame
		await RenderingServer.frame_post_draw
		var visible: Rect2i = viewport.get_texture().get_image().get_used_rect()
		check(visible.size.x>65 and visible.size.y>55,"queued food became hidden/tiny: %d %s"%[queue.served,visible])
		check(held.foodCutIndex <= 0 and held.foodCutProgress == 0.0 and held.foodRemaining == 1.0,"next food retained the previous cuts")
		for node in pet.model.get_children():
			if node is MeshInstance2D: node.show()
		queue.age = queue.food_end+queue.tail_time+0.01
		queue.update(0.01)
	viewport.queue_free()
	await process_frame
	var settings := ConfigFile.new()
	var settings_path := "res://../../_work/tests/meal-runtime-settings.cfg"
	settings.set_value("pet","auto_fall_enabled",false)
	settings.set_value("window","size",600)
	settings.save(settings_path)
	var app = Scene.instantiate()
	app.settings_path = settings_path
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app._feed_pngs(PackedStringArray([ProjectSettings.globalize_path("res://../../_work/tests/meal-fixture-0.png"),ProjectSettings.globalize_path("res://../../_work/tests/meal-fixture-3.png")]))
	for frame in 120: app._process(1.0/60.0)
	check(app.pickup.meal_enabled and app.pickup.foods.size() == 1,"PNG menu did not start multi-food queue")
	var at: float = app.pickup.age
	app.food_dialog_open = true
	for frame in 20: app._process(1.0/60.0)
	check(app.pickup.age == at,"file dialog advanced meal clock")
	app._feed_pngs(PackedStringArray([ProjectSettings.globalize_path("res://../../_work/tests/meal-fixture-4.png")]))
	check(app.pickup.foods.size() == 2 and app.pickup.age == at,"append replaced/restarted active food")
	app._menu_action(0)
	for frame in 30: app._process(1.0/60.0)
	check(not app.pickup.active() and not app.pet.pickup_pose.food.visible,"normal command did not release the meal")
	app._start_pickup_demo()
	for frame in 100: app._process(1.0/60.0)
	app.drag_pointer = root.position+Vector2i(300,170)
	app._begin_grab()
	for frame in 15: app._process(1.0/60.0)
	check(not app.pickup.active() and not app.pet.pickup_pose.food.visible,"grab retained a meal")
	finish()

func finish() -> void:
	print("MEAL RENDER CHECKS: ",checks," passed: ",checks-failures," failed: ",failures)
	quit(0 if failures == 0 else 1)
