extends SceneTree
## Native pixel regression: visible iris pixels must stay inside the rendered
## eye whites, including intermediate expression frames and runtime deformation.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Chewing = preload("res://scripts/chewing_motion.gd")
const Landing = preload("res://scripts/landing_motion.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
var viewport: SubViewport
var pet
var base: Dictionary
var out := "res://../../_work/tests/expression-masks"
var worst_leak := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("EXPRESSION MASKS: " + message)

func draw_image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check_bounds(label: String) -> void:
	for group in pet.clipping_masks.groups:
		var mask: SubViewport = group.viewport
		var area := Rect2(Vector2.ZERO, Vector2(mask.size))
		for source in group.sources:
			for point in Secondary.read_points(source):
				if not area.grow(-1.0).has_point(mask.canvas_transform * point):
					check(false, label + " clips final mask geometry"); return
	check(true, label)

func iris_leak_pixels() -> int:
	var visible := {}
	for node in pet.model.get_children():
		if node is CanvasItem:
			visible[node] = node.visible
			node.hide()
	var saved_alpha := {}
	for id in ["ArtMesh12", "ArtMesh13"]:
		saved_alpha[id] = pet.meshes[id].self_modulate.a
		pet.meshes[id].self_modulate.a = 1.0
		pet.meshes[id].show()
	var whites := await draw_image()
	for id in ["ArtMesh12", "ArtMesh13"]:
		pet.meshes[id].hide()
		pet.meshes[id].self_modulate.a = saved_alpha[id]
	for id in ["ArtMesh10", "ArtMesh11"]: pet.meshes[id].visible = visible[pet.meshes[id]]
	var irises := await draw_image()
	var count := 0
	var used := irises.get_used_rect().intersection(Rect2i(2,2,596,596))
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if irises.get_pixel(x,y).a < 0.08: continue
			var covered := false
			# Two raster pixels tolerate antialiasing/filtering at the border,
			# but not the large repeated iris lobes from an undersized viewport.
			for dy in range(-2,3):
				for dx in range(-2,3):
					if whites.get_pixel(x+dx,y+dy).a > 0.02: covered = true; break
				if covered: break
			if not covered: count += 1
	for node in visible: node.visible = visible[node]
	return count

func sample(label: String, extras: Dictionary, settle: int = 1) -> void:
	var pose := base.duplicate()
	pose.merge(extras,true)
	for f in settle: pet.apply_pose(pose,1.0/60)
	check_bounds(label)
	var full := await draw_image()
	full.save_png(out.path_join(label + ".png"))
	var leaks := await iris_leak_pixels()
	worst_leak = maxi(worst_leak, leaks)
	check(leaks == 0, "%s has %d iris pixels outside eye whites" % [label,leaks])

func run() -> void:
	if DisplayServer.get_name() == "headless": printerr("Native renderer required"); quit(1); return
	root.size = Vector2i(600,600)
	root.position = Vector2i(24,24)
	root.mouse_passthrough = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(600,600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(600,600)
	root.add_child(preview)
	pet = Pet.new()
	viewport.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))), pet.failure)
	if not pet.available: quit(1); return
	pet.fit(Vector2(600,600))
	check(pet.clipping_masks.groups.size() == 2, "both eye clipping groups must be bound")
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	base = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	# Prove this pixel test catches the actual old renderer defect.
	var groups: Array = pet.clipping_masks.groups
	pet.clipping_masks.groups = []
	var broken := base.duplicate()
	broken.merge({"eyeNear":0.3,"eyeFar":0.3,"chewBend":0.4},true)
	pet.apply_pose(broken,1.0/60)
	(await draw_image()).save_png(out.path_join("regression-before.png"))
	var old_leak := await iris_leak_pixels()
	check(old_leak > 20, "test failed to detect pre-fix clipping defect")
	pet.clipping_masks.groups = groups
	await sample("regression-after", {"eyeNear":0.3,"eyeFar":0.3,"chewBend":0.4})
	print("PIXEL CONTROL: old stray iris pixels=", old_leak)
	for facing in [1.0,-1.0]:
		base.facingScale = facing
		var prefix := "right" if facing > 0 else "left"
		for command in ["closed", "normal", "closedHappy", "happy", "talk", "normal"]:
			behavior.command(command)
			for f in 18:
				var expression: Dictionary = behavior.update(1.0/60,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
				expression.facingScale = facing
				pet.apply_pose(expression,1.0/60)
				check_bounds(prefix+"-"+command)
				if f in [0,4,17]:
					await sample("%s-expression-%s-%02d" % [prefix,command,f], expression)
		for eye in [0.0,0.05,0.3,0.65,1.0]:
			await sample("%s-blink-%.2f" % [prefix,eye], {"eyeNear":eye,"eyeFar":eye})
		for tilt in [-18.0,18.0]:
			await sample("%s-recoil-%.0f" % [prefix,tilt], {"eyeNear":0.3,"eyeFar":0.3,"headZ":tilt,
				"gazeX":signf(tilt),"gazeY":-0.8,"landingUpperTilt":tilt/100.0,"landingUpperBounce":0.08})
		# Physical drag -> closed lids -> fall eyes, including a regrab.
		await sample(prefix+"-held", {"dragHeld":true,"dragFace":1.0,"dragHang":1.0,"dragTilt":0.2,"dragStretch":0.12},12)
		for f in 18:
			await sample("%s-release-%02d" % [prefix,f], {"dragHeld":false,"dragFace":maxf(0.0,1.0-(f+1)/6.0),
				"fallActive":true,"fallSpeed":2.6,"dragHang":maxf(0.0,1.0-(f+1)/12.0),"dragTilt":0.2})
		await sample(prefix+"-regrab", {"dragHeld":true,"dragFace":1.0,"dragHang":1.0,"fallActive":false},12)
		await sample(prefix+"-normal-after-drag", {},24)
		# Use the actual randomized swallow timeline, in standing AND sitting.
		var chewing = Chewing.new()
		chewing.rng.seed = 20261034
		chewing.start()
		var group: Dictionary = chewing.groups[1]
		for seated in [false,true]:
			pet.set_seated(seated)
			pet.sitting.amount = 1.0 if seated else 0.0
			pet.sitting.velocity = 0.0
			for fraction in [0.10,0.28,0.36,0.60,0.80,0.84,0.90,0.94,1.0]:
				chewing.age = group.chew_end + group.rest*fraction
				await sample("%s-swallow-%s-%.2f" % [prefix,str(seated),fraction], chewing.pose())
			for fraction in [0.10,0.30,0.50,0.75,0.90]:
				chewing.age = group.chew_end+group.rest+group.relief*fraction
				await sample("%s-relief-%s-%.2f" % [prefix,str(seated),fraction], chewing.pose())
		# Dizzy circle eyes -> closed lids -> reopening while the upper body recoils.
		var landing = Landing.new()
		landing.start({"height":1.4,"speed":5.0,"lateral_speed":1.2,"facing":facing})
		for f in 180:
			landing.update(1.0/60)
			var pose := base.duplicate()
			pose.merge(landing.pose(),true)
			pet.apply_pose(pose,1.0/60)
			check_bounds(prefix+"-dizzy")
			if f in [3,12,40,130,140,145,150,155,160,165,170,179]:
				var extra: Dictionary = landing.pose()
				# Retain a representative upper-body recoil at reopening, too.
				if f > 140: extra.landingUpperTilt = 0.08; extra.landingUpperBounce = 0.03
				await sample("%s-dizzy-%03d" % [prefix,f], extra)
		pet.set_seated(false)
		pet.sitting.amount = 0.0
		await sample(prefix+"-normal-after-dizzy", {},24)
	print("EXPRESSION MASKS: %d checks, %d failures; worst fixed leak %d pixels" % [checks,failures,worst_leak])
	quit(0 if failures == 0 else 1)
