extends SceneTree
const Physics = preload("res://scripts/desktop_physics.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("PHYSICS RENDER: " + message)
func run() -> void:
	root.size = Vector2i(1200, 1000)
	root.position = Vector2i(20, 20)
	root.mouse_passthrough = true
	var bg := ColorRect.new()
	bg.size = Vector2(1200, 1000)
	bg.color = Color("242630")
	root.add_child(bg)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	var pets := []
	var stages := []
	for i in 2:
		var stage := Node2D.new()
		root.add_child(stage)
		stages.append(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		check(pet.load_pet(config), pet.failure)
		if not pet.available: quit(1); return
		pet.fit(Vector2.ONE * (320 if i == 0 else 460))
		pet.tail.automatic = false
		pets.append(pet)
	var bounds := Rect2(20, 80, 620, 840)
	for edge in [Rect2(20, 80, 620, 2), Rect2(20, 80, 2, 840), Rect2(638, 80, 2, 840), Rect2(20, 918, 620, 2)]:
		var line := ColorRect.new()
		line.position = edge.position
		line.size = edge.size
		line.color = Color("617086")
		root.add_child(line)
	var label := Label.new()
	label.position = Vector2(30, 24)
	label.add_theme_font_size_override("font_size", 22)
	root.add_child(label)
	var note := Label.new()
	note.position = Vector2(665, 80)
	note.text = "镜像方向 · 模型近景\n原生刚体弹簧 / 抛动 / 碰墙回弹\n底部无弹跳，逐渐停稳"
	note.add_theme_font_size_override("font_size", 20)
	root.add_child(note)
	var physics = Physics.new()
	root.add_child(physics)
	physics.set_geometry(Vector2.ONE * 320, bounds, pets[0].physics_anchor())
	var drag = Drag.new()
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var at := Vector2(120, 600)
	physics.reposition(at)
	var folder := "res://../../_work/tests/physics-b2-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var peak_angle := 0.0
	var peak_lag := 0.0
	var clipped := 0
	var closed_seen := false
	for frame in 480:
		if frame == 15 or frame == 260:
			drag.begin(at)
			physics.begin(at, at + physics.anchor, 1)
		if frame >= 15 and frame < 90:
			var t := float(frame - 15) / 75
			physics.set_pointer(Vector2(160 + 280 * t * t, 660 - 480 * t))
		if frame >= 260 and frame < 300:
			var t := float(frame - 260) / 40
			physics.set_pointer(Vector2(430 - 320 * t, 650 - 380 * t))
		if frame == 90 or frame == 300:
			drag.release()
			physics.release()
		var result: Dictionary = physics.update(1.0 / 60, at, Vector2.ONE * 320, bounds, physics.state == "held")
		if result.move: at = result.position
		drag.pointer_previous = at + physics.body.spring_gap
		drag.update(1.0 / 60, at, Vector2.ONE * 320)
		var pose: Dictionary = behavior.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 320, false).duplicate()
		pose.merge(drag.pose())
		pose.merge(physics.pose())
		pose.motionOrigin = at
		pose.fallLanded = result.landed
		if physics.active():
			pose.dragTilt = physics.body.rotation
			pose.dragSwingSpeed = physics.body.angular_velocity
		peak_angle = maxf(peak_angle, absf(physics.body.rotation))
		peak_lag = maxf(peak_lag, physics.body.spring_gap.length())
		label.text = "B2 原生物理 · " + physics.state + "   %.1f°   速度 %.0f" % [rad_to_deg(physics.body.rotation), physics.body.linear_velocity.length()]
		for i in 2:
			var pet = pets[i]
			var draw_pose := pose.duplicate()
			draw_pose.facingScale = 1.0 if i == 0 else -1.0
			draw_pose.dragTilt = pose.dragTilt * draw_pose.facingScale
			draw_pose.dragSwingSpeed = pose.dragSwingSpeed * draw_pose.facingScale
			pet.apply_pose(draw_pose, 1.0 / 60)
			stages[i].position = at if i == 0 else Vector2(680, 250)
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			for id in pet.meshes:
				var node: MeshInstance2D = pet.meshes[id]
				var points := Secondary.read_points(node)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				for p in points:
					valid = valid and p.is_finite()
					if node.visible and node.self_modulate.a > 0.01 and not Rect2(Vector2(-1, -1), pet.fitted_size + Vector2(2, 2)).has_point(pet.transform * pet.model.transform * p): clipped += 1
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var c := indices[n + 2]
					var before: float = (raw[id][b] - raw[id][a]).cross(raw[id][c] - raw[id][a])
					var after := (points[b] - points[a]).cross(points[c] - points[a])
					valid = valid and (absf(before) < 0.01 or before * after > 0.0)
				check(valid, "folded/nonfinite " + id)
			if frame >= 90 and frame < 110 and pet.secondary_pose.get("dragEyeOpenness", 1.0) < 0.01: closed_seen = true
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0:
			root.get_texture().get_image().save_png(folder.path_join("frame_%04d.png" % (frame / 2)))
	check(physics.body.impact_count > 0, "no collision in rendered trajectory")
	check(peak_angle > deg_to_rad(4), "hanging has no angular response")
	check(peak_lag > 30, "fast drag has no lag")
	check(closed_seen, "squeezed to closed eye handoff missing")
	check(clipped == 0, "viewport-clipped vertices: " + str(clipped))
	print("PHYSICS RENDER: %d checks, %d failures; angle %.2f; lag %.2f; clipped %d; contacts %d" % [checks, failures, rad_to_deg(peak_angle), peak_lag, clipped, physics.body.impact_count])
	quit(1 if failures else 0)
