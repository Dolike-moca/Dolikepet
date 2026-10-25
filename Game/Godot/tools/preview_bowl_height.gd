extends "res://tools/preview_bowl_hit.gd"
## Three real release heights, identical character size and desktop space.
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	panel_width = 540.0; pet_extent = 300.0; origin_y = 770.0; floor_y = 1070.0; origin_x = 20.0
	drop_heights = [0.16,1.0,1.8]; mirror_second = false
	root.size = Vector2i(1620,1120); root.position = Vector2i(-1800,-1400); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("26232f"); bg.size = Vector2(root.size); viewport.add_child(bg)
	label_at("坩埚弹落 · B2 连续渐变",Vector2(30,18),30)
	label_at("同一只猫、同一锅大小 · 落差越大，弹得越远，眩晕保持越久",Vector2(30,62),21)
	var names := ["低处：轻砸缓冲","中等高度：约 3.7 秒眩晕","更高处：约 6 秒眩晕"]
	var scenes := []
	for index in 3:
		label_at(names[index],Vector2(index*panel_width+28,112),22)
		if index>0:
			var line := Line2D.new(); line.points = PackedVector2Array([Vector2(index*panel_width,150),Vector2(index*panel_width,floor_y)]); line.width = 2; line.default_color = Color("50485e"); viewport.add_child(line)
		scenes.append(create_scene(index,false,false))
	for frame in 285:
		for scene in scenes: step(scene,frame/30.0)
		await process_frame; await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%frame))
	var file := FileAccess.open(out.path_join("events.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t")); file.close()
	print("Height B2 preview: ",records)
	for scene in scenes: scene.bowl.queue_free(); scene.parent.queue_free(); scene.display.queue_free(); scene.caption.queue_free()
	await process_frame; quit()
