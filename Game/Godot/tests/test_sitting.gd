extends SceneTree
## Capture the real renderer at 60 Hz, including the short texture hand-off.
const Scene = preload("res://scenes/pet.tscn")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var failures := 0
var report: Array = []
var previous_waist := Vector2.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures < 20:
			printerr("SITTING: " + message)

func _run() -> void:
	var app = Scene.instantiate()
	app.bowl_root_override = ProjectSettings.globalize_path("res://../../_work/tests/test_sitting/bowl")
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.set_process_input(false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	app.bubble.hide()
	root.size = Vector2i(600, 600)
	root.position = Vector2i(40, 40)
	app.pet.fit(Vector2(root.size))
	_check(app.pet.available, app.pet.failure)
	if not app.pet.available:
		quit(1)
		return
	_check(app.pet.sitting.sprite.get_index() >
		app.pet.sitting.transition_meshes["ArtMesh21"].node.get_index(),
		"seated cloth must composite above the outgoing skirt")
	app.behavior.automatic_blinks = false
	var folder := ProjectSettings.globalize_path("res://../../_work/tests/sitting-frames")
	DirAccess.make_dir_recursive_absolute(folder)
	var metadata := {}
	for id in app.pet.meshes:
		var points := Secondary.read_points(app.pet.meshes[id])
		var rect := Rect2(points[0], Vector2.ZERO)
		for point in points:
			rect = rect.expand(point)
		metadata[id] = {"bounds": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"z": app.pet.meshes[id].z_index}
	var f := FileAccess.open(folder.path_join("meshes.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(metadata, "\t"))
	f.close()
	for frame in 240:
		if frame == 18:
			app._menu_action(12)
		if frame == 126:
			app._menu_action(13)
		var pose: Dictionary = app.behavior.update(1.0 / 60.0,
			app.pet.gaze_anchor(), app.pet.gaze_anchor(), 600, false)
		# Isolate the posture transition from breath/eye movement in this first inspection.
		pose.breath = 0.0
		app.pet.apply_pose(pose, 1.0 / 60.0)
		var sit = app.pet.sitting
		_check(sit.amount >= 0.0 and sit.amount <= 1.0, "progress outside range")
		_check(sit.blend >= 0.0 and sit.blend <= 1.0, "invalid dissolve")
		for material in sit.lower_materials:
			_check(absf(material.get_shader_parameter("sit_blend") - sit.blend) < 0.00001,
				"material replacement is out of sync")
		for id in ["ArtMesh23", "ArtMesh22"]:
			_check(app.pet.meshes[id].transform.determinant() > 0.7, "flipped/collapsed leg")
		if frame % 6 == 0 and sit.blend < 1.0:
			var raw: Dictionary = app.pet.model.call("get_raw_mesh_vertices")
			for id in sit.LOWER_IDS:
				var dense = sit.transition_meshes[id]
				var node: MeshInstance2D = dense.node if sit.amount > 0.0 else app.pet.meshes[id]
				var before: PackedVector2Array = dense.sample(raw[id]) if sit.amount > 0.0 else raw[id]
				var rendered := Secondary.read_points(node)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var c := indices[n + 2]
					var before_area: float = (before[b] - before[a]).cross(before[c] - before[a])
					var after_area := (rendered[b] - rendered[a]).cross(rendered[c] - rendered[a])
					if absf(before_area) > 0.01:
						_check(before_area * after_area > 0.0, "folded lower-body triangle: " + id)
		var waist: Vector2 = app.pet.to_global(app.pet.model.transform * Vector2(-154, 436))
		if frame > 0:
			_check(waist.distance_to(previous_waist) < 8.0, "waist teleported")
		previous_waist = waist
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0 or frame in range(28, 41):
			var picture := root.get_texture().get_image()
			_check(picture.get_pixel(0, 0).a == 0, "opaque viewport background")
			_check(picture.get_used_rect().end.y < 600, "feet/hair clipped at viewport bottom")
			if sit.blend > 0.05 and sit.blend < 0.95:
				for local_foot in [Vector2(174, 291), Vector2(514, 341)]:
					var pixel := Vector2i(sit.sprite.to_global(local_foot))
					_check(picture.get_pixelv(pixel).a > 0.98, "see-through boot during dissolve")
			picture.save_png(folder.path_join("%03d.png" % frame))
		report.append({"frame": frame, "time": frame / 60.0, "amount": sit.amount,
			"blend": sit.blend, "waist": [waist.x, waist.y]})
		if frame == 120:
			_check(sit.amount == 1.0 and sit.sprite.visible, "did not settle seated")
			for id in sit.LOWER_IDS:
				_check(not app.pet.meshes[id].visible, "standing lower body still visible")
				_check(not sit.transition_meshes[id].node.visible, "transition copy still visible")
	_check(app.pet.sitting.amount == 0.0, "did not return exactly to standing")
	for id in app.pet.sitting.LOWER_IDS:
		_check(app.pet.meshes[id].visible and app.pet.meshes[id].modulate.a == 1.0,
			"standing mesh not restored")
		_check(not app.pet.sitting.transition_meshes[id].node.visible, "duplicate standing mesh")
	# Reversing in the middle must not jump to an endpoint or produce invalid geometry.
	for frame in 100:
		if frame in [0, 13, 21, 36]:
			app.pet.set_seated(not app.pet.sitting.seated)
		var before: float = app.pet.sitting.amount
		var pose: Dictionary = app.behavior.update(1.0 / 60.0,
			app.pet.gaze_anchor() + Vector2(180, -80), app.pet.gaze_anchor(), 600, true)
		app.pet.apply_pose(pose, 1.0 / 60.0)
		_check(absf(app.pet.sitting.amount - before) < 0.1, "reversal jumped")
	# Sitting must remain compatible with breath, expressions and resizing.
	app.pet.set_seated(true)
	app.behavior.command("talk")
	for i in 120:
		var pose: Dictionary = app.behavior.update(1.0 / 60.0,
			app.pet.gaze_anchor() + Vector2(-180, 80), app.pet.gaze_anchor(), 600, true)
		app.pet.apply_pose(pose, 1.0 / 60.0)
	_check(app.pet.sitting.amount == 1.0, "talk changed seated state")
	app._zoom(-24)
	_check(app.pet.sitting.amount == 1.0, "zoom changed seated state")
	# Check the replacement uses the exact torso affine, including breathing.
	var raw: Dictionary = app.pet.model.call("get_raw_mesh_vertices")
	var torso: Transform2D = app.pet.deformation._affine("ArtMesh24", raw["ArtMesh24"])
	var sprite_waist: Vector2 = app.pet.sitting.sprite.transform * Vector2(544, 31)
	_check(sprite_waist.distance_to(torso * Vector2(-154, 436)) < 0.001, "waist seam drift")
	f = FileAccess.open(folder.path_join("timeline.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"failures": failures, "frames": report}, "\t"))
	f.close()
	print("SITTING: 460 frames checked; %d failures" % failures)
	quit(0 if failures == 0 else 1)
