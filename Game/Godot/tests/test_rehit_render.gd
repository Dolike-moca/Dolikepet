extends "res://tools/preview_bowl_hit.gd"
## Actual falling pot contacts an already dizzy cat, in both facing directions.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<12: printerr("REHIT: "+message)
func run() -> void:
	var preview := "--preview" in OS.get_cmdline_user_args()
	out = ProjectSettings.globalize_path("res://../../_work/tests/rehit-render")
	DirAccess.make_dir_recursive_absolute(out)
	panel_width = 500; origin_x = 40; origin_y = 320; floor_y = 740
	drop_heights = [0.15,0.15]
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	root.size = Vector2i(1000,800); root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("26232f"); bg.size = Vector2(root.size); viewport.add_child(bg)
	label_at("眩晕中再次受击 · 轻微低头与下沉",Vector2(32,20),30)
	label_at("保持眩晕表情与计时 · 身体短促下沉后回弹 · 裙摆与鞋底保持支撑",Vector2(32,66),19)
	label_at("正向",Vector2(220,112),22); label_at("镜像",Vector2(720,112),22)
	var scenes := [create_scene(0,true,false),create_scene(1,true,false)]
	var references: Array = []
	var max_dip := [0.0,0.0]
	for scene in scenes:
		scene.landing.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED,"dizzy_seconds":6.0,"immediate_dizzy":true})
		scene.landing.age = 2.0; scene.landing.recoil.reset()
		step(scene,0.0)
		# Compare against the same breathing pose without the new impact impulse.
		# A frozen first-frame transform would incorrectly reject ordinary breathing.
		var reference = Pet.new(); scene.parent.add_child(reference); reference.hide()
		reference.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json")))
		reference.fit(Vector2.ONE*pet_extent)
		reference.sitting.seated = true; reference.sitting.amount = 1.0
		references.append(reference)
	for frame in 165:
		for index in 2:
			var scene: Dictionary = scenes[index]
			# Re-arm distinct real drops after the previous pot has bounced away.
			if frame in [65,107]:
				var cap: PackedVector2Array = scene.bowl.impact_target.call().cap
				scene.bowl.place(Vector2i(cap[3]-scene.bowl._feet()[1]-Vector2(0,65)))
				scene.bowl.arm_drop()
			step(scene,float(frame)/30.0)
			var p: Dictionary = scene.landing.pose()
			max_dip[index] = maxf(max_dip[index],p.dizzyRehit)
			var neutral: Dictionary = scene.last_pose.duplicate()
			neutral.landingUpperBounce -= 0.12*p.dizzyRehit
			neutral.landingUpperTilt += deg_to_rad(1.0)*p.dizzyRehit
			neutral.dizzyRehit = 0.0
			references[index].apply_pose(neutral,1.0/30)
			check(scene.pet.sitting.sprite.global_transform.is_equal_approx(references[index].sitting.sprite.global_transform),"rehit lifted seated skirt or boots")
			check(p.dizzyAlpha>0.99 and p.dizzyRehit<=1.15,"rehit lost dizzy eyes or overcompressed")
			if p.dizzyRehit>0.5:
				check(scene.pet.secondary_pose.headY<0.0,"head nod not applied through dizzy pose")
				check(p.landingUpperBounce>0.05,"body did not sink")
			scene.caption.text = "眩晕剩余 %.1f 秒 · %s"%[scene.landing.dizzy_remaining(),"受击缓冲" if p.dizzyRehit>0.08 else "轻轻摇晃"]
		await process_frame; await RenderingServer.frame_post_draw
		if preview or frame in [20,35,38,46,80,120]:
			viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%frame))
	check(records.size()==6,"expected three actual contacts per facing")
	for record in records: check(record.repeated,"pot did not hit an already dizzy cat")
	for index in 2:
		check(max_dip[index]>0.9,"visible dip missing")
		check(scenes[index].landing.rehit.amount<0.001,"body failed to settle after the last hit")
	FileAccess.open(out+"/events.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	print("REHIT RENDER: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
