extends SceneTree
const Tail = preload("res://scripts/tail_motion.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const DragPose = preload("res://scripts/drag_pose.gd")
const Landing = preload("res://scripts/landing_motion.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("HELD TAIL: " + message)
func controller_checks() -> void:
	var trajectories := []
	for fps in [30, 60, 120]:
		var tail := Tail.new()
		tail.rng.seed = 1729
		tail.held_rng.seed = 329
		tail.next_sway = 100.0
		var samples := []
		var largest := 0.0
		var opposite_tip := false
		var pauses := 0
		for frame in fps * 12:
			var t: float = float(frame) / fps
			var held: bool = (t >= 0.5 and t < 6.5) or (t >= 8.0 and t < 9.0)
			tail.update(1.0 / fps, 0.0, 0.0, 0.0, held)
			largest = maxf(largest, absf(tail.angle))
			opposite_tip = opposite_tip or (absf(tail.angle) > 0.08 and tail.angle * tail.tip_angle < -0.005)
			if held and tail.group_age > tail.group_duration: pauses += 1
			check(is_finite(tail.angle) and absf(tail.angle) < 0.70 and absf(tail.tip_angle) < 0.40, "unbounded angles")
			if held: check(tail.group_cycles in [2, 3] and tail.group_rest >= 0.15 and tail.group_rest <= 0.30, "wrong grouped rhythm")
			if (frame + 1) % (fps / 2) == 0: samples.append(Vector2(tail.angle, tail.tip_angle))
			if frame == fps * 2:
				var before := [tail.angle, tail.velocity, tail.tip_angle, tail.group_age, tail.held_mix]
				tail.update(1.0, 0.0, 0.0, 0.0, held, true)
				check(before == [tail.angle, tail.velocity, tail.tip_angle, tail.group_age, tail.held_mix], "pause advanced tail")
		check(largest > 0.40 and opposite_tip and pauses > fps / 2, "large sweep / tip lag / short breaks missing")
		check(tail.group_count >= 5 and tail.held_mix == 0.0 and absf(tail.angle) < 0.005, "release did not settle")
		trajectories.append(samples)
	for i in trajectories[0].size():
		check(trajectories[0][i].distance_to(trajectories[2][i]) < 0.0001 and trajectories[1][i].distance_to(trajectories[2][i]) < 0.0001, "refresh-rate drift")
func run() -> void:
	controller_checks()
	if "--controller-only" in OS.get_cmdline_user_args():
		print("HELD TAIL CONTROLLER: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	root.size = Vector2i(1100, 740)
	root.position = Vector2i(20, 20)
	root.mouse_passthrough = true
	RenderingServer.set_default_clear_color(Color("242630"))
	var cases := []
	for i in 2:
		var stage := Node2D.new()
		root.add_child(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))), pet.failure)
		if not pet.available: quit(1); return
		pet.fit(Vector2.ONE * 480)
		pet.tail.rng.seed = 1729
		pet.tail.held_rng.seed = 329
		pet.tail.next_sway = 100.0
		var label := Label.new()
		label.position = Vector2(25 + i * 550, 20)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
		var behavior = Behavior.new()
		behavior.automatic_blinks = false
		cases.append({"pet": pet, "stage": stage, "label": label, "behavior": behavior, "drag": Drag.new(), "landing": Landing.new()})
	var folder := "res://../../_work/tests/held-tail-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var clipped := 0
	var worst_area := 0.0
	var max_motion := 0.0
	var max_root := 0.0
	var worst_frame := 0
	var worst_isolated := 0.0
	var extreme_clipped := 0
	var capture := not "--no-capture" in OS.get_cmdline_user_args()
	for frame in 600:
		var t := frame / 60.0
		for i in 2:
			var c: Dictionary = cases[i]
			var pet = c.pet
			var drag = c.drag
			var facing := 1.0 if i == 0 else -1.0
			var at := Vector2(30 + i * 550, lerpf(180.0, 70.0, smoothstep(0.5, 0.9, t)) + 110.0 * smoothstep(5.5, 6.2, t))
			if frame == 30: drag.begin(at, facing)
			if frame == 330: drag.release()
			if frame == 372: c.landing.start({"height": 1.2, "speed": 4.4})
			var event: Dictionary = c.landing.update(1.0 / 60)
			if event.sit: pet.set_seated(true, event.sit_speed)
			drag.update(1.0 / 60, at, Vector2.ONE * 480)
			var pose: Dictionary = c.behavior.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 480, false).duplicate()
			pose.merge(drag.pose())
			pose.merge(c.landing.pose())
			pose.physicsActive = t >= 0.5 and t < 6.2
			pose.dragTilt = deg_to_rad(24.0 * sin((t - 0.5) * 2.6)) * facing * smoothstep(0.5, 0.9, t) * (1.0 - smoothstep(5.5, 6.2, t))
			pose.dragStretch = 0.135 * pose.dragHang
			pose.dragBend = deg_to_rad(5.0) * sin(t * 3.0) * pose.dragHang
			pose.facingScale = facing
			pose.fallActive = t >= 5.5 and t < 6.2
			pose.fallSpeed = 4.4 * smoothstep(5.5, 6.2, t)
			pose.motionOrigin = at
			c.stage.position = at
			pet.apply_pose(pose, 1.0 / 60)
			c.label.text = ("拎起 · 分组快甩" if i == 0 else "镜像朝向 · 同步检查") + ("\n短暂停顿" if drag.state == "held" and pet.tail.group_age > pet.tail.group_duration else "")
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
			var isolated: PackedVector2Array = pet.tail.deform_points(raw[Tail.MESH_ID], body)
			if frame >= 30 and frame < 330 and frame % 6 == 0:
				for tilt in [-24.0, 24.0]:
					for bend in [-5.0, 5.0]:
						var extreme: Transform2D = pet.transform * DragPose.new().root_transform(pet.sitting.root_transform,
							{"dragTilt": deg_to_rad(tilt) * facing, "physicsActive": true}, facing)
						for point in isolated:
							var attached: Vector2 = body * DragPose.bend_tail_point(body.affine_inverse() * point, deg_to_rad(bend), 0.135)
							if not Rect2(-1, -1, 482, 482).has_point(extreme * attached): extreme_clipped += 1
			for n in isolated.size():
				max_motion = maxf(max_motion, isolated[n].distance_to(raw[Tail.MESH_ID][n]))
				if pet.tail.bindings[n] <= 2.0: max_root = maxf(max_root, isolated[n].distance_to(raw[Tail.MESH_ID][n]))
			var node: MeshInstance2D = pet.meshes[Tail.MESH_ID]
			var points := Secondary.read_points(node)
			for p in points:
				check(p.is_finite(), "nonfinite vertex")
				if not Rect2(-1, -1, 482, 482).has_point(pet.transform * pet.model.transform * p):
					if clipped == 0: print("FIRST CLIP: frame %d at %s angle %.3f tip %.3f" % [frame, pet.transform * pet.model.transform * p, pet.tail.angle, pet.tail.tip_angle])
					clipped += 1
			var triangles: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			for n in range(0, triangles.size(), 3):
				var a := triangles[n]
				var b := triangles[n + 1]
				var d := triangles[n + 2]
				var before: float = (raw[Tail.MESH_ID][b] - raw[Tail.MESH_ID][a]).cross(raw[Tail.MESH_ID][d] - raw[Tail.MESH_ID][a])
				var after := (points[b] - points[a]).cross(points[d] - points[a])
				check(before * after > 0.0, "tail triangle folded")
				if absf(after / before - 1.0) > worst_area:
					worst_area = absf(after / before - 1.0)
					worst_frame = frame
				var isolated_area: float = (isolated[b] - isolated[a]).cross(isolated[d] - isolated[a])
				worst_isolated = maxf(worst_isolated, absf(isolated_area / before - 1.0))
		if capture:
			await process_frame
			await RenderingServer.frame_post_draw
			if frame % 2 == 0: root.get_texture().get_image().save_png(folder.path_join("%04d.png" % (frame / 2)))
	check(clipped == 0, "tail clipped while held " + str(clipped))
	check(extreme_clipped == 0, "tail clipped at physical limits " + str(extreme_clipped))
	check(max_root < 0.002 and max_motion > 220.0, "tail root or large sweep incorrect")
	check(worst_area < 0.55, "tail texture stretched excessively")
	print("AREA DIAGNOSTIC: frame %d isolated %.3f" % [worst_frame, worst_isolated])
	print("HELD TAIL: %d checks, %d failures; clipped %d; travel %.2f; root %.6f; area %.3f" % [checks, failures, clipped, max_motion, max_root, worst_area])
	quit(1 if failures else 0)
