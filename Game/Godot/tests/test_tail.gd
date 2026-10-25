extends SceneTree
## Actual Cubism geometry and render integration, with a reproducible motion seed.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Tail = preload("res://scripts/tail_motion.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures <= 15:
			printerr("TAIL: " + label)

func _run() -> void:
	root.size = Vector2i(1000, 660)
	root.position = Vector2i(30, 30)
	root.mouse_passthrough = true
	RenderingServer.set_default_clear_color(Color("#1d2029"))
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	var pet = Pet.new()
	var detail = Pet.new()
	root.add_child(pet)
	root.add_child(detail)
	_check(pet.load_pet(config) and detail.load_pet(config), "load model")
	if not pet.available or not detail.available:
		quit(1)
		return
	# Different parents preserve fit()'s own bottom anchor.
	var stage := Node2D.new()
	root.add_child(stage)
	detail.reparent(stage)
	stage.position = Vector2(280, -130)
	pet.fit(Vector2(600, 640))
	detail.fit(Vector2(820, 900))
	for item in [pet, detail]:
		item.tail.rng.seed = 1729
		item.tail.next_sway = 0.5
	var title := Label.new()
	title.position = Vector2(630, 200)
	title.text = "TAIL DETAIL\nSame motion, original layer order"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)
	var state_label := Label.new()
	state_label.position = Vector2(36, 12)
	state_label.add_theme_font_size_override("font_size", 20)
	root.add_child(state_label)
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var base: PackedVector2Array = pet.deformation.reference[Tail.MESH_ID]
	var triangles: PackedInt32Array = pet.meshes[Tail.MESH_ID].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var original_uvs: PackedVector2Array = pet.meshes[Tail.MESH_ID].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
	var neutral: PackedVector2Array = pet.tail.deform_points(raw[Tail.MESH_ID], Transform2D.IDENTITY)
	_check(neutral == raw[Tail.MESH_ID], "neutral must preserve exact vertices")
	var max_motion := 0.0
	var worst_stretch := 0.0
	var render := "--render" in OS.get_cmdline_user_args()
	var folder := "res://../../_work/tests/tail-frames"
	if render:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for frame in 1200:
		var time := frame / 60.0
		var seated := time >= 6.0 and time < 12.0
		var walk := smoothstep(14.0, 15.0, time)
		var pose: Dictionary = behavior.update(1.0 / 60.0,
			Vector2(200 * sin(time * 0.6), 0), Vector2.ZERO, 600, true).duplicate()
		pose.walkPhase = (time - 14.0) * TAU * 1.7 if time > 14.0 else 0.0
		pose.walkWeight = walk
		# Turn all the way through the narrow midpoint, then stay mirrored.
		pose.facingScale = 1.0
		if time >= 17.0:
			var turn := clampf((time - 17.0) / 0.28, 0.0, 1.0)
			pose.facingScale = (1.0 if turn < 0.5 else -1.0) * (0.12 + 0.88 * absf(cos(PI * turn)))
		pet.set_seated(seated)
		detail.set_seated(seated)
		pet.apply_pose(pose, 1.0 / 60.0)
		detail.apply_pose(pose, 1.0 / 60.0)
		for id in detail.meshes:
			detail.meshes[id].visible = id == Tail.MESH_ID
		for mesh in detail.sitting.transition_meshes.values():
			mesh.node.hide()
		detail.sitting.sprite.hide()
		state_label.text = "Standing - gentle sweep" if time < 6 else (
			"Seated - smaller movement" if time < 12 else (
			"Standing up" if time < 14 else "Walking - soft balancing motion"))
		raw = pet.model.call("get_raw_mesh_vertices")
		var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
		var points := Secondary.read_points(pet.meshes[Tail.MESH_ID])
		var finite := true
		var attached := true
		var inside := true
		for i in points.size():
			finite = finite and points[i].is_finite()
			max_motion = maxf(max_motion, points[i].distance_to(raw[Tail.MESH_ID][i]))
			if pet.tail.bindings[i] <= 2.0:
				attached = attached and points[i].distance_to(raw[Tail.MESH_ID][i]) < 0.002
			var screen: Vector2 = pet.transform * pet.model.transform * points[i]
			inside = inside and Rect2(1, 1, 598, 638).has_point(screen)
		_check(finite and attached, "finite tail with attached root")
		_check(inside, "tail clipped at turn/stand/sit/walk")
		var nonfolded := true
		for n in range(0, triangles.size(), 3):
			var a := triangles[n]
			var b := triangles[n + 1]
			var c := triangles[n + 2]
			var before: float = (raw[Tail.MESH_ID][b] - raw[Tail.MESH_ID][a]).cross(raw[Tail.MESH_ID][c] - raw[Tail.MESH_ID][a])
			var after := (points[b] - points[a]).cross(points[c] - points[a])
			nonfolded = nonfolded and before * after > 0.0
			worst_stretch = maxf(worst_stretch, absf(after / before - 1.0))
		_check(nonfolded, "tail triangle flipped")
		_check(pet.meshes[Tail.MESH_ID].z_index == 0, "tail changed layer")
		# Reapplying an unchanged frame must never accumulate mesh deformation.
		if frame % 60 == 0:
			var stable: PackedVector2Array = pet.tail.deform_points(raw[Tail.MESH_ID], body)
			pet.tail.update(0.0, pose.walkPhase, walk, pet.sitting.amount)
			_check(stable == pet.tail.deform_points(raw[Tail.MESH_ID], body), "zero-delta drift")
		if render:
			await process_frame
			await RenderingServer.frame_post_draw
			if frame % 2 == 0:
				root.get_texture().get_image().save_png(folder.path_join("%04d.png" % (frame / 2)))
	_check(max_motion > 145.0 and max_motion < 185.0, "stronger but bounded sway")
	_check(worst_stretch < 0.25, "excessive tail texture stretch")
	_check(original_uvs == pet.meshes[Tail.MESH_ID].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV], "changed atlas UVs")
	# Controller playback is stable across common refresh rates.
	var trajectories := []
	for fps in [30, 60, 120]:
		var controller := Tail.new()
		controller.rng.seed = 12
		controller.next_sway = 0.5
		var samples := []
		for frame in range(fps * 30):
			controller.update(1.0 / fps, 0.0, 0.0, 0.0)
			if (frame + 1) % fps == 0:
				samples.append(Vector2(controller.angle, controller.tip_angle))
		trajectories.append(samples)
	for i in 30:
		_check(trajectories[0][i].distance_to(trajectories[2][i]) < 0.0001
			and trajectories[1][i].distance_to(trajectories[2][i]) < 0.0001, "refresh-rate drift")
	print("TAIL: 1200 frames; %d checks, %d failures; max travel %.2f px; max area change %.3f" %
		[checks, failures, max_motion, worst_stretch])
	quit(0 if failures == 0 else 1)
