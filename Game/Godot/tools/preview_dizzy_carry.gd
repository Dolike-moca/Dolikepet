extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Landing = preload("res://scripts/landing_motion.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const Carry = preload("res://scripts/dizzy_carry.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(520,520); root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	var viewport := SubViewport.new(); viewport.size = Vector2i(520,520)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new(); viewport.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))): quit(1); return
	pet.fit(Vector2(520,520)); pet.tail.rng.seed = 20261025; pet.tail.held_rng.seed = 20261026
	pet.tail.next_sway = 1.25
	var behavior = Behavior.new(); behavior.automatic_blinks = false
	var landing = Landing.new(); var drag = Drag.new(); var carry = Carry.new()
	landing.start({"height":1.0,"speed":5.0,"dizzy_seconds":7.5,"immediate_dizzy":true})
	pet.set_seated(true); pet.sitting.amount = 1.0
	for frame in 300:
		var t := frame/30.0; var held := (t>=1.0 and t<3.0) or (t>=5.0 and t<9.0)
		var airborne := held or (t>=3.0 and t<3.5)
		var travel := Vector2(sin((t-1.0)*3.4)*75.0,-65.0) if held else Vector2.ZERO
		if frame in [30,150]: drag.begin(travel); pet.set_seated(false)
		if frame in [90,270]: drag.release()
		landing.set_suspended(airborne)
		var event: Dictionary = landing.update(1.0/30)
		if event.sit: pet.set_seated(true,event.sit_speed)
		drag.pointer_previous = travel+Vector2(cos(t*3.4)*12,0)
		drag.update(1.0/30,travel,Vector2(520,520))
		var p: Dictionary = behavior.update(1.0/30,Vector2.ZERO,Vector2.ZERO,520,false).duplicate()
		p.merge(drag.pose(),true); p.merge(landing.pose(),true)
		p.dragTilt = sin((t-1.0)*3.4-0.4)*0.14 if held else 0.0
		p.motionOrigin = travel; p.motionReset = frame==0; p.facingScale = 1.0
		p = carry.prepare(p,1.0/30,airborne and landing.state=="hard",held,drag.velocity.x)
		pet.apply_pose(p,1.0/30)
		await process_frame; await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("%04d.png" % frame))
	print("DIZZY PREVIEW: 300 frames"); quit()
