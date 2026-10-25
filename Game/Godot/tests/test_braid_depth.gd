extends SceneTree
## Actual pixel checks: braid covers the raised arm; splitting preserves its art.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Meal = preload("res://scripts/meal_motion.gd")
const Food = preload("res://scripts/food_item.gd")
var failures := 0
var overlap_pixels := 0
var reconstruction_pixels := 0
var viewport: SubViewport

func _initialize() -> void: call_deferred("run")

func render() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func difference(a: Color, b: Color) -> float:
	# Compare premultiplied colors so transparent edge RGB is irrelevant.
	return maxf(absf(a.a-b.a),maxf(absf(a.r*a.a-b.r*b.a),maxf(absf(a.g*a.a-b.g*b.a),absf(a.b*a.a-b.b*b.a))))

func run() -> void:
	root.size = Vector2i(600,600)
	root.position = Vector2i(-1600,-1600)
	viewport = SubViewport.new()
	viewport.size = root.size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new()
	viewport.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))):
		printerr(pet.failure); quit(1); return
	pet.fit(Vector2.ONE*600)
	pet.sitting.amount = 1.0
	pet.sitting.seated = true
	var behavior = Behavior.new()
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.motionReset = true
	base.breath = 0.0
	var meal = Meal.new()
	meal.rng.seed = 20261027
	meal.request_food([Food.from_texture(Food.DEMO_TEXTURES[0])],100,600)
	meal.state = "holding"
	var moments := [3.0,meal.segments[0].start+0.45,meal.segments[4].start+0.45,meal.segments[-1].start+0.45]
	var out := "res://../../_work/tests/braid-depth-pixels"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for facing in [1.0,-1.0]:
		for stage in moments.size():
			meal.age = moments[stage]
			var pose := base.duplicate()
			pose.merge(meal.pose(),true)
			pose.facingScale = facing
			pet.apply_pose(pose,0.0)
			var rig = pet.pickup_pose.hold_rig
			var braid: MeshInstance2D = pet.meshes.ArtMesh17
			var upper: MeshInstance2D = rig.braid_layers.pieces[0].node
			var lower: MeshInstance2D = rig.braid_layers.pieces[1].node
			var shown := []
			for node in pet.model.get_children():
				if node is CanvasItem and node.visible: shown.append(node)
			(await render()).save_png(out.path_join("facing-%d-stage-%d.png"%[int(facing),stage]))
			for node in shown: node.hide()
			lower.show()
			var foreground := await render()
			lower.hide(); rig.near.show()
			var arm := await render()
			lower.show()
			var combined := await render()
			var overlap := 0
			for y in 600:
				for x in 600:
					var a := foreground.get_pixel(x,y)
					if a.a<0.99 or arm.get_pixel(x,y).a<0.99: continue
					overlap += 1
					if difference(a,combined.get_pixel(x,y))>0.015: failures += 1
			if overlap<15:
				printerr("BRAID: no useful overlap at ",facing," stage ",stage)
				failures += 1
			overlap_pixels += overlap
			rig.near.hide(); upper.show()
			var split := await render()
			upper.hide(); lower.hide(); braid.show(); braid.self_modulate.a = 1.0
			var native := await render()
			var seam_errors := 0
			for y in 600:
				for x in 600:
					var a := split.get_pixel(x,y)
					var b := native.get_pixel(x,y)
					if a.a==0.0 and b.a==0.0: continue
					reconstruction_pixels += 1
					if difference(a,b)>0.025: seam_errors += 1
			if seam_errors>3:
				printerr("BRAID: split art discontinuity ",seam_errors," pixels at ",facing," stage ",stage)
				failures += 1
			for node in shown: node.show()
	print("BRAID PIXELS: ",overlap_pixels," arm overlap; ",reconstruction_pixels," reconstruction; ",failures," failures")
	quit(0 if failures==0 else 1)
