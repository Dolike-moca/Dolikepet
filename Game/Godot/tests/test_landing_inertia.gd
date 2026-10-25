extends SceneTree
const Landing = preload("res://scripts/landing_motion.gd")
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
		if failures < 15: printerr("LANDING INERTIA: " + message)
func controller_checks() -> void:
	for speed in [1.6, 4.6, 7.0]:
		for direction in [-1.0, 1.0]:
			var trajectories := []
			for fps in [30, 60, 120]:
				for facing in [-1.0, 1.0]:
					var motion := Landing.new()
					motion.start({"height": 0.15, "speed": speed, "lateral_speed": direction * facing * 0.7, "facing": facing})
					var outward := 0.0
					var rebound := 0.0
					var samples := []
					for frame in fps * 2:
						motion.update(1.0 / fps)
						var pose: Dictionary = motion.pose()
						var tilt: float = pose.landingUpperTilt * direction
						if motion.age <= 0.25:
							check(tilt >= 0.0, "first lean opposed falling direction")
							outward = maxf(outward, tilt)
						elif motion.age <= 0.55: rebound = maxf(rebound, -tilt)
						check(absf(pose.landingUpperTilt) < deg_to_rad(13.0), "unbounded impact lean")
						if (frame + 1) % (fps / 10) == 0: samples.append(Vector2(pose.landingUpperTilt, pose.landingUpperBounce))
						if frame == fps / 2:
							var frozen: Dictionary = motion.pose()
							motion.update(2.0, true)
							check(frozen == motion.pose(), "paused recoil changed")
					check(outward > deg_to_rad(2.0) and rebound > outward * 0.25 and rebound < outward * 0.55, "missing smaller opposite rebound")
					check(motion.pose().landingUpperTilt == 0.0 and motion.pose().landingUpperBounce == 0.0, "upper body did not settle")
					trajectories.append(samples)
				for track in trajectories:
					for i in track.size(): check(track[i].distance_to(trajectories[0][i]) < 0.00001, "frame-rate/facing drift")
	var vertical := Landing.new()
	vertical.start({"height": 1.2, "speed": 4.5, "angle": 0.18, "facing": 1.0})
	vertical.update(0.1)
	check(vertical.pose().landingUpperTilt > 0.0, "vertical back-lean lost existing attitude")
	vertical.cancel()
	check(vertical.pose().landingUpperTilt == 0.0 and vertical.recoil.angular_velocity == 0.0, "regrab retained recoil")
