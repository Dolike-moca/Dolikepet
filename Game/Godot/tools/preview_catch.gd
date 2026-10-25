extends SceneTree
## First three catches use native boundary contacts. The labelled second
## section fast-forwards the same score controller to compare visual tiers.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Physics = preload("res://scripts/desktop_physics.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const Challenge = preload("res://scripts/catch_challenge.gd")
const View = preload("res://scripts/catch_score_view.gd")
var viewport: SubViewport
var font := SystemFont.new()
var records: Array = []
func _initialize() -> void: call_deferred("run")
func label(words: String, at: Vector2, pixels: int, color := Color("eee5fa")) -> Label:
	var result := Label.new(); result.text = words; result.position = at
	result.add_theme_font_override("font",font); result.add_theme_font_size_override("font_size",pixels)
	result.add_theme_color_override("font_color",color); viewport.add_child(result); return result
func run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1200,800); root.position = Vector2i(-1800,-1800); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = Vector2i(1200,800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("211d2b"); bg.size = Vector2(1200,800); viewport.add_child(bg)
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	label("接猫挑战 · B 预览",Vector2(38,24),30)
	var caption := label("每次抛投独立计分 · 这次弹两次 +4，下次弹一次仍 +1",Vector2(40,72),20,Color("c3b0d6"))
	var field := ReferenceRect.new(); field.position = Vector2(30,133); field.size = Vector2(790,566)
	field.editor_only = false; field.border_color = Color("53435f"); field.border_width = 2; viewport.add_child(field)
	label("抛出  →  撞边弹回  →  接住",Vector2(64,723),21)
	var state_label := label("准备抛出",Vector2(64,756),17,Color("b29fc5"))
	label("右下角计分窗",Vector2(869,382),18,Color("bca7d4"))
	label("普通基础分 + 大号连击奖励",Vector2(859,412),15,Color("9f8eaf"))
	var score = View.new(); score.position = Vector2(850,446); viewport.add_child(score); score.hide()
	var pet_parent := Node2D.new(); viewport.add_child(pet_parent)
	var pet = Pet.new(); pet_parent.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))): quit(1); return
	pet.fit(Vector2.ONE*260); pet.tail.rng.seed = 42; pet.tail.held_rng.seed = 43
	var b = Behavior.new(); b.automatic_blinks = false
	var base: Dictionary = b.update(0.0,Vector2.ZERO,Vector2.ZERO,260,false).duplicate()
	var motion = Physics.new(); viewport.add_child(motion)
	motion.set_geometry(Vector2.ONE*260,Rect2(30,133,790,566),pet.physics_anchor())
	var at := Vector2(320,385); motion.reposition(at)
	motion.begin(at,at+motion.anchor,1.0)
	var drag = Drag.new(); drag.begin(at)
	var game = Challenge.new()
	var next_throw := 0.9
	var contact_at := -1.0
	var native_done := false
	var showcase_walls := 0
	for frame in 660:
		var now := frame/30.0; var dt := 1.0/30
		if frame<270:
			var step: Dictionary = motion.update(dt,at,Vector2.ONE*260,motion.area,motion.state=="held")
			if step.move: at = step.position
			game.advance(now,motion.body.wall_sequence,motion.body.floor_sequence)
			if not native_done and now>=next_throw and motion.state=="held":
				var speed := Vector2(7000,-3800) if game.streak==0 else (Vector2(2400,0) if game.streak==1 else Vector2(-2400,-850))
				motion.body.linear_velocity = speed
				game.released(now,motion.body.wall_sequence,motion.body.floor_sequence,speed.length(),260)
				motion.release(); drag.release(); contact_at = -1.0
				state_label.text = "已抛出 · 等待撞边弹回"
			var wanted := 2 if game.streak==0 else 1
			if motion.state=="falling" and game.bounce_count>=wanted and contact_at<0.0:
				contact_at = now; state_label.text = "撞边弹回 · 可以接住"
			if contact_at>=0.0 and now-contact_at>=(0.033 if game.streak==0 else 0.17) and motion.state=="falling":
				var success: bool = game.caught(now,motion.body.wall_sequence,motion.body.floor_sequence,motion.body.grounded,true)
				records.append({"type":"native_catch","time":now,"success":success,"walls":motion.body.wall_sequence,"total":game.total,"delta":game.delta,"base_points":game.base_points,"bonus":game.bonus,"scored_bounces":game.scored_bounces})
				motion.begin(at,at+motion.anchor,1.0); drag.begin(at)
				next_throw = now+0.95; contact_at = -1.0
				if game.streak==3: native_done = true
				state_label.text = "接住！这次弹 %d 次 · 基础 +%d · 本轮 %d 分"%[game.scored_bounces,game.base_points,game.total]
			if native_done and not game.active(): state_label.text = "接住后超过 3 秒未抛出 · 本轮归零，保留最高分"
		else:
			if frame==270:
				motion.cancel(); drag.cancel(); at = Vector2(280,390)
				pet.fit(Vector2.ONE*310)
				caption.text = "基础分与连击奖励分开显示 · 10 / 11 / 20 / 40 连击加速演示"
				game.finish("demo")
			if frame in [285,345,405,465]:
				var target := 10 if frame==285 else (11 if frame==345 else (20 if frame==405 else 40))
				for i in range(game.streak,target):
					var hits := 2 if i+1==10 else (3 if i+1==20 else 1)
					game.released(now,showcase_walls,0,700,310); showcase_walls += hits
					game.caught(now,showcase_walls,0,false,true)
				records.append({"type":"accelerated_style_demo","streak":game.streak,"total":game.total,"delta":game.delta,"base_points":game.base_points,"bonus":game.bonus,"scored_bounces":game.scored_bounces})
				state_label.text = "%d 连击 · 这次弹 %d 次 · 基础 +%d"%[game.streak,game.scored_bounces,game.base_points]
				if game.bonus>0: state_label.text += "   连击奖励 +%d"%game.bonus
				state_label.text += " · 本轮 %d 分"%game.total
			game.advance(now,showcase_walls,0)
			if frame>=555: state_label.text = "3 秒没有再次抛出 · 本轮归零，最高 %d 分保留"%game.best
		var pose := base.duplicate()
		if frame<270:
			drag.pointer_previous = at+motion.body.spring_gap
			drag.update(dt,at,Vector2.ONE*260)
			pose.merge(drag.pose(),true); pose.merge(motion.pose(),true)
			pose.dragTilt = motion.body.rotation; pose.dragSwingSpeed = motion.body.angular_velocity
		pose.motionOrigin = at; pose.motionReset = frame in [0,270]; pose.breath = sin(now*2.0)*0.5+0.5
		pet_parent.position = at; pet.apply_pose(pose,dt)
		var scoreboard: Dictionary = game.snapshot(now)
		score.visible = scoreboard.shown; score.update_score(scoreboard,dt)
		await process_frame; await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%frame))
	var file := FileAccess.open(out.path_join("events.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t")); file.close()
	print("CATCH PREVIEW: ",records)
	quit(0 if native_done else 1)
