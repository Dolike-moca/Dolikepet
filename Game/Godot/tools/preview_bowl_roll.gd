extends SceneTree
## Real post-game physics/art, two reproducible landings. No user files/scores.
const Pot = preload("res://scripts/bowl_window.gd")
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
	root.position = Vector2i(-2200,-2200); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = Vector2i(1800,800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("211d2b"); bg.size = Vector2(1800,800); viewport.add_child(bg)
	font.font_names = PackedStringArray(["Microsoft YaHei UI"])
	label("坩埚落地 · 自然惯性停止",Vector2(40,25),32)
	label("沿用落地后剩余惯性 · 持续减速，不补速度或强行补圈",Vector2(42,72),19)
	var arena := Rect2(40,125,1720,465)
	var border := ReferenceRect.new(); border.position = arena.position; border.size = arena.size
	border.editor_only = false; border.border_color = Color("665875"); viewport.add_child(border)
	var caption := label("",Vector2(42,640),25)
	var details := label("",Vector2(42,690),19)
	var pot = Pot.new(); root.add_child(pot); pot.fit_pet(420); pot.set_process(false)
	var sprite := Sprite2D.new(); sprite.texture = Pot.ART; sprite.centered = false; sprite.material = pot.soup
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; viewport.add_child(sprite)
	var pivot: Vector2 = Vector2(4,4)+Pot.USED.size*pot.art_scale*0.5
	var outline := PackedVector2Array()
	for point in pot.silhouette: outline.append(point-pivot)
	var index := 0; var reports := []
	for example in 2:
		var f = pot.juggle; f.next_special_override = 0
		f.start(Vector2(450 if example==0 else 1400,260),Vector2(pot.rest_size),outline,arena)
		f.state = "flight"; f.angle = 0.7 if example==0 else -1.1
		f.velocity = Vector2(570 if example==0 else 720,1450)
		f.angular_velocity = 5.0 if example==0 else -4.0
		var landed := -1.0; var stopped := -1.0
		for frame in 240:
			var now := frame/30.0
			for event in f.advance(1.0/30,{}):
				if event.type=="floor": landed = now
				if event.type=="rest": stopped = now
			var transform := Transform2D(f.angle,Vector2.ONE*pot.art_scale,0.0,Vector2.ZERO)
			transform.origin = f.center-transform.basis_xform(Pot.USED.position+Pot.USED.size*0.5)
			sprite.transform = transform
			pot.soup.set_shader_parameter("fullness",0.70); pot.soup.set_shader_parameter("clock_time",now)
			var phase: String = f.ground_roll.phase if landed>=0 else "flight"
			caption.text = ("常规落地" if example==0 else "靠近边缘落地")+"  ·  "+{"flight":"下落","hop":"轻弹","slide":"触地摩擦，平缓转入滚动","roll":"惯性滚动 → 持续减速","rock":"低速轻晃，逐渐停稳","idle":"底部向下，停稳"}.get(phase,phase)
			details.text = "滚动 %.1f 圈    落地后 %.1f 秒    边缘反弹 %d 次"%[f.ground_roll.travelled/TAU if landed>=0 else 0.0,maxf(0,now-landed) if landed>=0 else 0.0,f.ground_roll.wall_hits if landed>=0 else 0]
			await process_frame; await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%index)); index += 1
			if stopped>=0 and now-stopped>=1.1: break
		reports.append({"example":example,"landed":landed,"stopped":stopped,"turns":f.ground_roll.travelled/TAU,"walls":f.ground_roll.wall_hits})
	var record := {"frames":index,"fps":30,"examples":reports}
	var file := FileAccess.open(out.path_join("preview.json"),FileAccess.WRITE); file.store_string(JSON.stringify(record,"\t")); file.close()
	print("ROLL PREVIEW: "+JSON.stringify(record))
	quit(0 if reports.all(func(row): return row.stopped>row.landed) else 1)
