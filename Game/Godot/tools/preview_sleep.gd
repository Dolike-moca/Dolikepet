extends SceneTree
## Deterministic preview of production sleep/rig; no real user files or input.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Cycle = preload("res://scripts/sleep_cycle.gd")
const Drag = preload("res://scripts/drag_motion.gd")
const SettingsTheme = preload("res://scripts/settings_theme.gd")
const FPS := 30
const FRAMES := 1020
func _initialize() -> void: call_deferred("run")
func label(parent: Node, text: String, at: Vector2, size: int, color := Color("e0d8ed")) -> Label:
	var result := Label.new(); result.text = text; result.position = at
	result.add_theme_font_size_override("font_size",size); result.add_theme_color_override("font_color",color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(result); return result
func run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty() or not output.is_absolute_path(): printerr("Pass absolute --out="); quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(720,720); root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	var viewport := SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var background := ColorRect.new(); background.color = Color("25222e"); background.size = Vector2(720,720)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE; viewport.add_child(background)
	var ui := Control.new(); ui.theme = SettingsTheme.make(); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE; viewport.add_child(ui)
	label(ui,"猫猫作息 · 坐姿睡眠预览",Vector2(28,20),26)
	var subtitle := label(ui,"",Vector2(29,61),16,Color("aca2bc"))
	var status := label(ui,"",Vector2(29,652),21)
	label(ui,"坐下睡觉 · 轻呼吸 · 自然睁眼 · 不抱尾巴",Vector2(29,687),14,Color("a59bb3"))
	var holder := Node2D.new(); holder.position = Vector2(100,108); viewport.add_child(holder)
	var pet = Pet.new(); holder.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))): quit(1); return
	pet.fit(Vector2(520,520)); pet.tail.rng.seed = 20261031; pet.tail.held_rng.seed = 20261031; pet.tail.next_sway = 1.5
	var behavior = Behavior.new(); behavior.automatic_blinks = false
	var cycle = Cycle.new(); cycle.rng.seed = 20261031; cycle.enabled = false
	var drag = Drag.new()
	var metadata := {"fps":FPS,"frames":FRAMES,"segments":["日常入睡与自然醒","作息持续睡眠与点击叫醒","拖拽立即响应与松手睁眼"],"keyframes":[30,120,240,360,450,540,690,765,840,900,990]}
	for frame in FRAMES:
		var t := float(frame)/FPS
		var minute := 12*60 if frame<480 else 23*60+10
		var local := t-27.0
		if frame==30 or frame==480: cycle.request_sleep()
		if frame==419: cycle.asleep_seconds = cycle.nap_seconds
		if frame==750: cycle.interact()
		if frame==810:
			cycle.state = "asleep"; cycle.age = 0.0; cycle.phase = 6.0; cycle.asleep_seconds = 0.0
			pet.set_seated(true); pet.sitting.amount = 1.0; pet.sitting.velocity = 0.0
		if frame==870:
			cycle.interact(true); drag.begin(Vector2.ZERO); pet.set_seated(false)
		if frame==960: drag.release()
		var events: Dictionary = cycle.advance(1.0/FPS,{"minute":minute,"blocked":false,"settled":true})
		if events.sit: pet.set_seated(true,0.6)
		if events.finished: pet.set_seated(false)
		var p: Dictionary = behavior.update(1.0/FPS,Vector2.ZERO,Vector2.ZERO,520,false).duplicate()
		p.merge(cycle.pose(),true)
		var travel := Vector2.ZERO
		if frame>=870:
			var held := frame<960
			var strength := smoothstep(2.0,2.6,local) if held else 1.0-smoothstep(5.0,6.4,local)
			travel = Vector2(25.0*sin((local-2.0)*2.3),-40.0)*strength
			drag.pointer_previous = travel+Vector2(cos(local*2.3)*8.0,0)
			drag.update(1.0/FPS,travel,Vector2(520,520))
			p.merge(drag.pose(),true)
			p.dragTilt = sin((local-2.0)*2.3)*0.06*strength
			holder.position = Vector2(100,108)+travel
		p.motionOrigin = travel; p.motionReset = frame in [0,480,810]; p.facingScale = 1.0
		pet.apply_pose(p,1.0/FPS)
		if frame<480:
			subtitle.text = "日常小睡 · 正式随机睡 3～8 分钟，预览缩短等待"
			status.text = "困意渐起，慢慢坐下" if frame<180 else ("轻轻呼吸，安静睡着" if frame<420 else "睡一会儿后，自然睁眼起身")
		elif frame<810:
			subtitle.text = "作息时间 · 无操作保持睡眠，不会随机醒来"
			status.text = "到了睡觉时间，慢慢入睡" if frame<630 else ("持续睡眠（演示节选）" if frame<750 else "点击叫醒 · 缓慢睁眼，恢复活动")
		else:
			subtitle.text = "拖拽唤醒 · 随时能拎起，松开后接自然睁眼"
			status.text = "坐着熟睡" if frame<870 else ("立即响应拖拽" if frame<960 else "松开后自然恢复")
		await process_frame; await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image.save_png(output.path_join("frame-%04d.png"%frame))!=OK: quit(2); return
	var file := FileAccess.open(output.path_join("preview.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"\t")); file.close()
	print("SLEEP PREVIEW: ",FRAMES," frames at ",output); quit()
