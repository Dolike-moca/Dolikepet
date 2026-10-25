extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DRAG EXPRESSION: " + message)
func run() -> void:
	root.size = Vector2i(700, 700)
	root.position = Vector2i(20, 20)
	root.mouse_passthrough = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2048, 2048)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new()
	viewport.add_child(pet)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	check(pet.load_pet(config), pet.failure)
	if not pet.available: quit(1); return
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(700, 700)
	root.add_child(preview)
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/drag/psd-reference.json"))
	var out := "res://../../_work/reviews/godot/drag/psd-v2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for sample in [["neutral", 0.0, 1.0], ["tilt-left", -18.0, 1.0], ["tilt-right", 18.0, 1.0], ["mirrored", 0.0, -1.0], ["released", 0.0, 1.0]]:
		var pose: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 2048, false).duplicate()
		pose.headZ = sample[1]
		pose.breath = 0.0
		pose.dragFace = 0.0 if sample[0] == "released" else 1.0
		pet.apply_pose(pose, 1.0 / 60)
		# Exact source-PSD pixel coordinates, without the desktop fit/scale.
		pet.transform = Transform2D(0.0, Vector2(sample[2], 1.0), 0.0, Vector2(1024, 1024))
		var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
		var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
		for i in 3:
			var sprite: Sprite2D = pet.drag_pose.sprites[i]
			var feature: Dictionary = metadata.features[i]
			var expected_size := Vector2(feature.size[0], feature.size[1])
			check(sprite.texture.get_size() == expected_size, "baked PSD texture size differs")
			var expected_center := Vector2(feature.center[0], feature.center[1]) - Vector2(1024, 1024)
			for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
				var actual: Vector2 = sprite.transform * (corner * expected_size)
				var expected: Vector2 = head * (expected_center + corner * expected_size)
				check(actual.distance_to(expected) < 0.002, "PSD position / scale / extra mirror differs")
		check(pet.meshes.ArtMesh14.self_modulate.a == 1.0, "PSD eye creases hidden")
		check(pet.meshes.ArtMesh12.self_modulate.a == 1.0 - pose.dragFace, "original eye overlap")
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join(sample[0] + ".png"))
		if sample[0] == "neutral":
			var visibility := {}
			for id in pet.meshes:
				visibility[id] = pet.meshes[id].visible
				pet.meshes[id].hide()
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out.path_join("features-only.png"))
			for id in visibility:
				pet.meshes[id].visible = visibility[id]
	print("DRAG EXPRESSION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
