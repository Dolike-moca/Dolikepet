extends SceneTree
## Requires the Windows renderer. Captures the actual Live2D viewport.
const Scene = preload("res://scenes/pet.tscn")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var failures := 0
var frames_checked := 0
var worst_scarf_error := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(600, 600)
	root.position = Vector2i(24, 24)
	var app = Scene.instantiate()
	app.bowl_root_override = ProjectSettings.globalize_path("res://../../_work/tests/test_render/bowl")
	root.add_child(app)
	await process_frame
	if not app.pet.available:
		printerr("RENDER FAILED: " + app.pet.failure)
		quit(1)
		return
	app.set_process(false)
	app.set_process_input(false)
	app.bubble.hide()
	root.size = Vector2i(600, 600)
	app.pet.fit(Vector2(root.size))
	var folder := ProjectSettings.globalize_path("res://../../_work/reviews/godot")
	DirAccess.make_dir_recursive_absolute(folder)
	var base: Dictionary = app.pet.model.call("get_raw_mesh_vertices")
	var samples := [
		["neutral", Vector2.ZERO, false, "normal"],
		["left", Vector2(-230, 0), true, "normal"],
		["right", Vector2(230, 0), true, "normal"],
		["up", Vector2(0, -230), true, "normal"],
		["down", Vector2(0, 230), true, "normal"],
		["closed", Vector2.ZERO, false, "closed"],
		["happy", Vector2.ZERO, false, "happy"],
		["closed-happy", Vector2.ZERO, false, "closedHappy"],
	]
	app.behavior.automatic_blinks = false
	for sample in samples:
		app.behavior.command(sample[3])
		for i in 90:
			var pose: Dictionary = app.behavior.update(1.0 / 60.0,
				app.pet.gaze_anchor() + sample[1], app.pet.gaze_anchor(), 600, sample[2])
			app.pet.apply_pose(pose, 1.0 / 60.0)
			_check_geometry(app.pet, base, pose)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var result := image.save_png(folder.path_join(sample[0] + ".png"))
		if result != OK or image.get_used_rect().size.x < 100:
			failures += 1
			printerr("Missing rendered image: " + sample[0])
		if image.get_pixel(0, 0).a > 0.0:
			failures += 1
			printerr("Viewport background is not transparent.")
	# Confirm resizing keeps the feet at the window bottom and all parameters remain valid.
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = area.position + Vector2i(60, 60)
	var old_feet: int = root.position.y + root.size.y
	app._zoom(24)
	if root.size != Vector2i(624, 624) or absi(root.position.y + root.size.y - old_feet) > 1:
		failures += 1
		printerr("Zoom changed the foot anchor.")
	app._menu_action(10)
	if app.gaze_enabled:
		failures += 1
	app._menu_action(10)
	app.menu.popup()
	await process_frame
	if not app.menu.visible:
		failures += 1
	app.menu.hide()
	print("RENDER: %d frames, %d failures; scarf top error %.6f px; meshes %d" %
		[frames_checked, failures, worst_scarf_error, app.pet.meshes.size()])
	# This test deliberately does not save desktop window settings.
	quit(0 if failures == 0 else 1)

func _check_geometry(pet, base: Dictionary, pose: Dictionary) -> void:
	frames_checked += 1
	var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
	var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
	var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
	for id in Secondary.HAIR.keys() + ["ArtMesh5"]:
		var points: PackedVector2Array = pet.deformation.deform_points(id, raw[id], pet.secondary_pose, head, body)
		if frames_checked % 10 == 0:
			var rendered := Secondary.read_points(pet.meshes[id])
			for i in points.size():
				if points[i].distance_to(rendered[i]) > 0.001:
					failures += 1
					if failures <= 5:
						printerr("Rendered vertex differs from current-frame deformation: " + id)
		for i in points.size():
			if not points[i].is_finite():
				failures += 1
				printerr("Nonfinite vertex: " + id)
			if id == "ArtMesh5" and base[id][i].y + 1024.0 <= 1160.0:
				var expected: Vector2 = raw[id][i] + head * base[id][i] - body * base[id][i]
				worst_scarf_error = maxf(worst_scarf_error, points[i].distance_to(expected))
				if points[i].distance_to(expected) > 0.001:
					failures += 1
