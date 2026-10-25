extends SceneTree
## Uses the real pot physics, collision, reaction and rig; no user folder worker.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Bowl = preload("res://scripts/bowl_window.gd")
const Hit = preload("res://scripts/bowl_hit_reaction.gd")
const Landing = preload("res://scripts/landing_motion.gd")
const Jump = preload("res://scripts/bowl_jump.gd")
var out := ""
var viewport: SubViewport
var records: Array = []
var font := SystemFont.new()
var panel_width := 600.0
var pet_extent := 420.0
var origin_y := 550.0
var floor_y := 970.0
var origin_x := 90.0
var drop_heights := [65.0/420.0,360.0/420.0]
var mirror_second := true
func _initialize() -> void: call_deferred("run")
func label_at(text: String, at: Vector2, size: int) -> Label:
	var label := Label.new(); label.text = text; label.position = at
	label.add_theme_font_override("font",font); label.add_theme_font_size_override("font_size",size)
	viewport.add_child(label); return label
func create_scene(index: int, seated: bool, jumping: bool) -> Dictionary:
	var origin := Vector2(index*panel_width+origin_x,origin_y)
	var parent := Node2D.new(); parent.position = origin; viewport.add_child(parent)
	var pet = Pet.new(); parent.add_child(pet)
	pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json")))
	pet.fit(Vector2.ONE*pet_extent); pet.tail.rng.seed = 40; pet.tail.held_rng.seed = 41; pet.tail.next_sway = 1.5
	pet.sitting.seated = seated; pet.sitting.amount = 1.0 if seated else 0.0
	var b = Behavior.new(); b.automatic_blinks = false
	var base: Dictionary = b.update(0.0,Vector2.ZERO,Vector2.ZERO,pet_extent,false).duplicate()
	base.facingScale = -1.0 if mirror_second and index==1 else 1.0
	pet.apply_pose(base,1.0/30)
	var bowl = Bowl.new(); root.add_child(bowl); bowl.set_process(false); bowl.fit_pet(pet_extent)
	var display := Sprite2D.new(); display.texture = bowl.ART; display.centered = false
	display.z_index = 1000 # Dragged native pot is in front of the pet window.
	display.scale = Vector2.ONE*bowl.art_scale
	display.material = bowl.soup; viewport.add_child(display)
	bowl.soup.set_shader_parameter("fullness",0.60); bowl.soup.set_shader_parameter("ripple",1.0)
	var reaction = Hit.new(); var landing = Landing.new(); var jump = Jump.new()
	var scene := {"parent":parent,"pet":pet,"bowl":bowl,"display":display,"base":base,
		"reaction":reaction,"landing":landing,"jump":jump,"jumping":jumping,"origin":origin,
		"area":Rect2(index*panel_width,118,panel_width,floor_y-118),"armed":false,"hit_at":-1.0,"clock":0.0,"duration":0.0,
		"caption":label_at("准备放下饭盆",Vector2(index*panel_width+26,floor_y+15),20)}
	bowl.impact_target = func():
		var cap: PackedVector2Array = pet.crown_cap()
		for i in cap.size(): cap[i] += parent.position
		return {"cap":cap,"extent":pet_extent}
	bowl.struck_pet.connect(func(hit):
		var direct: bool = scene.has("summon") and scene.summon.state=="calling"
		var repeated: bool = landing.extend_dizziness(hit.dizzy_seconds)
		if not repeated: reaction.start("hard" if direct else hit.kind,hit.dizzy_seconds,direct)
		jump.stop_for_impact(); scene.hit_at = scene.clock; scene.duration = hit.dizzy_seconds
		records.append({"panel":index,"seated":seated,"jumping":jumping,"time":scene.clock,"kind":hit.kind,"height":hit.height,"dizzy_seconds":hit.dizzy_seconds,"distance":absf(bowl.rebound.endpoint.x-bowl.rebound.origin.x)})
		records[-1].repeated = repeated
	)
	var cap: PackedVector2Array = bowl.impact_target.call().cap
	var center: Vector2 = cap[3]
	var foot: Vector2 = bowl._feet()[1]
	bowl.at = Vector2(center.x-foot.x,center.y-foot.y-pet_extent*drop_heights[index])
	bowl.at.y = maxf(118.0,bowl.at.y)
	display.position = bowl.at+bowl.sprite.position
	return scene
