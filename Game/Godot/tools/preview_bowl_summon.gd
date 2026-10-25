extends "res://tools/preview_bowl_hit.gd"
## The production arrival, rescue, impact, drag and expression controllers.
const Summon = preload("res://scripts/bowl_summon.gd")
const Drag = preload("res://scripts/drag_motion.gd")
func crown(scene: Dictionary) -> Rect2:
	var cap: PackedVector2Array = scene.pet.crown_cap()
	var rect := Rect2(cap[0]+scene.parent.position,Vector2.ZERO)
	for point in cap: rect = rect.expand(point+scene.parent.position)
	return rect
func summon_step(scene: Dictionary, time: float, rescue: bool) -> void:
	var dt := 1.0/30.0
	scene.clock = time
	if time>=0.5 and not scene.armed:
		scene.armed = true; scene.summon.request(); scene.summon.begin(crown(scene))
		scene.bowl.begin_arrival(crown(scene).get_center().x,scene.area)
		scene.bowl.hide() # Display the identical art in the captured viewport.
		records.append({"panel":int(rescue),"event":"summon","time":time,"x":scene.bowl.at.x})
	if rescue and time>=1.45 and not scene.grabbed:
		scene.grabbed = true; scene.summon.grabbed_cat()
		scene.drag.begin(scene.parent.position,scene.base.facingScale)
	if rescue and scene.grabbed and time<2.05:
		var progress := smoothstep(1.45,2.05,time)
		scene.parent.position = scene.origin+Vector2(progress*300,-28.0*sin(progress*PI))
		scene.drag.pointer_previous = scene.parent.position
	elif rescue and scene.drag.state=="held": scene.drag.release()
	scene.drag.update(dt,scene.parent.position,Vector2.ONE*pet_extent)
	if scene.armed:
		if scene.bowl.arrival.active(): scene.bowl._advance_arrival(dt)
		else: scene.bowl._advance_fall(dt,scene.area)
	scene.display.visible = scene.armed
	scene.display.position = scene.bowl.at-scene.bowl.margin+scene.bowl.sprite.position-scene.area.position
	scene.display.rotation = scene.bowl.sprite.rotation
	scene.display.scale = scene.bowl.sprite.scale
	scene.bowl.soup.set_shader_parameter("clock_time",time)
	scene.bowl.soup.set_shader_parameter("slosh",scene.bowl.slosh)
	var pot := Rect2(scene.bowl.at,Vector2(scene.bowl.rest_size))
	var gesture: Dictionary = scene.summon.update(dt,crown(scene),pot,not scene.bowl.arrival.active(),pot.end.y>=floor_y-2,
		scene.drag.active(),not scene.drag.active() and not scene.reaction.active() and not scene.landing.active())
	if gesture.say: scene.words.text = "出来吧，我的锅锅"
	if gesture.thanks:
		scene.behavior.command("satisfied"); scene.words.text = "谢谢喵"; scene.thanked = time
		records.append({"panel":int(rescue),"event":"thanks","time":time,"pot_x":scene.bowl.at.x})
	if scene.drag.state=="held": scene.words.text = "用户把猫咪拖开"
	if scene.hit_at>=0.0: scene.words.text = ""
	if scene.thanked>=0.0 and time>scene.thanked+2.4: scene.words.text = ""
	if scene.reaction.update(dt,true,scene.landing.active(),false):
		scene.landing.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED,"lateral_speed":0.0,"dizzy_seconds":scene.reaction.dizzy_seconds,"immediate_dizzy":scene.reaction.immediate_dizzy})
	var landed: Dictionary = scene.landing.update(dt)
	if landed.sit: scene.pet.set_seated(true,landed.sit_speed)
	var p: Dictionary = scene.behavior.update(dt,Vector2.ZERO,Vector2.ZERO,pet_extent,false).duplicate()
	p.facingScale = scene.base.facingScale; p.motionOrigin = scene.parent.position; p.motionReset = time==0.0
	p.merge(scene.drag.pose(),true); p.merge(scene.landing.pose(),true)
	p.bowlReach = gesture.weight; p.bowlCalling = gesture.calling; p.bowlTime = gesture.time
	p.bowlTilt = gesture.tilt; p.bowlSummoning = true
	p = scene.reaction.prepare(p); scene.pet.apply_pose(p,dt)
	scene.words.position = Vector2(scene.parent.position.x+35,scene.parent.position.y-60)
	if scene.hit_at>=0.0:
		scene.caption.text = "接触即眩晕 · 锅轻压回弹，再弹向旁边"
	elif scene.thanked>=0.0: scene.caption.text = "确认躲过 → 放手站稳 → 闭眼笑、自然睁眼"
	elif scene.grabbed: scene.caption.text = "落点固定，不追踪猫咪 · 等待确认躲过"
	elif scene.armed: scene.caption.text = "顶部露出 0.5 秒 → 停顿 0.6 秒 → 下落"
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	panel_width = 800.0; pet_extent = 420.0; origin_y = 540.0; floor_y = 960.0; origin_x = 80.0
	root.size = Vector2i(1600,1040); root.position = Vector2i(-1800,-1400); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = root.size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("26232f"); bg.size = Vector2(root.size); viewport.add_child(bg)
	label_at("猫的饭盆 · Q 弹碰撞与直接眩晕",Vector2(32,20),32)
	label_at("左：没有拖开，被锅砸中",Vector2(32,72),23)
	label_at("右：拖开获救，闭眼笑说谢谢",Vector2(832,72),23)
	var scenes := []
	for i in 2:
		var scene := create_scene(i,false,false)
		var clipping := Control.new(); clipping.position = scene.area.position; clipping.size = scene.area.size
		clipping.clip_contents = true; clipping.mouse_filter = Control.MOUSE_FILTER_IGNORE; viewport.add_child(clipping)
		scene.display.reparent(clipping)
		scene.display.position = Vector2(-2000,-2000)
		scene.summon = Summon.new(); scene.drag = Drag.new(); scene.behavior = Behavior.new()
		scene.behavior.automatic_blinks = false; scene.grabbed = false; scene.thanked = -1.0
		scene.words = label_at("",scene.origin-Vector2(0,60),25)
		scene.bowl.struck_pet.connect(func(_impact): scene.summon.finish())
		var line := Line2D.new(); line.points = PackedVector2Array([Vector2(i*800+10,floor_y),Vector2(i*800+790,floor_y)])
		line.width = 1; line.default_color = Color("50485e"); viewport.add_child(line)
		scenes.append(scene)
	for frame in 330:
		for i in 2: summon_step(scenes[i],frame/30.0,i==1)
		await process_frame; await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%frame))
	var file := FileAccess.open(out.path_join("events.json"),FileAccess.WRITE); file.store_string(JSON.stringify(records,"\t")); file.close()
	print("SUMMON PREVIEW: ",records)
	quit()
