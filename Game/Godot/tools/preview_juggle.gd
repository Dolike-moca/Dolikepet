extends SceneTree
## Reproducible preview with an isolated scripted catcher; production physics,
## meshes, soup shader, score controller and reward drawing are used directly.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Pot = preload("res://scripts/bowl_window.gd")
const Motion = preload("res://scripts/juggle_motion.gd")
const Game = preload("res://scripts/juggle_challenge.gd")
const View = preload("res://scripts/catch_score_view.gd")
var viewport: SubViewport
var font := SystemFont.new()
func _initialize() -> void: call_deferred("run")
func label(words: String, at: Vector2, pixels: int) -> Label:
	var node := Label.new(); node.text = words; node.position = at
	node.add_theme_font_override("font",font); node.add_theme_font_size_override("font_size",pixels)
	viewport.add_child(node); return node
func run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	root.position = Vector2i(-1800,-1800); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = Vector2i(1200,800); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("211d2b"); bg.size = Vector2(1200,800); viewport.add_child(bg)
	font.font_names = PackedStringArray(["Microsoft YaHei UI"])
	label("猫猫颠锅 · C / 自然旋转与动量",Vector2(30,18),28)
	label("演示使用固定随机种子与自动接锅，展示正式运动与动作",Vector2(32,56),15)
	var arena := Rect2(22,105,820,640)
	var border := ReferenceRect.new(); border.position = arena.position; border.size = arena.size
	border.editor_only = false; border.border_color = Color("514260"); viewport.add_child(border)
	var carrier := Node2D.new(); viewport.add_child(carrier)
	var pet = Pet.new(); carrier.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))): quit(1); return
	pet.fit(Vector2.ONE*420); pet.tail.rng.seed = 42; pet.tail.held_rng.seed = 43
	var behavior = Behavior.new(); behavior.automatic_blinks = false
	var base: Dictionary = behavior.update(0,Vector2.ZERO,Vector2.ZERO,420,false).duplicate()
	carrier.position = Vector2(210,302); pet.apply_pose(base,1.0/30)
	var pot = Pot.new(); root.add_child(pot); pot.fit_pet(420); pot.set_process(false)
	var halo := Sprite2D.new(); halo.texture = Pot.ART; halo.centered = false; halo.material = pot.aura_material
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; viewport.add_child(halo)
	var image := Sprite2D.new(); image.texture = Pot.ART; image.centered = false; image.material = pot.soup
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; viewport.add_child(image)
	var pivot: Vector2 = Vector2(4,4)+Pot.USED.size*pot.art_scale*0.5
	var outline := PackedVector2Array()
	for point in pot.silhouette: outline.append(point-pivot)
	var f = pot.juggle; f.rng.seed = 82; f.next_special_override = 0
	var cap: PackedVector2Array = pet.crown_cap()
	for i in cap.size(): cap[i] += carrier.position
	var crown := Rect2(cap[0],Vector2.ZERO)
	for point in cap: crown = crown.expand(point)
	f.start(Vector2(crown.get_center().x,crown.position.y-pot.rest_size.y*0.5-2),Vector2(pot.rest_size),outline,arena)
	f.next_special_override = 1
	var game = Game.new(); game.hit(0,0,false)
	var motion = Motion.new(); motion.struck()
	var score = View.new(); score.position = Vector2(862,430); viewport.add_child(score)
	var status := label("",Vector2(868,145),20)
	label("偏心顶撞带动旋转\n猫头移动传递动量\n绿光蓄力 0.8 秒\n越玩越高、越快\n落地轻弹、滚动回正",Vector2(868,200),18)
	var note := label("",Vector2(32,759),18)
	var events: Array = []; var boosted_hits := 0; var ended := false
	for frame in 900:
		var now := frame/30.0; var dt := 1.0/30.0
		var before: Vector2 = carrier.position
		var goal_x := clampf(f.center.x-196.0,arena.position.x-30,arena.end.x-390) if boosted_hits==0 else 85.0
		carrier.position.x = lerpf(carrier.position.x,goal_x,0.70 if boosted_hits==0 else 0.12)
		carrier.position.y = 302.0+sin(now*2.1)*9.0
		var p := base.duplicate(); p.dragHeld = true; p.dragHang = 1.0; p.dragFace = 1.0
		p.dragTime = now; p.motionOrigin = carrier.position; p.facingScale = 1.0
		p = motion.prepare(p,dt,game.active(),true,(carrier.position.x-before.x)/420.0/dt)
		pet.apply_pose(p,dt)
		var rendered: PackedVector2Array = pet.crown_cap()
		for i in rendered.size(): rendered[i] += carrier.position
		var target := {"cap":rendered,"extent":420.0,"velocity":(carrier.position-before)/dt} if boosted_hits==0 else {}
		if f.animating():
			for event in f.advance(dt,target):
				event.time = now; events.append(event)
				if event.type=="head":
					game.hit(now,event.walls,event.boosted); motion.struck()
					if event.boosted: boosted_hits += 1; f.special = false; f.state = "flight"
				elif event.type=="floor": game.finish("锅落地 · 本轮结束",now); ended = true
		var pose := Transform2D(f.angle,f.shape*pot.art_scale,0.0,Vector2.ZERO)
		pose.origin = f.center-pose.basis_xform(Pot.USED.position+Pot.USED.size*0.5)
		image.transform = pose
		halo.transform = pose; halo.visible = f.glow>0.0
		pot.soup.set_shader_parameter("fullness",0.70); pot.soup.set_shader_parameter("clock_time",now)
		pot.clock = now; pot.set_charge(f.glow)
		score.update_score(game.snapshot(now),dt)
		status.text = {"rise":"额外升高","flight":"旋转 / 抛物线","spin":"原地旋转","charge":"绿光蓄力 0.8 秒","settle":"轻弹 / 滚动回正","idle":"落地结束"}.get(f.state,f.state)
		note.text = "晕眩布娃娃姿态 · 肩根与手臂长度保持不变" if not ended else "落地结束后 5 秒隐藏计分窗口"
		await process_frame; await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%frame))
		if ended and now-game.ended_at>=5.1: break
	var record := {"events":events,"boostedHits":boosted_hits,"total":game.total,"ended":ended,"frameCount":DirAccess.get_files_at(out).size()}
	var file := FileAccess.open(out.path_join("preview.json"),FileAccess.WRITE); file.store_string(JSON.stringify(record,"\t")); file.close()
	print("JUGGLE PREVIEW: "+JSON.stringify(record)); quit(0 if boosted_hits>0 and ended else 1)
