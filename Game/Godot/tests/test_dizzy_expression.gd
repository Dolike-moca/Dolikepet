extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("DIZZY PSD: " + message)
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
	pet.fitted_size = Vector2(2048, 2048)
	pet.pixel_scale = 1.0
	pet.pivot = Vector2(0, 2048.0 * 0.98 - 1024.0)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(700, 700)
	root.add_child(preview)
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/landing/psd-reference.json"))
	var out := "res://../../_work/reviews/godot/landing/psd"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for sample in [["neutral", 0.0, 1.0, 0.0], ["rotated", 0.0, 1.0, 1.2], ["tilted", 3.0, 1.0, 0.6], ["mirrored", 0.0, -1.0, 1.2], ["regrab", 0.0, 1.0, 0.0], ["normal", 0.0, 1.0, 0.0]]:
		var pose: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 2048, false).duplicate()
		pose.breath = 0.0
		pose.facingScale = sample[2]
		pose.dizzyActive = sample[0] != "normal"
		pose.dizzyWobble = sample[1]
		pose.dizzyEyeOverride = sample[0] != "normal"
		pose.dizzyOpenness = 0.0
		pose.dizzyAlpha = 0.0 if sample[0] == "normal" else 1.0
		pose.dizzyAngle = sample[3]
		pose.dragFace = 1.0 if sample[0] == "regrab" else 0.0
		pet.apply_pose(pose, 1.0 / 60)
		var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
		var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
		for i in 3:
			var sprite: Sprite2D = pet.landing_pose.sprites[i]
			var feature: Dictionary = metadata.features[i]
			var size := Vector2(feature.size[0], feature.size[1])
			var center := Vector2(feature.center[0], feature.center[1]) - Vector2(1024, 1024)
			check(sprite.texture.get_size() == size, "PSD cache dimensions")
			check(sprite.transform.origin.distance_to(head * center) < 0.002, "rotating eye center drifted")
			check(sprite.z_index >= pet.meshes.ArtMesh2.z_index and sprite.z_index < pet.meshes.ArtMesh1.z_index, "PSD hair occlusion order")
			var local: Transform2D = head.affine_inverse() * sprite.transform * Transform2D(0.0, size, 0.0, Vector2.ZERO)
			check(absf(Vector2(local.x.x, local.y.x).length() - size.x) < 0.002, "rotated eye width/perspective changed")
			check(absf(Vector2(local.x.y, local.y.y).length() - size.y) < 0.002, "rotated eye height changed")
			if sample[3] == 0.0 or i == 2:
				for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
					check((sprite.transform * (corner * size)).distance_to(head * (center + corner * size)) < 0.002, "extra flip / incorrect PSD placement")
		check(pet.meshes.ArtMesh14.self_modulate.a == 1.0, "eye creases lost")
		check(pet.landing_pose.sprites[0].visible == (sample[0] not in ["normal", "regrab"]), "face priority/recovery")
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join(sample[0]+".png"))
		if sample[0] == "neutral":
			var visibility := {}
			for id in pet.meshes:
				visibility[id] = pet.meshes[id].visible
				pet.meshes[id].hide()
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out.path_join("features-only.png"))
			for id in visibility: pet.meshes[id].visible = visibility[id]
	print("DIZZY PSD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
