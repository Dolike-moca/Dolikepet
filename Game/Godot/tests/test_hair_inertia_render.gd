extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15:
			printerr("HAIR RENDER: " + message)

func _motion(t: float) -> Vector2:
	# 0.15/2.4 pet-heights per second in the left/right panels, same input path.
	var x := clampf(t - 0.5, 0.0, 0.75) - clampf(t - 3.0, 0.0, 0.4)
	x += clampf(t - 3.4, 0.0, 0.4) # Immediate reversal, then another stop.
	var y := clampf(t - 5.0, 0.0, 0.35) - clampf(t - 5.35, 0.0, 0.35)
	return Vector2(x, y)

func _run() -> void:
	root.size = Vector2i(1200, 740)
	root.position = Vector2i(30, 30)
	root.mouse_passthrough = true
	var background := ColorRect.new()
	background.color = Color("#242630")
	background.size = Vector2(1200, 740)
	root.add_child(background)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	var pets := []
	var behaviors := []
	for index in 2:
		var stage := Node2D.new()
		stage.position = Vector2(index * 600, 35)
		root.add_child(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		_check(pet.load_pet(config), pet.failure)
		if not pet.available:
			quit(1)
			return
		pet.fit(Vector2(600, 700))
		pet.tail.rng.seed = 1729
		pet.tail.next_sway = 0.5
		pets.append(pet)
		var behavior = Behavior.new()
		behavior.automatic_blinks = false
		behaviors.append(behavior)
		var label := Label.new()
		label.position = Vector2(18 + index * 600, 10)
		label.text = "SLOW  |  Gentle follow" if index == 0 else "FAST  |  Trailing + return swing"
		label.add_theme_font_size_override("font_size", 22)
		root.add_child(label)
	var action := Label.new()
	action.position = Vector2(440, 690)
	action.add_theme_font_size_override("font_size", 19)
	root.add_child(action)
	var output := "res://../../_work/tests/hair-inertia-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var max_step := 0.0
	var previous := [{}, {}]
	var roots_stable := true
	var layered := false
	for frame in 960:
		var t := frame / 60.0
		var seated := t >= 7.0 and t < 9.0
		var walk := smoothstep(10.5, 11.0, t) * (1.0 - smoothstep(12.0, 12.3, t))
		var turn := smoothstep(12.5, 12.78, t)
		var facing := (1.0 if turn < 0.5 else -1.0) * maxf(0.12, absf(cos(PI * turn)))
		action.text = "Move right, then stop" if t < 3 else (
			"Quick reversal" if t < 5 else ("Up / down" if t < 7 else (
			"Sit / stand" if t < 10.5 else ("Walk / stop / turn" if t < 13 else "Settled"))))
		for index in 2:
			var pet = pets[index]
			var pose: Dictionary = behaviors[index].update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
			pose.motionOrigin = _motion(t) * (0.15 if index == 0 else 2.4) * 600.0
			pose.walkPhase = maxf(0.0, t - 10.5) * TAU * 1.7
			pose.walkWeight = walk
			pose.facingScale = facing
			pet.set_seated(seated)
			pet.apply_pose(pose, 1.0 / 60.0)
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
			var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
			for id in Secondary.HAIR:
				var node: MeshInstance2D = pet.meshes[id]
				var points := Secondary.read_points(node)
				var baseline: PackedVector2Array = pet.deformation.deform_points(id, raw[id], pose, head, body)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				var root_index := 0
				for i in points.size():
					# Tuft grows up from its bottom; the other layers hang down.
					if (raw[id][i].y > raw[id][root_index].y) == (id == "ArtMesh"):
						root_index = i
					valid = valid and points[i].is_finite()
					var screen: Vector2 = pet.transform * pet.model.transform * points[i]
					valid = valid and Rect2(1, 1, 598, 698).has_point(screen)
				roots_stable = roots_stable and points[root_index].distance_to(baseline[root_index]) < 0.002
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var c := indices[n + 2]
					var before: float = (raw[id][b] - raw[id][a]).cross(raw[id][c] - raw[id][a])
					var after := (points[b] - points[a]).cross(points[c] - points[a])
					valid = valid and (absf(before) < 0.01 or before * after > 0.0)
				_check(valid, "folded/clipped hair " + id)
			var screen_offsets: Dictionary = pet.hair_inertia.offsets
			for key in screen_offsets:
				if previous[index].has(key):
					max_step = maxf(max_step, screen_offsets[key].distance_to(previous[index][key]))
			previous[index] = screen_offsets.duplicate()
			layered = layered or screen_offsets.hairBack.distance_to(screen_offsets.hairFront) > 5.0
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0:
			root.get_texture().get_image().save_png(output.path_join("%04d.png" % (frame / 2)))
	_check(roots_stable, "hair root detached")
	_check(layered, "missing different layer responses")
	_check(max_step < 14.0, "inertial offset jumped")
	_check(pets[0].sitting.amount == 0.0 and pets[1].facing_scale == -1.0, "stand/turn did not complete")
	print("HAIR RENDER: 960 frames x 2; %d checks, %d failures; max step %.3f model px" % [checks, failures, max_step])
	quit(0 if failures == 0 else 1)
