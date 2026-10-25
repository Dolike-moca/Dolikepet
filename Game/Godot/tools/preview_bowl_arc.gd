extends "res://tools/preview_bowl_hit.gd"
## Actual collision, native-pot motion and live rig, with flight trails for review.
func run() -> void:
	out = ProjectSettings.globalize_path("res://../../_work/drag-release/arc-preview")
	DirAccess.make_dir_recursive_absolute(out)
	panel_width = 900; origin_x = 240
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	root.size = Vector2i(1800,1020); root.position = Vector2i(-2000,-2000); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = root.size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var bg := ColorRect.new(); bg.color = Color("26232f"); bg.size = Vector2(root.size); viewport.add_child(bg)
	label_at("饭盆回弹 · 抛物线路线预览",Vector2(36,20),30)
	label_at("较低位置落下",Vector2(36,70),23)
	label_at("较高位置落下 · 回弹更高、更远",Vector2(936,70),23)
	var scenes := [create_scene(0,false,false),create_scene(1,false,false)]
	var trails: Array[Line2D] = []
	for scene in scenes:
		var trail := Line2D.new(); trail.width = 2.0; trail.default_color = Color(0.73,0.62,0.94,0.5)
		viewport.add_child(trail); viewport.move_child(trail,1); trails.append(trail)
	for frame in 180:
		for index in 2:
			var scene: Dictionary = scenes[index]
			step(scene,float(frame)/30)
			if scene.bowl.rebound.active() and scene.bowl.rebound.age>scene.bowl.rebound.pause and scene.bowl.rebound.age<scene.bowl.rebound.pause+scene.bowl.rebound.land_time:
				trails[index].add_point(scene.bowl.at+Vector2(scene.bowl.rest_size)*0.5)
		await process_frame; await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png"%frame))
	FileAccess.open(out+"/events.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	print("BALLISTIC PREVIEW: ",records)
	quit()
