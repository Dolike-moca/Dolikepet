extends SceneTree
## Verify opaque icon pixels actually occlude the scarf, in both facings.
const Pet = preload("res://scripts/live2d_pet.gd")
const Meal = preload("res://scripts/meal_motion.gd")
const Food = preload("res://scripts/food_item.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(600,600)
	root.position = Vector2i(-1600,-1600)
	root.mouse_passthrough = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600,600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new()
	viewport.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))):
		printerr(pet.failure); quit(1); return
	pet.fit(Vector2(600,600))
	var behavior = Behavior.new()
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	var meal = Meal.new()
	meal.rng.seed = 20261022
	meal.request_food([Food.from_texture(Food.DEMO_TEXTURES[0])],100,600)
	meal.state = "holding"
	var first: Dictionary = meal.segments[0]
	var middle: Dictionary = meal.segments[3]
	var last: Dictionary = meal.segments[-1]
	var moments := [2.0,first.start+first.duration*0.40,first.start+first.duration*0.90,middle.start+middle.duration*0.40,last.start+last.duration*0.40]
	var out := "res://../../_work/tests/food-scarf-depth"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var max_difference := 0.0
	for facing in [1.0,-1.0]:
		for stage in moments.size():
			meal.age = moments[stage]
			var pose := base.duplicate()
			pose.merge(meal.pose(),true)
			pose.facingScale = facing
			pet.apply_pose(pose,0.0)
			var shown := []
			for node in pet.model.get_children():
				if node is CanvasItem and node.visible: shown.append(node)
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out.path_join("facing-%d-stage-%d.png"%[int(facing),stage]))
			if stage == 0 or stage == 4:
				pet.pickup_pose.food.hide()
				await process_frame
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(out.path_join("shoulders-%d-stage-%d.png"%[int(facing),stage]))
				pet.pickup_pose.food.show()
			var layers := []
			for mode in 3:
				for node in shown: node.hide()
				if mode != 1: pet.meshes.ArtMesh5.show()
				if mode != 0: pet.pickup_pose.food.show()
				await process_frame
				await RenderingServer.frame_post_draw
				layers.append(viewport.get_texture().get_image())
			var overlap := 0
			for y in range(260,440):
				for x in range(80,520):
					var scarf: Color = layers[0].get_pixel(x,y)
					var icon: Color = layers[1].get_pixel(x,y)
					if scarf.a<0.98 or icon.a<0.98: continue
					var combined: Color = layers[2].get_pixel(x,y)
					var difference := maxf(absf(combined.r-icon.r),maxf(absf(combined.g-icon.g),absf(combined.b-icon.b)))
					max_difference = maxf(max_difference,difference)
					overlap += 1
					checks += 1
					if difference>0.015: failures += 1
			if stage<3 and overlap<40:
				failures += 1
				printerr("No useful scarf/icon overlap at ",facing," stage ",stage)
			print("DEPTH facing ",facing," stage ",stage," overlap pixels ",overlap)
			for node in shown: node.show()
	print("FOOD SCARF PIXELS: ",checks," failed ",failures," max difference ",max_difference)
	quit(0 if failures==0 else 1)
