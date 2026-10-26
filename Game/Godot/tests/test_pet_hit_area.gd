extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
var out := ""
var probe := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<15: printerr("HIT AREA: "+message)
func native_target(point: Vector2) -> String:
	var results: Array = []
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,root.get_window_id())
	var screen := root.position+Vector2i(point)
	var code := OS.execute(probe,[str(handle),str(screen.x),str(screen.y)],results)
	check(code==0,"native hit probe failed")
	return str(results[0]).strip_edges() if not results.is_empty() else ""
func draw(pose: Dictionary, extent: int, seated: bool) -> void:
	root.size = Vector2i.ONE*extent
	app.pet.fit(Vector2(root.size))
	app.pet.sitting.seated = seated
	app.pet.sitting.amount = 1.0 if seated else 0.0
	app.pet.sitting.velocity = 0.0
	app.pet.apply_pose(pose,1.0/60)
	await process_frame; await RenderingServer.frame_post_draw
	app._capture_hit_area()
func opaque_point() -> Vector2:
	var image: Image = app.hit_area.image
	for y in range(image.get_height()/3,image.get_height()*2/3,3):
		for x in range(image.get_width()/3,image.get_width()*2/3,3):
			if image.get_pixel(x,y).a>0.99: return Vector2(x,y)
	return Vector2(-1,-1)
