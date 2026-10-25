extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Motion = preload("res://scripts/juggle_motion.gd")
const Pot = preload("res://scripts/bowl_window.gd")
const View = preload("res://scripts/catch_score_view.gd")
const Game = preload("res://scripts/juggle_challenge.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("JUGGLE RENDER: "+label)
func run() -> void:
	root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	var viewport := SubViewport.new(); viewport.size = Vector2i(420,420); viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var pet = Pet.new(); viewport.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))): quit(1); return
	pet.fit(Vector2.ONE*420); pet.tail.rng.seed = 41; pet.tail.held_rng.seed = 42
	var b = Behavior.new(); b.automatic_blinks = false
	var base: Dictionary = b.update(0,Vector2.ZERO,Vector2.ZERO,420,false).duplicate()
	var motion = Motion.new(); var order := {}; var near_lengths: Array = []; var far_lengths: Array = []
	var rig = pet.pickup_pose.hold_rig
	for id in pet.meshes: order[id] = pet.meshes[id].z_index
	for facing in [1.0,-1.0]:
		for frame in 120:
			var p := base.duplicate(); p.facingScale = facing; p.dragHeld = true; p.dragHang = 1.0; p.dragFace = 1.0; p.dragTime = frame/60.0
			p = motion.prepare(p,1.0/60,true,true,sin(frame/60.0*TAU)*3.0)
			if frame%30==0: motion.struck()
			pet.apply_pose(p,1.0/60)
			near_lengths.append(rig.near.transform.x.length()); far_lengths.append(rig.far.transform.x.length())
			if frame>12:
				check(pet.landing_pose.sprites[0].modulate.a>0.999,"dizzy face lost while held")
				check(not pet.drag_pose.sprites[0].visible,"squeezed eyes leaked")
				check(rig.near.z_index==order.ArtMesh19 and rig.far.z_index==order.ArtMesh26,"arm layer switched to hide overlap")
			for point in pet.crown_cap(): check(point.is_finite(),"nonfinite animated crown")
	check(float(near_lengths.max())/float(near_lengths.min())<1.01,"near arm stretched")
	check(float(far_lengths.max())/float(far_lengths.min())<1.01,"far arm stretched")
	var pot = Pot.new(); root.add_child(pot); pot.fit_pet(420); pot.set_process(false)
	pot.at = Vector2(500,250); pot.juggle.state = "spin"; pot.show()
	for frame in 36:
		pot._art_pose(frame*TAU/36)
		for point in pot.mouse_passthrough_polygon:
			check(Rect2(Vector2.ZERO,Vector2(pot.size)).grow(0.1).has_point(point),"rotated handle/foot clipped by native window")
		await process_frame; await RenderingServer.frame_post_draw
		var image: Image = pot.get_texture().get_image()
		var used := image.get_used_rect()
		check(used.position.x>0 and used.position.y>0 and used.end.x<image.get_width() and used.end.y<image.get_height(),"rendered rotation clipped")
	# Pixel regression: charging adds light outside the existing opaque art,
	# including its rotated handles, without recolouring soup, gold or metal.
	pot.soup.set_shader_parameter("fullness",0.7)
	pot.soup.set_shader_parameter("clock_time",1.5)
	pot.juggle.glow = 0.0; pot._art_pose(0.72)
	pot.clock = 1.5; pot.set_charge(0.0)
	await process_frame; await RenderingServer.frame_post_draw
	var unlit: Image = pot.get_texture().get_image()
	pot.juggle.glow = 1.0; pot._art_pose(0.72)
	pot.set_charge(1.0)
	await process_frame; await RenderingServer.frame_post_draw
	var lit: Image = pot.get_texture().get_image()
	var solid := 0; var halo_pixels := 0; var difference := 0.0
	for y in unlit.get_height():
		for x in unlit.get_width():
			var a := unlit.get_pixel(x,y); var c := lit.get_pixel(x,y)
			if a.a>0.98:
				solid += 1
				difference = maxf(difference,maxf(absf(a.r-c.r),maxf(absf(a.g-c.g),absf(a.b-c.b))))
			elif a.a<0.001 and c.a>0.04 and c.g>c.r and c.g>c.b: halo_pixels += 1
	check(solid>5000,"pot pixels missing")
	check(difference<=2.0/255.0,"charging recoloured original pot: %f"%difference)
	check(halo_pixels>100,"external green halo missing")
	var lit_used := lit.get_used_rect()
	check(lit_used.position.x>0 and lit_used.position.y>0 and lit_used.end.x<lit.get_width() and lit_used.end.y<lit.get_height(),"charging halo clipped")
	print("CHARGE HALO: %d original pixels, %d external pixels, max RGB difference %.8f"%[solid,halo_pixels,difference])
	pot.juggle.cancel(); pot.queue_free(); pet.queue_free(); viewport.queue_free(); await process_frame
	print("JUGGLE RENDER: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
