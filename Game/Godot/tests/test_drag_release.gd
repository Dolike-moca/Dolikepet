extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
var probe := ""
class NativeButtons extends RefCounted:
	# Deterministic capture handoff while held, without generating system input.
	var down := true
	var captured := 0
	func desktop_primary_pressed() -> bool: return down
	func desktop_capture_matches(handle: int) -> bool: return captured==handle
	func release_desktop_capture(handle: int) -> void:
		if captured==handle: captured = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("DRAG RELEASE: "+message)
func button(pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.window_id = root.get_window_id(); event.position = Vector2(210,210)
	return event
func probe_value(args: Array) -> String:
	var output: Array = []
	var code := OS.execute(probe,args,output,true)
	if code!=0: printerr(output)
	check(code==0,"native helper failed")
	return str(output[0]).strip_edges() if not output.is_empty() else ""
func stage_hold() -> void:
	app.dragging = true; app.drag_moved = true
	app.drag_pointer = root.position+Vector2i(210,210); app._begin_grab()
func run() -> void:
	var out := ProjectSettings.globalize_path("res://../../_work/tests/drag-release")
	var source := ProjectSettings.globalize_path("res://tests/PointerProbe.cs")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-root="): out = arg.trim_prefix("--fixture-root=")
		if arg.begins_with("--probe-source="): source = arg.trim_prefix("--probe-source=")
	DirAccess.make_dir_recursive_absolute(out)
	probe = out.path_join("PointerProbe.exe")
	var output: Array = []
	var compiler := OS.get_environment("WINDIR").path_join("Microsoft.NET/Framework64/v4.0.30319/csc.exe")
	if OS.execute(compiler,["/nologo","/out:"+probe.replace("/","\\"),source.replace("/","\\")],output,true)!=0:
		printerr(output); quit(1); return
	output.clear(); OS.execute(probe,["primary"],output)
	if str(output[0]).strip_edges()!="up":
		printerr("Physical mouse button is in use; retry without interfering with user input."); quit(1); return
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420); cfg.set_value("window","position",Vector2i(100,100))
	cfg.set_value("pet","roaming_mode","off"); cfg.set_value("pet","auto_fall_enabled",false)
	cfg.set_value("pet","auto_sit_enabled",false); cfg.set_value("bowl","visible",false)
	cfg.save(out+"/settings.cfg")
	app = Scene.instantiate(); app.settings_path = out+"/settings.cfg"; root.add_child(app)
	app.set_process(false); app.set_process_input(false); app.bowl_window.set_process(false)
	root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true; app.bubble.hide()
	# Lose the release event deliberately, without generating any system input.
	Input.parse_input_event(button(true)); Input.flush_buffered_events()
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"failed to stage stale engine button")
	stage_hold()
	app.falling.body.linear_velocity = Vector2(400,-250)
	app._process(1.0/60)
	check(not app.dragging,"lost release left cat attached to cursor")
	check(not app.falling.body.held and app.drag_motion.state!="held","spring or animation remained held")
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"stale input cache not repaired")
	if app.dragging: app._finish_drag()
	Input.parse_input_event(button(false)); Input.flush_buffered_events()
	check(app.pet.model.has_method("desktop_primary_pressed"),"physical-button bridge missing")
	if app.pet.model.has_method("desktop_primary_pressed"):
		check(not app.pet.model.call("desktop_primary_pressed"),"physical button disagrees with independent probe")
	# Dropped up at any frame rate preserves throw momentum and releases exactly once.
	for fps in [30,60,120]:
		for attempt in 5:
			Input.parse_input_event(button(true)); Input.flush_buffered_events()
			stage_hold()
			var body = app.falling.body
			body.linear_velocity = Vector2(250+attempt*50,-300)
			body.angular_velocity = 0.8; body.grounded = false
			var velocity: Vector2 = body.linear_velocity; var spin: float = body.angular_velocity
			app._update_drag_pointer(Vector2i(10000,-10000),true)
			check(app.dragging and body.held,"held input stopped outside silhouette")
			app._poll_drag_pointer(1.0/fps)
			check(not app.dragging and not app.drag_moved and not body.held,"release poll left held state")
			check(body.linear_velocity==velocity and body.angular_velocity==spin,"fallback changed throw momentum")
			check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"repeat release cache not cleared")
			var phase: String = app.catch_game.phase
			app._finish_drag(); app._input(button(false))
			check(app.catch_game.phase==phase and body.linear_velocity==velocity,"late duplicate release changed throw")
	# A popup must not swallow an already active drag's up event.
	stage_hold(); app.menu.show(); app._input(button(false))
	check(not app.dragging and not app.falling.body.held,"menu swallowed mouse up")
	app.menu.hide()
	# Genuine Win32 down, followed by no native up: engine cache AND capture reset.
	root.title = "Dolike drag release fixture"; root.mouse_passthrough = false
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,root.get_window_id())
	check(probe_value(["fixture-press",str(handle),str(OS.get_process_id())])=="posted","native press not posted")
	await process_frame; await process_frame
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"Win32 down did not reach input cache")
	check(probe_value(["capture",str(handle)])==str(handle),"Win32 down did not establish capture")
	check(app.pet.model.call("desktop_capture_matches",handle),"capture bridge missed native ownership")
	stage_hold(); app._poll_drag_pointer(1.0/60)
	check(not app.dragging and not app.falling.body.held,"native lost up left body held")
	check(probe_value(["capture",str(handle)])!=str(handle),"native capture survived release")
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"native lost up left cache held")
	check((DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT)==0,"native display-server button mask survived release")
	app.bubble.hide(); app._capture_hit_area()
	check(not app._apply_pointer_region(Vector2(-20,-20)),"after-release transparent area captured mouse")
	var pot = app.bowl_window
	pot.show(); pot.paused = true
	pot._input_window(button(true)); pot.dragging = true
	Input.parse_input_event(button(true)); Input.flush_buffered_events()
	pot._process(1.0/60)
	check(not pot.pressed and not pot.dragging,"lost release left cauldron attached to cursor")
	check(pot.drop_armed,"lost cauldron release did not arm normal fall")
	pot._release(); Input.parse_input_event(button(false)); Input.flush_buffered_events()
	var notices := [0]
	pot.moved.connect(func(): notices[0] += 1)
	for fps in [30,60,120]:
		for attempt in 8:
			pot._input_window(button(true))
			Input.parse_input_event(button(true)); Input.flush_buffered_events()
			pot._update_drag_pointer(pot.pointer_start+Vector2i(90,40),true)
			check(pot.dragging,"held cauldron stopped following")
			var before := int(notices[0])
			pot._process(1.0/fps)
			check(not pot.pressed and not pot.dragging and pot.drop_armed,"repeated lost cauldron up remains held")
			check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"cauldron did not repair input cache")
			var at: Vector2 = pot.at
			pot._update_drag_pointer(Vector2i(9000,-9000),true)
			check(pot.at==at,"released cauldron resumed following without a new down")
			pot._input_window(button(false)); pot._release()
			check(notices[0]==before+1,"duplicate cauldron up saved/armed twice")
	# Native release never steals the other widget's capture.
	pot.title = "Dolike drag release fixture cauldron"
	var pot_handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,pot.get_window_id())
	check(probe_value(["fixture-press",str(pot_handle),str(OS.get_process_id())])=="posted","cauldron native press not posted")
	await process_frame; await process_frame
	check(app.pet.model.call("desktop_capture_matches",pot_handle),"cauldron native capture not detected")
	app._release_drag_capture()
	check(probe_value(["capture",str(pot_handle)])==str(pot_handle),"cat cleanup stole cauldron capture")
	pot._process(1.0/60)
	check(not pot.pressed and not pot.dragging,"native lost cauldron up left hold")
	check(not app.pet.model.call("desktop_capture_matches",pot_handle),"native cauldron capture survived release")
	# A new held click on the other widget ends the old grab even when the
	# physical button is down again before the next frame can observe an up.
	var native := NativeButtons.new()
	app.drag_input.bridge = native; pot.drag_input.bridge = native
	native.captured = handle; app.drag_input.begin(root); stage_hold()
	var anchor: Vector2 = app.falling.body.attachment
	app._input(button(true))
	check(app.falling.body.attachment==anchor and app.drag_moved,"duplicate cat down reset attachment")
	app._poll_drag_pointer(1.0/60)
	check(app.dragging and app.falling.body.held,"valid captured cat drag cancelled")
	native.captured = pot_handle; pot._input_window(button(true)); pot.dragging = true
	app._poll_drag_pointer(1.0/60)
	check(not app.dragging and not app.falling.body.held,"capture handoff kept cat attached")
	check(pot.pressed and native.captured==pot_handle,"capture handoff cancelled fresh pot drag")
	pot._process(1.0/60); check(pot.dragging,"valid captured pot drag cancelled")
	native.captured = handle
	pot._process(1.0/60)
	check(not pot.pressed and not pot.dragging and native.captured==handle,"pot handoff stole other capture")
	# Window interruption and inconsistent flags must leave no hidden spring.
	native.captured = handle; app.drag_input.begin(root); stage_hold()
	app.falling.body.linear_velocity = Vector2(310,-220)
	root.focus_exited.emit()
	check(not app.dragging and not app.falling.body.held,"focus loss kept cat held")
	check(app.falling.body.linear_velocity==Vector2(310,-220),"focus loss erased cat momentum")
	stage_hold(); app.drag_moved = false; app._finish_drag()
	check(not app.falling.body.held and app.drag_motion.state!="held","cleared movement flag orphaned cat spring")
	stage_hold(); app.dragging = false; app.drag_moved = false; app._process(1.0/60)
	check(not app.falling.body.held and app.drag_motion.state!="held","orphaned cat spring not released")
	for interruption in ["focus","hidden","capture"]:
		pot.show(); pot_handle = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,pot.get_window_id())
		native.captured = pot_handle; pot._input_window(button(true)); pot.dragging = true
		if interruption=="focus": pot.focus_exited.emit()
		elif interruption=="hidden": pot.hide()
		else: native.captured = 0; pot._process(1.0/60)
		check(not pot.pressed and not pot.dragging,"cauldron hold survived "+interruption)
	pot.show(); pot_handle = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,pot.get_window_id())
	native.captured = pot_handle
	pot.opened.disconnect(app.bowl_files.open_folder)
	pot._input_window(button(true)); var double := button(true); double.double_click = true
	pot._input_window(double)
	check(not pot.pressed and native.captured==0,"double click left cauldron captured")
	app.drag_input.bridge = app.pet.model; pot.drag_input.bridge = app.pet.model
	Input.parse_input_event(button(false)); Input.flush_buffered_events()
	app.queue_free(); await process_frame
	print("DRAG RELEASE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
