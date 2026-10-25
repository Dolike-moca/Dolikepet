extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
var cursors: Array[Polygon2D] = []
func _initialize() -> void:
	call_deferred("run")
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("DRAG RENDER: " + message)
func run() -> void:
	root.size = Vector2i(1200, 800)
	root.position = Vector2i(20, 20)
	root.mouse_passthrough = true
	var bg := ColorRect.new()
	bg.size = Vector2(1200, 800)
	bg.color = Color("#242630")
	root.add_child(bg)
	var pets := []
	var states := []
	var behaviors := []
	var stages := []
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	for index in 2:
		var stage := Node2D.new()
		root.add_child(stage)
		stages.append(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		_check(pet.load_pet(config), pet.failure)
		if not pet.available: quit(1); return
		pet.fit(Vector2(500, 500))
		pet.set_seated(index == 1)
		pet.sitting.amount = float(index)
		pet.tail.rng.seed = 157
		pets.append(pet)
		states.append(Drag.new())
		var behavior = Behavior.new()
		behavior.automatic_blinks = false
		behaviors.append(behavior)
		var title := Label.new()
		title.position = Vector2(index * 600 + 20, 15)
		title.text = "Slow drag / standing" if index == 0 else "Fast drag / seated + mirrored"
		title.add_theme_font_size_override("font_size", 21)
		root.add_child(title)
		var cursor := Polygon2D.new()
		cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 16), Vector2(12, 26), Vector2(17, 23), Vector2(11, 14), Vector2(22, 14)])
		cursor.color = Color("#65e5ff")
		cursor.z_index = 100
		root.add_child(cursor)
		cursors.append(cursor)
	var note := Label.new()
	note.text = "Cyan marker = simulated mouse. Hold still to catch up; release stays in place."
	note.position = Vector2(20, 765)
	root.add_child(note)
	var out := "res://../../_work/tests/drag-v4-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var max_scarf_error := 0.0
	var returned := true
	var clipped := 0
	var max_strain := 0.0
	for frame in 540:
		var t := frame / 60.0
		var u := clampf(t - 1.4, 0.0, 2.4)
		for index in 2:
			var pet = pets[index]
			var d = states[index]
			var facing := 1.0 if index == 0 else -1.0
			var target := Vector2(50 + (55 if index == 0 else 100) * sin(u * (2.5 if index == 0 else 12.0)),
				230 - 150 * smoothstep(0.75, 1.4, t) + 30 * sin(u * 4.0))
			if frame == 45:
				d.begin(target, facing)
				pet.set_seated(false)
			if frame == 288: d.release()
			var position: Vector2 = d.follow_pointer(1.0 / 60, target, Vector2(500, 500)) if frame >= 45 else target
			d.update(1.0 / 60, position, Vector2(500, 500))
			max_strain = maxf(max_strain, d.stretch)
			var pose: Dictionary = behaviors[index].update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 500, false).duplicate()
			pose.merge(d.pose())
			pose.motionOrigin = position
			pose.facingScale = facing
			pet.apply_pose(pose, 1.0 / 60)
			stages[index].position = position + Vector2(index * 600, 0)
			cursors[index].position = target + Vector2(index * 600, 0) + pet.transform * pet.drag_pose.PIVOT
			cursors[index].visible = frame >= 45 and frame < 288
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			for id in pet.meshes:
				var node: MeshInstance2D = pet.meshes[id]
				var points := Secondary.read_points(node)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				for p in points:
					valid = valid and p.is_finite()
					if node.visible and not Rect2(-1, -1, 502, 502).has_point(pet.transform * pet.model.transform * p):
						clipped += 1
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var c := indices[n + 2]
					var before: float = (raw[id][b] - raw[id][a]).cross(raw[id][c] - raw[id][a])
					var after := (points[b] - points[a]).cross(points[c] - points[a])
					valid = valid and (absf(before) < 0.01 or before * after > 0.0)
				_check(valid, "folded mesh " + id)
			var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
			var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
			var scarf := Secondary.read_points(pet.meshes.ArtMesh5)
			for i in scarf.size():
				var p: Vector2 = pet.deformation.reference.ArtMesh5[i]
				if p.y + 1024 <= 1160:
					max_scarf_error = maxf(max_scarf_error, scarf[i].distance_to(raw.ArtMesh5[i] + head * p - body * p))
			if frame > 100 and frame < 288:
				_check(pet.meshes.ArtMesh12.self_modulate.a == 0.0 and pet.drag_pose.sprites[0].visible, "open eye leaking through held face")
			if frame == 539:
				returned = returned and d.state == "idle" and pet.sitting.amount == 0.0
				for id in pet.drag_pose.FACE_IDS:
					returned = returned and pet.meshes[id].self_modulate.a == 1.0
				for sprite in pet.drag_pose.sprites: returned = returned and not sprite.visible
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0: root.get_texture().get_image().save_png(out.path_join("%04d.png" % (frame / 2)))
	_check(returned, "release did not restore face / standing pose")
	_check(clipped == 0, "vertices outside pet window: %d" % clipped)
	_check(max_scarf_error < 0.001, "scarf detached")
	_check(max_strain > 0.06 and max_strain < 0.16, "pickup strain missing or excessive")
	print("DRAG RENDER: 540 frames x 2, %d checks, %d failures, scarf %.6f, clipped %d, pickup strain %.4f" % [checks, failures, max_scarf_error, clipped, max_strain])
	quit(0 if failures == 0 else 1)
