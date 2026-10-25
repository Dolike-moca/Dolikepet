extends SceneTree
const Physics = preload("res://scripts/desktop_physics.gd")
const Landing = preload("res://scripts/landing_motion.gd")
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
		if failures < 15: printerr("LANDING RENDER: " + message)
func run() -> void:
	root.size = Vector2i(1200, 1000)
	root.position = Vector2i(20, 20)
	root.mouse_passthrough = true
	var bg := ColorRect.new()
	bg.size = Vector2(1200, 1000)
	bg.color = Color("242630")
	root.add_child(bg)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	var cases := []
	for i in 2:
		var stage := Node2D.new()
		root.add_child(stage)
		var pet = Pet.new()
		stage.add_child(pet)
		check(pet.load_pet(config), pet.failure)
		if not pet.available: quit(1); return
		pet.fit(Vector2.ONE * 380)
		pet.tail.automatic = false
		var physics = Physics.new()
		root.add_child(physics)
		var area := Rect2(20 + 600 * i, 65, 560, 855)
		var facing := 1.0 if i == 0 else -1.0
		physics.set_geometry(Vector2.ONE * 380, area, pet.physics_anchor(facing))
		physics.body.collision_layer = 1 << i
		physics.body.collision_mask = 1 << i
		for wall in physics.walls:
			wall.collision_layer = 1 << i
			wall.collision_mask = 1 << i
		var at := Vector2(100 + 600 * i, area.end.y - 380 * (1.15 if i == 0 else 2.2))
		physics.reposition(at)
		physics.begin(at, at + physics.anchor, facing)
		var drag = Drag.new()
		drag.begin(at, facing)
		var behavior = Behavior.new()
		behavior.automatic_blinks = false
		var label := Label.new()
		label.position = Vector2(35 + 600 * i, 20)
		label.add_theme_font_size_override("font_size", 22)
		root.add_child(label)
		var line := ColorRect.new()
		line.position = Vector2(20 + i * 600, 920)
		line.size = Vector2(560, 2)
		line.color = Color("74839a")
		root.add_child(line)
		cases.append({"pet": pet, "stage": stage, "physics": physics, "drag": drag,
			"behavior": behavior, "landing": Landing.new(), "at": at, "facing": facing,
			"label": label, "impact_count": 0, "max_knee": 0.0, "dizzy_seen": false, "previous_drop": 0.0,
			"support_min": INF, "support_max": -INF, "support_left": INF, "support_right": -INF})
	var folder := "res://../../_work/tests/landing-b-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var clipped := 0
	var max_boot_error := 0.0
	for frame in 360:
		for i in 2:
			var c: Dictionary = cases[i]
			var pet = c.pet
			var physics = c.physics
			var landing = c.landing
			if frame == 30:
				physics.body.linear_velocity.x = -90.0
				if i == 1:
					physics.body.rotation = deg_to_rad(10.0)
					physics.body.angular_velocity = 0.8
					physics.body.linear_velocity.x = -90.0
				physics.release()
				c.drag.release()
			var result: Dictionary = physics.update(1.0 / 60, c.at, physics.size, physics.area, frame < 30)
			if result.move: c.at = result.position
			if not result.impact.is_empty():
				c.impact_count += 1
				landing.start(result.impact)
				check(landing.state == ("soft" if i == 0 else "hard"), "wrong rendered landing tier")
			var event: Dictionary = landing.update(1.0 / 60)
			if event.sit: pet.set_seated(true, event.sit_speed)
			c.drag.pointer_previous = c.at + physics.body.spring_gap
			c.drag.update(1.0 / 60, c.at, physics.size)
			var pose: Dictionary = c.behavior.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 380, false).duplicate()
			pose.merge(c.drag.pose())
			pose.merge(physics.pose())
			pose.merge(landing.pose())
			pose.facingScale = c.facing
			pose.motionOrigin = c.at
			if physics.active():
				pose.dragTilt = physics.body.rotation * c.facing
				pose.dragSwingSpeed = physics.body.angular_velocity * c.facing
			pet.apply_pose(pose, 1.0 / 60)
			if i == 1 and landing.state == "hard" and landing.age >= 0.35:
				check(pet.sitting.amount >= 0.95 and pet.sitting.blend == 1.0, "hard landing still lowering after 0.35s")
			c.stage.position = c.at
			# Stage travel changes canvas coordinates too; actual host windows
			# stay at canvas origin, but this side-by-side preview has two stages.
			pet.sitting.update_composite_coordinates()
			if i == 1 and landing.age >= 0.5 and landing.age <= 1.4:
				var support_y: float = (pet.sitting.sprite.global_transform * pet.sitting.sprite.texture.get_size()).y
				c.support_min = minf(c.support_min, support_y)
				c.support_max = maxf(c.support_max, support_y)
				var support_x: float = (pet.sitting.sprite.global_transform * pet.sitting.sprite.texture.get_size()).x
				c.support_left = minf(c.support_left, support_x)
				c.support_right = maxf(c.support_right, support_x)
			c.max_knee = maxf(c.max_knee, pet.landing_pose.knee_amount)
			c.dizzy_seen = c.dizzy_seen or pose.dizzyAlpha > 0.9
			var combined_drop: float = pet.sitting.DROP * smoothstep(0.1, 1.0, pet.sitting.amount) + pet.landing_pose.lowering.y
			if i == 1 and landing.age > 0.11 and landing.age < 0.4:
				check(combined_drop >= c.previous_drop - 1.5, "absorption lifted back up before sitting")
			c.previous_drop = combined_drop
			c.label.text = ("低处 · 屈膝缓冲" if i == 0 else "高处 · 坐下眩晕（镜像方向）") + "\n" + landing.state
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			for id in pet.meshes:
				var node: MeshInstance2D = pet.meshes[id]
				var points := Secondary.read_points(node)
				var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				for p in points:
					valid = valid and p.is_finite()
					if node.visible and node.self_modulate.a > 0.01 and not Rect2(-1, -1, 382, 382).has_point(pet.transform * pet.model.transform * p): clipped += 1
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n+1]
					var d := indices[n+2]
					var before: float = (raw[id][b]-raw[id][a]).cross(raw[id][d]-raw[id][a])
					var after := (points[b]-points[a]).cross(points[d]-points[a])
					valid = valid and (absf(before) < 0.01 or before * after > 0)
				check(valid, "mesh folded/nonfinite " + id)
			# Isolate the planted-foot deformation from the existing fall stretch.
			if i == 0 and pet.landing_pose.knee_amount > 0.2 and landing.age > 0.08:
				var body: Transform2D = pet.deformation._affine("ArtMesh24", raw.ArtMesh24)
				var inv := body.affine_inverse()
				for id in ["ArtMesh22", "ArtMesh23"]:
					var pts := Secondary.read_points(pet.meshes[id])
					for n in pts.size():
						if (inv * raw[id][n]).y >= 736:
							max_boot_error = maxf(max_boot_error, (pts[n] + pet.landing_pose.lowering).distance_to(raw[id][n]))
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0: root.get_texture().get_image().save_png(folder.path_join("frame_%04d.png" % (frame / 2)))
	check(clipped == 0, "clipped viewport vertices " + str(clipped))
	check(max_boot_error < 0.02, "planted sole moved " + str(max_boot_error))
	for i in 2:
		var c: Dictionary = cases[i]
		check(c.impact_count == 1 and c.max_knee > 0.45, "impact/knee missing or repeated")
		check(c.dizzy_seen == (i == 1) and c.pet.sitting.seated == (i == 1), "wrong final pose")
		check(not c.landing.active() and not c.pet.landing_pose.sprites[0].visible, "dizzy did not recover")
		if i == 1:
			check(c.support_max - c.support_min < 1.0, "seated lower body bounced with residual collision tilt")
			check(c.support_right - c.support_left < 1.0, "seated lower body slid sideways after contact")
			print("SEATED SUPPORT: horizontal range %.6f pixels" % (c.support_right - c.support_left))
			print("SEATED SUPPORT: vertical range %.6f pixels" % (c.support_max - c.support_min))
	print("LANDING RENDER: %d checks, %d failures; clipped %d; boot error %.6f" % [checks, failures, clipped, max_boot_error])
	quit(1 if failures else 0)
