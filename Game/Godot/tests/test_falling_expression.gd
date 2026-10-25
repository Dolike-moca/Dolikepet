extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const FallingPose = preload("res://scripts/falling_pose.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FALL EXPRESSION: " + message)
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
	# Establish source-PSD placement BEFORE advance() computes mask culling.
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
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/falling/psd-reference.json"))
	var out := "res://../../_work/reviews/godot/falling/psd-v1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for sample in [["neutral", 0.0, 1.0], ["tilt-left", -18.0, 1.0], ["tilt-right", 18.0, 1.0], ["mirrored", 0.0, -1.0], ["regrabbed", 0.0, 1.0], ["released", 0.0, 1.0]]:
		var pose: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 2048, false).duplicate()
		pose.headZ = sample[1]
		pose.facingScale = sample[2]
		pose.breath = 0.0
		pose.eyeNear = 0.0 # An existing closed/happy expression must not leak in.
		pose.eyeFar = 0.0
		pose.mouth = 1.0
		pose.fallActive = sample[0] not in ["released", "regrabbed"]
		pose.dragFace = 1.0 if sample[0] == "regrabbed" else 0.0
		for frame in 20:
			pet.apply_pose(pose, 1.0 / 60)
			await process_frame
		pet.transform = Transform2D(0.0, Vector2(sample[2], 1.0), 0.0, Vector2(1024, 1024))
		var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
		var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
		var sprite: Sprite2D = pet.falling_pose.sprite
		var feature: Dictionary = metadata.features[0]
		var expected_size := Vector2(feature.size[0], feature.size[1])
		check(sprite.texture.get_size() == expected_size, "PSD cached size differs")
		var center := Vector2(feature.center[0], feature.center[1]) - Vector2(1024, 1024)
		for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
			check((sprite.transform * (corner * expected_size)).distance_to(head * (center + corner * expected_size)) < 0.002, "mouth placement / mirror differs from PSD")
		check(sprite.visible == pose.fallActive, "fall / grab / normal visibility")
		if pose.fallActive:
			check(pet.secondary_pose.eyeNear == 1.0 and pet.secondary_pose.eyeFar == 1.0, "eyes not open as in PSD")
			check(pet.meshes.ArtMesh3.self_modulate.a == 0.0 and pet.meshes.ArtMesh4.self_modulate.a == 0.0, "original mouths overlap")
		elif sample[0] == "released":
			check(pet.meshes.ArtMesh3.self_modulate.a == 1.0 and pet.secondary_pose.eyeNear == 0.0, "original expression not restored")
		await process_frame
		await RenderingServer.frame_post_draw
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
			for id in visibility: pet.meshes[id].visible = visibility[id]
	# The new strain must preserve the neck and boot dimensions at every speed.
	var source_pose: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 420, false).duplicate()
	for fps in [30, 60, 120]:
		var controller = FallingPose.new()
		source_pose.fallActive = true
		source_pose.fallSpeed = 2.6
		for frame in fps: controller.update(source_pose, 1.0 / fps, 0.0)
		check(absf(controller.stretch - 0.065) < 0.00002, "FPS dependent stretch")
		source_pose.fallPaused = true
		var before: float = controller.stretch
		controller.update(source_pose, 0.1, 0.0)
		check(controller.stretch == before, "pause changed strain")
		source_pose.fallPaused = false
		source_pose.fallActive = false
		for frame in fps:
			controller.update(source_pose, 1.0 / fps, 0.0)
			check(controller.stretch >= 0.0 and controller.stretch <= before, "new landing bounce")
			before = controller.stretch
		check(controller.stretch == 0.0 and controller.face == 0.0, "fall pose did not neutralize")
	print("FALL EXPRESSION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