func step(scene: Dictionary, time: float) -> void:
	var dt := 1.0/30
	scene.clock = time
	var jump_pose: Dictionary = scene.jump.update(dt,scene.parent.position,Vector2.ONE*pet_extent,
		scene.area,scene.jumping and time<0.85 and not scene.reaction.active(),false)
	if jump_pose.move: scene.parent.position = jump_pose.position
	if time>=0.8 and not scene.armed: scene.armed = true; scene.bowl.arm_drop()
	if scene.armed: scene.bowl._advance_fall(dt,scene.area)
	scene.display.position = scene.bowl.at-scene.bowl.margin+scene.bowl.sprite.position
	scene.display.rotation = scene.bowl.sprite.rotation
	scene.display.scale = scene.bowl.sprite.scale
	scene.bowl.soup.set_shader_parameter("clock_time",time)
	scene.bowl.soup.set_shader_parameter("slosh",scene.bowl.slosh)
	var grounded: bool = scene.parent.position.y>=scene.origin.y-2.0
	if scene.reaction.update(dt,grounded,scene.landing.active(),false):
		scene.jump.cancel()
		scene.landing.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED,"lateral_speed":0.0,"dizzy_seconds":scene.reaction.dizzy_seconds,"immediate_dizzy":scene.reaction.immediate_dizzy})
	var landing: Dictionary = scene.landing.update(dt)
	if landing.sit: scene.pet.set_seated(true,landing.sit_speed)
	var p: Dictionary = scene.base.duplicate()
	p.breath = sin(time*2.0)*0.5+0.5
	p.motionOrigin = scene.parent.position; p.motionReset = time==0.0
	p.merge(scene.landing.pose(),true)
	p.bowlReach = jump_pose.weight; p.bowlCalling = jump_pose.calling; p.bowlTime = jump_pose.time
	p.bowlTilt = jump_pose.tilt; p.landingKnee = maxf(p.get("landingKnee",0.0),jump_pose.knee)
	p = scene.reaction.prepare(p)
	scene.last_pose = p.duplicate()
	scene.pet.apply_pose(p,dt)
	if scene.hit_at>=0.0:
		scene.caption.text = ("轻砸：挤眼 → 缓冲 → 自然睁眼" if scene.reaction.kind=="light" else "眩晕 %.1f 秒 · 已持续 %.1f 秒"%[scene.duration,scene.reaction.age]) if scene.reaction.active() else "反应结束 · 饭盆已落向旁边"
	elif time>=0.8: scene.caption.text = "饭盆自由下落"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	root.size = Vector2i(1200,1020); root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = Vector2i(1200,1020)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("26232f"); bg.size = Vector2(1200,1020); viewport.add_child(bg)
	var heading := label_at("饭盆砸中 · B2 动作预览",Vector2(40,20),30)
	label_at("低处落下 · 拖拽同款轻反应",Vector2(45,68),23)
	label_at("高处落下 · 原有眩晕动画",Vector2(650,68),23)
	var line := Line2D.new(); line.points = PackedVector2Array([Vector2(600,120),Vector2(600,970)]); line.width = 2; line.default_color = Color("50485e"); viewport.add_child(line)
	for section in 2:
		heading.text = "饭盆砸中 · B2 动作预览"+(" · 站立" if section==0 else " · 坐姿 / 跳跃")
		var scenes := [create_scene(0,section==1,false),create_scene(1,false,section==1)]
		for frame in 180:
			for scene in scenes: step(scene,frame/30.0)
			await process_frame; await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%(section*180+frame)))
		for scene in scenes:
			scene.bowl.queue_free(); scene.parent.queue_free(); scene.display.queue_free(); scene.caption.queue_free()
		await process_frame
	var file := FileAccess.open(out.path_join("events.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t")); file.close()
	print("B2 preview: ",records)
	quit()