func run() -> void:
	out = ProjectSettings.globalize_path("res://../../_work/tests/pet-hit-area")
	var source := ProjectSettings.globalize_path("res://tests/PointerProbe.cs")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): out = arg.trim_prefix("--fixture=")
		if arg.begins_with("--probe-source="): source = arg.trim_prefix("--probe-source=")
	DirAccess.make_dir_recursive_absolute(out)
	probe = out.path_join("PointerProbe.exe")
	var compile_output: Array = []
	var compiler := OS.get_environment("WINDIR").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	var compiled := OS.execute(compiler,["/nologo","/target:exe","/platform:x64","/out:"+probe.replace("/","\\"),source.replace("/","\\")],compile_output,true)
	if compiled!=0:
		printerr("Native probe compilation failed: ",compile_output)
		quit(1); return
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420); cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("pet","auto_fall_enabled",false); cfg.set_value("pet","auto_sit_enabled",false)
	cfg.set_value("bowl","visible",false); cfg.save(out+"/settings.cfg")
	app = Scene.instantiate(); app.settings_path = out+"/settings.cfg"
	root.add_child(app); app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false); app.bubble.hide()
	root.position = DisplayServer.screen_get_usable_rect(root.current_screen).position+Vector2i(20,40)
	check(app.pet.model.has_method("set_desktop_passthrough"),"missing native pixel-hit bridge")
	var base: Dictionary = app.behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,420,false).duplicate()
	var scenarios := [
		[150,false,{"facingScale":1.0}], [420,true,{"facingScale":1.0}],
		[600,false,{"facingScale":-1.0}], [420,false,{"facingScale":0.35,"walkWeight":1.0,"walkPhase":0.6}],
		[420,false,{"facingScale":-1.0,"dragHeld":true,"dragHang":1.0,"dragFace":1.0,"dragTilt":0.3}],
		[420,true,{"facingScale":1.0,"dizzyActive":true,"dizzyAlpha":1.0,"dizzyRehit":1.0,"landingUpperBounce":0.12}],
	]
	for index in scenarios.size():
		var row: Array = scenarios[index]
		var pose := base.duplicate(); pose.merge(row[2],true)
		await draw(pose,row[0],row[1])
		var frame: Image = app.hit_area.image
		var visible_count := 0
		var empty_count := 0
		for y in range(0,row[0],7):
			for x in range(0,row[0],7):
				var alpha := frame.get_pixel(x,y).a
				if alpha>0.99:
					visible_count += 1; check(app._pointer_hits_pet(Vector2(x,y)),"visible body rejected: "+str(index))
				elif alpha<0.01:
					empty_count += 1; check(not app._pointer_hits_pet(Vector2(x,y)),"transparent gap accepted: "+str(index))
		check(visible_count>50 and empty_count>50,"incomplete rendered scenario")
		var inside := opaque_point()
		check(app._apply_pointer_region(inside),"visible pixels did not enable input")
		await process_frame
		check(native_target(inside)=="hit","visible pixels failed OS hit test")
		check(not app._apply_pointer_region(Vector2(2,2)),"empty corner did not pass input")
		await process_frame
		check(native_target(Vector2(2,2))=="pass","transparent pixels blocked external desktop")
		check(not app._apply_pointer_region(Vector2(-20,20)),"outside client region accepted")
		# The Win32 style must preserve the original rendered colors in both modes.
		var desktop := DisplayServer.screen_get_image(root.current_screen)
		var origin := root.position-DisplayServer.screen_get_position(root.current_screen)
		var matched := 0; var sampled := 0
		for y in range(0,row[0],9):
			for x in range(0,row[0],9):
				var expected := frame.get_pixel(x,y)
				if expected.a<0.99: continue
				var actual := desktop.get_pixelv(origin+Vector2i(x,y))
				sampled += 1
				if Vector3(expected.r-actual.r,expected.g-actual.g,expected.b-actual.b).length()<0.12: matched += 1
		check(matched>sampled*0.92,"native passthrough changed visible pixels: %d/%d"%[matched,sampled])
		frame.save_png(out+"/pose-%d.png"%index)
		var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
		click.position = Vector2(2,2); app._input(click)
		check(not app.dragging,"blank press started dragging")
		var old_size := root.size
		click.button_index = MOUSE_BUTTON_WHEEL_UP; app._input(click)
		check(root.size==old_size,"blank wheel resized pet")
		click.button_index = MOUSE_BUTTON_RIGHT; app._input(click)
		check(not app.menu.visible,"blank right press opened menu")
		click.button_index = MOUSE_BUTTON_LEFT; click.position = inside; app._input(click)
		check(app.dragging,"opaque press failed to grab")
		check(app._apply_pointer_region(Vector2(-20,-20)),"captured drag lost input outside silhouette")
		click.pressed = false; click.position = Vector2(-20,-20); app._input(click)
		check(not app.dragging,"outside release left stuck dragging")
		app.bubble.hide()
	# Speech is visible UI but deliberately cannot grab the cat from far away.
	for extent in [150,600]:
		app.bubble.hide()
		await draw(base,extent,false)
		var clean: Image = app.hit_area.image
		app._say("喵～\n气泡区域不拖动猫咪\n但被遮住的猫咪仍然可以拖动",20.0)
		await process_frame; await RenderingServer.frame_post_draw
		app._capture_hit_area()
		var rect: Rect2 = app.bubble.get_global_rect()
		var head := Vector2(-1,-1); var empty := Vector2(-1,-1)
		var mismatches := 0
		for y in range(int(rect.position.y)+1,mini(extent,int(rect.end.y)),2):
			for x in range(int(rect.position.x)+1,mini(extent,int(rect.end.x)),2):
				var point := Vector2(x,y)
				var visible := clean.get_pixel(x,y).a>=0.08
				if app._pointer_hits_pet(point)!=visible: mismatches += 1
				if visible: head = point
				else: empty = point
		check(head.x>=0 and empty.x>=0,"speech overlap fixture missing head/gap")
		check(mismatches==0,"speech masked real cat pixels or added a drag handle: %d"%mismatches)
		check(app._apply_pointer_region(head),"speech overlap blocked native hit region")
		check(not app._apply_pointer_region(empty),"speech-only region blocked desktop")
		var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
		click.position = head; app._input(click)
		app._update_drag_pointer(app.drag_pointer+Vector2i(40,20),true)
		check(app.drag_moved and app.falling.body.held,"speech prevented drag from covered head")
		check(not app.bubble.visible,"drag failed to dismiss speech")
		click.pressed = false; app._input(click)
		check(not app.dragging and not app.falling.body.held,"speech drag remained held after release")
		# Exercise the actual tap -> greeting -> second press -> drag sequence,
		# rather than only calling _say directly. No global mouse injection.
		app.falling.cancel(); app.drag_motion.cancel(); app.bubble.hide()
		await draw(base,extent,false)
		click.pressed = true; app._input(click)
		check(app.dragging and not app.drag_moved,"stationary press did not arm click/drag")
		click.pressed = false; app._input(click)
		check(app.bubble.visible and app.bubble_label.text=="喵～","tap did not show the real greeting")
		await process_frame; await RenderingServer.frame_post_draw
		app._capture_hit_area()
		click.pressed = true; app._input(click)
		check(app.dragging,"greeting blocked the next press")
		app._update_drag_pointer(app.drag_pointer+Vector2i(40,20),true)
		check(app.falling.body.held and not app.bubble.visible,"greeting took priority over dragging")
		click.pressed = false; app._input(click)
		check(not app.dragging and not app.falling.body.held,"second grab remained attached")
		# The UI-free mask must follow poses while speech remains on screen.
		app._say("喵～\n动作变化时也能抓住猫咪",20.0)
		var changed := base.duplicate(); changed.facingScale = -1.0; changed.headZ = 12.0
		await draw(changed,extent,false)
		var speaking: Image = app.hit_area.image
		var displayed := root.get_texture().get_image()
		var speech_rect: Rect2 = app.bubble.get_global_rect()
		app.bubble.hide()
		await process_frame; await RenderingServer.frame_post_draw
		app._capture_hit_area()
		var mask_matches := true; var display_matches := true
		for y in extent:
			for x in extent:
				var actual: Color = app.hit_area.image.get_pixel(x,y)
				# Only alpha belongs to the hit contract. Clip-texture RGB can
				# settle a render pass later in the invisible shared-canvas view.
				mask_matches = mask_matches and speaking.get_pixel(x,y).a==actual.a
				if not speech_rect.has_point(Vector2(x,y)):
					display_matches = display_matches and displayed.get_pixel(x,y)==actual
		check(mask_matches,"speech mask became stale during a pose change")
		check(display_matches,"separate hit rendering changed the visible cat")
		check(app.hit_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"speech transition lost the completed UI-free frame")
	app.hit_area.size = Vector2.ONE
	check(not app._pointer_hits_pet(Vector2(200,200)),"stale mask accepted after resize")
	app.queue_free(); await process_frame
	print("PET HIT AREA: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
