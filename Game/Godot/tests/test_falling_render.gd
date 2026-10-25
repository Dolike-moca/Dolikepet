extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const Fall = preload("res://scripts/falling_motion.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("FALL RENDER: " + message)
func run() -> void:
	root.size = Vector2i(1200, 1000)
	root.position = Vector2i(20, 20)
	root.mouse_passthrough = true
	var bg := ColorRect.new()
	bg.size = Vector2(1200, 1000)
	bg.color = Color("#242630")
	root.add_child(bg)
	var pets := []
	var stages := []
	var behaviors := []
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	for index in 2:
		var stage := Node2D.new()
		root.add_child(stage)
		stages.append(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		check(pet.load_pet(config), pet.failure)
		if not pet.available: quit(1); return
		pet.fit(Vector2.ONE * (420 if index == 0 else 580))
		pet.tail.automatic = false
		pets.append(pet)
		var behavior = Behavior.new()
		behavior.automatic_blinks = false
		behaviors.append(behavior)
		var label := Label.new()
		label.position = Vector2(index * 600 + 20, 20)
		label.text = "下落全景" if index == 0 else "头发放大 · 固定视图"
		label.add_theme_font_size_override("font_size", 24)
		root.add_child(label)
	var floor_line := ColorRect.new()
	floor_line.position = Vector2(20, 920)
	floor_line.size = Vector2(540, 2)
	floor_line.color = Color("#617086")
	root.add_child(floor_line)
	var note := Label.new()
	note.position = Vector2(20, 950)
	note.text = "真实模型模拟：松手 → 短暂停顿 → 加速下落。PSD 惊讶表情、躯干微伸、分层头发。"
	root.add_child(note)
	var status := Label.new()
	status.position = Vector2(20, 55)
	root.add_child(status)
	var drag = Drag.new()
	var fall = Fall.new()
	var at := Vector2(70, 70)
	drag.begin(at)
	var out := "res://../../_work/tests/fall-v1-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var max_scarf_error := 0.0
	var max_root_error := 0.0
	var max_torso_extension := 0.0
	var max_torso_error := 0.0
	var max_boot_error := 0.0
	var closed_handoff := false
	var clipped := 0
	var max_back := 0.0
	for frame in 360:
		var held: bool = frame < 45 or (frame >= 180 and frame < 225)
		if frame == 45 or frame == 225: drag.release()
		if frame == 180: drag.begin(at)
		if frame >= 180 and frame < 225:
			var target := Vector2(70, lerpf(500, 70, smoothstep(0, 1, (frame - 180) / 44.0)))
			at = drag.follow_pointer(1.0 / 60, target, Vector2(420, 420))
		drag.update(1.0 / 60, at, Vector2(420, 420))
		var fall_result: Dictionary = fall.update(1.0 / 60, at, Vector2(420, 420), Rect2(0, 0, 600, 920), held)
		if fall_result.move: at = fall_result.position
		if fall.state == "falling" or fall_result.landed:
			drag.stretch = 0.0
			drag.stretch_speed = 0.0
		status.text = "拎起" if held else ("下落中" if fall.active() else "到达底边")
		for index in 2:
			var pet = pets[index]
			var pose: Dictionary = behaviors[index].update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 420, false).duplicate()
			pose.merge(drag.pose())
			pose.merge(fall.pose())
			pose.fallLanded = fall_result.landed
			pose.dragStretch *= 1.0 - pose.fallNormalize
			pose.motionOrigin = at
			pose.facingScale = 1.0 if index == 0 else -1.0
			pet.apply_pose(pose, 1.0 / 60)
			if frame >= 45 and frame < 60:
				if drag.face > 0.00001: check(pet.secondary_pose.eyeNear == 0.0, "eyes opened before squeezed artwork cleared")
				elif pet.secondary_pose.dragEyeOpenness < 0.01: closed_handoff = true
			stages[index].position = at if index == 0 else Vector2(600, 150)
			max_back = maxf(max_back, -pet.falling_hair.offsets.hairBack.y)
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			for id in pet.meshes:
				var node: MeshInstance2D = pet.meshes[id]
				var points := Secondary.read_points(node)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				for p in points:
					valid = valid and p.is_finite()
					var size: Vector2 = pet.fitted_size
					if node.visible and not Rect2(Vector2(-1, -1), size + Vector2(2, 2)).has_point(pet.transform * pet.model.transform * p): clipped += 1
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var c := indices[n + 2]
					var before: float = (raw[id][b] - raw[id][a]).cross(raw[id][c] - raw[id][a])
					var after := (points[b] - points[a]).cross(points[c] - points[a])
					valid = valid and (absf(before) < 0.01 or before * after > 0.0)
				check(valid, "folded mesh " + id)
			var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
			var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
			var scarf := Secondary.read_points(pet.meshes.ArtMesh5)
			for i in scarf.size():
				var p: Vector2 = pet.deformation.reference.ArtMesh5[i]
				if p.y + 1024 <= 1160:
					max_scarf_error = maxf(max_scarf_error, scarf[i].distance_to(raw.ArtMesh5[i] + head * p - body * p))
			if fall.state == "falling":
				var torso := Secondary.read_points(pet.meshes.ArtMesh24)
				var inverse := body.affine_inverse()
				for i in torso.size():
					var p: Vector2 = inverse * raw.ArtMesh24[i]
					var amount: float = pet.secondary_pose.fallStretch
					# Independently check the axial extension and rigid neck region.
					var expected_y := p.y + amount * clampf(p.y - 266.0, 0.0, 270.0)
					max_torso_error = maxf(max_torso_error, absf((inverse * torso[i]).y - expected_y))
					max_torso_extension = maxf(max_torso_extension, torso[i].y - raw.ArtMesh24[i].y)
				check(pet.secondary_pose.fallStretch <= 0.065, "excessive fall elongation")
				check(pet.falling_pose.sprite.visible, "missing falling expression")
				check(pet.meshes.ArtMesh3.self_modulate.a == 0.0, "old mouth overlaps falling mouth")
				for id in ["ArtMesh22", "ArtMesh23"]:
					var leg := Secondary.read_points(pet.meshes[id])
					var first := -1
					for i in leg.size():
						var p: Vector2 = inverse * raw[id][i]
						if p.y + 1024.0 < 1810.0: continue
						if first < 0: first = i
						var before: float = (inverse * raw[id][first]).distance_to(p)
						var after := (inverse * leg[first]).distance_to(inverse * leg[i])
						max_boot_error = maxf(max_boot_error, absf(before - after))
				for id in Secondary.HAIR:
					var layer: Array = Secondary.HAIR[id]
					var control: Dictionary = pet.secondary_pose.duplicate()
					control.fallingHair = {}
					var baseline: PackedVector2Array = pet.deformation.deform_points(id, raw[id], control, head, body)
					var actual: PackedVector2Array = pet.deformation.deform_points(id, raw[id], pet.secondary_pose, head, body)
					for i in actual.size():
						var y: float = pet.deformation.reference[id][i].y + 1024.0
						var u: float = (y - layer[1]) / (layer[2] - layer[1])
						if layer[4]: u = 1.0 - u
						if u <= 0.18: max_root_error = maxf(max_root_error, actual[i].distance_to(baseline[i]))
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0: root.get_texture().get_image().save_png(out.path_join("%04d.png" % (frame / 2)))
	check(clipped == 0, "window clipping %d" % clipped)
	check(max_root_error < 0.001 and max_scarf_error < 0.001, "hair root / scarf detached")
	check(max_torso_error < 0.001 and max_torso_extension > 6.0 and max_torso_extension < 18.0, "torso elongation outside gentle range / neck moved")
	check(max_back > 65.0, "back hair lag too small to show")
	check(max_boot_error < 0.002, "boot shape stretched")
	check(closed_handoff, "missing closed eyes between drag and fall")
	print("FALL RENDER: 360 frames x 2, %d checks, %d failures; root %.6f, scarf %.6f, torso %.6f, back %.2f, clipped %d" % [checks, failures, max_root_error, max_scarf_error, max_torso_error, max_back, clipped])
	quit(0 if failures == 0 else 1)