func run() -> void:
	controller_checks()
	if "--controller-only" in OS.get_cmdline_user_args():
		print("LANDING INERTIA CONTROLLER: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	root.size = Vector2i(1720, 960)
	root.position = Vector2i(10, 10)
	root.mouse_passthrough = true
	var bg := ColorRect.new()
	bg.size = root.size
	bg.color = Color("242630")
	root.add_child(bg)
	var cases := []
	for i in 4:
		var stage := Node2D.new()
		root.add_child(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))), pet.failure)
		if not pet.available: quit(1); return
		pet.fit(Vector2.ONE * 360)
		pet.tail.rng.seed = 1729
		pet.tail.held_rng.seed = 329
		var facing := -1.0 if i in [1, 2] else 1.0
		var direction := -1.0 if i in [0, 2] else 1.0
		var physics := Physics.new()
		root.add_child(physics)
		physics.set_geometry(Vector2.ONE * 360, Rect2(10 + i * 430, 70, 410, 830), pet.physics_anchor(facing))
		physics.body.collision_layer = 1 << i
		physics.body.collision_mask = 1 << i
		for wall in physics.walls:
			wall.collision_layer = 1 << i
			wall.collision_mask = 1 << i
		var at := Vector2(35 + i * 430, 900.0 - 360.0 * (2.2 if i >= 2 else 1.15))
		physics.reposition(at)
		physics.begin(at, at + physics.anchor, facing)
		var drag := Drag.new()
		drag.begin(at, facing)
		var behavior := Behavior.new()
		behavior.automatic_blinks = false
		var title := ("低处" if i < 2 else "高处") + (" · 向身前摔" if direction < 0 else " · 向身后摔")
		var label := Label.new()
		label.position = Vector2(22 + 430 * i, 25)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
		var floor_line := ColorRect.new()
		floor_line.position = Vector2(10 + i * 430, 900)
		floor_line.size = Vector2(410, 2)
		floor_line.color = Color("74839a")
		root.add_child(floor_line)
		cases.append({"pet": pet, "stage": stage, "physics": physics, "drag": drag, "behavior": behavior,
			"landing": Landing.new(), "at": at, "facing": facing, "direction": direction, "label": label,
			"title": title, "impacts": 0, "first": 0.0, "rebound": 0.0, "support": Vector2(INF, INF), "support_error": 0.0})
	var folder := "res://../../_work/tests/landing-inertia-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var clipped := 0
	for frame in 300:
		for i in 4:
			var c: Dictionary = cases[i]
			var pet = c.pet
			var physics = c.physics
			var landing = c.landing
			if frame == 30:
				physics.body.linear_velocity.x = c.direction * c.facing * 100.0
				physics.release()
				c.drag.release()
			var result: Dictionary = physics.update(1.0 / 60, c.at, physics.size, physics.area, frame < 30)
			if result.move: c.at = result.position
			if not result.impact.is_empty():
				c.impacts += 1
				landing.start(result.impact)
				check(signf(result.impact.lateral_speed * c.facing) == c.direction, "native pre-impact direction lost")
			var event: Dictionary = landing.update(1.0 / 60)
			if event.sit: pet.set_seated(true, event.sit_speed)
			c.drag.pointer_previous = c.at + physics.body.spring_gap
			c.drag.update(1.0 / 60, c.at, physics.size)
			var pose: Dictionary = c.behavior.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 360, false).duplicate()
			pose.merge(c.drag.pose())
			pose.merge(physics.pose())
			pose.merge(landing.pose())
			pose.facingScale = c.facing
			pose.motionOrigin = c.at
			if physics.active(): pose.dragTilt = physics.body.rotation * c.facing
			pet.apply_pose(pose, 1.0 / 60)
			c.stage.position = c.at
			pet.sitting.update_composite_coordinates()
			c.first = maxf(c.first, pose.landingUpperTilt * c.direction)
			c.rebound = maxf(c.rebound, -pose.landingUpperTilt * c.direction)
			var phase := "落稳"
			if c.impacts == 0: phase = "悬挂" if frame < 30 else "下落"
			elif absf(pose.landingUpperTilt) > 0.02:
				phase = ("前倾" if pose.landingUpperTilt < 0.0 else "后仰") + ("卸力" if pose.landingUpperTilt * c.direction > 0.0 else "回弹")
			c.label.text = c.title + "\n" + phase
			if i >= 2 and landing.age >= 0.5:
				var support: Vector2 = pet.sitting.sprite.global_transform * pet.sitting.sprite.texture.get_size()
				if c.support.x == INF: c.support = support
				c.support_error = maxf(c.support_error, support.distance_to(c.support))
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			for id in pet.meshes:
				var node: MeshInstance2D = pet.meshes[id]
				var points := Secondary.read_points(node)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				for p in points:
					valid = valid and p.is_finite()
					if node.visible and node.self_modulate.a > 0.01 and not Rect2(-1, -1, 362, 362).has_point(pet.transform * pet.model.transform * p): clipped += 1
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var d := indices[n + 2]
					var before: float = (raw[id][b] - raw[id][a]).cross(raw[id][d] - raw[id][a])
					var after := (points[b] - points[a]).cross(points[d] - points[a])
					valid = valid and (absf(before) < 0.01 or before * after > 0)
				check(valid, "mesh folded/nonfinite " + id)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0: root.get_texture().get_image().save_png(folder.path_join("%04d.png" % (frame / 2)))
	check(clipped == 0, "viewport clipped vertices " + str(clipped))
	for c in cases:
		check(c.impacts == 1 and c.first > deg_to_rad(2.0) and c.rebound > c.first * 0.25, "missing directional landing/rebound")
		check(c.support_error < 1.0, "seated support moved with recoil")
		print("%s: first %.2f / opposite %.2f degrees, support %.4f px" % [c.title, rad_to_deg(c.first), rad_to_deg(c.rebound), c.support_error])
	print("LANDING INERTIA: %d checks, %d failures; clipped %d" % [checks, failures, clipped])
	quit(1 if failures else 0)
