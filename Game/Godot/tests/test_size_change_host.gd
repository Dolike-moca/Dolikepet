extends SceneTree
var failures: Array[String] = []
var app
var resized_count:=0
func verify(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("run")
func advance(frames: int) -> void:
	for frame in frames:
		app._process(1.0/30.0)
		await process_frame
func settle() -> void:
	for frame in 200:
		if not app.size_change.pending(): return
		await advance(1)
	verify(false,"size animation completes within its bounded duration")
func run() -> void:
	app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path=ProjectSettings.globalize_path("res://../../_work/tests/size-change/settings-%d.cfg" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(app.settings_path.get_base_dir())
	root.add_child(app);app.set_process(false);app.set_process_input(false)
	await process_frame
	root.mouse_passthrough=true
	app.bowl_window.hide();app.bowl_enabled=false;app.bowl_summon.finish()
	app.roaming.configure("off");app.idle_sitting.enabled=false;app.behavior.command("normal")
	var area:=DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position=Vector2i(area.get_center().x-150,area.end.y-300)
	app.falling.reposition(Vector2(root.position))
	root.size_changed.connect(func(): resized_count+=1)
	var initial_center:float=root.position.x+root.size.x*0.5
	var original_capacity:int=app.satiety.capacity
	for tick in 20: app._zoom(24)
	verify(root.size.x==300 and app.size_change.target==375,"wheel burst queues only one enlargement")
	for tick in 20:
		app._advance_size_change(0.02,true)
		app._zoom(24)
	verify(app.size_change.target==375 and app.size_change.state=="waiting","busy waiting does not accumulate wheel enlargement")
	await advance(15)
	verify(app.size_change.state=="summon","fixture reaches mushroom animation")
	for tick in 20: app._zoom(24)
	verify(app.size_change.target==375,"eating does not accumulate wheel enlargement")
	await advance(123)
	verify(app.size_change.state=="grow","fixture reaches white-flash growth")
	for tick in 20: app._zoom(24)
	verify(app.size_change.target==375,"growing does not accumulate wheel enlargement")
	for frame in 63:
		app._zoom(24)
		await advance(1)
	verify(root.size.x==375 and not app.size_change.pending(),"burst finishes at exactly 125%")
	verify(resized_count<=2,"growth does not reallocate the native canvas every frame")
	verify(absf(root.position.x+root.size.x*0.5-initial_center)<=0.5,"first step preserves center to integer-window precision")
	await advance(45)
	verify(root.size.x==375 and not app.size_change.pending(),"ignored ticks cannot start a later automatic growth")
	initial_center=root.position.x+root.size.x*0.5
	for tick in 20: app._zoom(24)
	verify(app.size_change.target==450,"fresh scroll after completion advances one more preset")
	await settle()
	verify(root.size.x==450 and not app.size_change.pending(),"second burst finishes at 150%")
	verify(absf(root.position.x+root.size.x*0.5-initial_center)<=0.5,"second step preserves center to integer-window precision")
	for tick in 20: app._zoom(-24)
	resized_count=0
	verify(app.size_change.target==375,"downward burst queues only one shrink")
	for tick in 20:
		app._advance_size_change(0.02,true)
		app._zoom(-24)
	verify(app.size_change.target==375 and app.size_change.state=="waiting","busy waiting does not accumulate shrink")
	await advance(7)
	verify(app.size_change.state=="shrink","fixture reaches shrinking")
	verify(root.size.x==450 and app._pet_size().x<450,"shrinking keeps a larger transparent canvas")
	verify(app.pet.fitted_size==Vector2(app._pet_size()),"model and logical extent agree during shrinking")
	for tick in 20:
		app._zoom(-24);app._zoom(24)
	verify(app.size_change.target==375,"neither direction retargets a wheel animation")
	for frame in 60:
		app._zoom(-24)
		await advance(1)
	verify(root.size.x==375 and not app.size_change.pending(),"shrink stops after one preset without queued ticks")
	verify(resized_count<=1,"shrink trims the native canvas only at completion")
	await advance(12)
	for tick in 20: app._zoom(-24)
	await advance(30)
	verify(root.size.x==300 and not app.size_change.pending(),"fresh downward burst advances one more preset")
	initial_center=root.position.x+root.size.x*0.5
	app._request_size(600)
	await settle()
	verify(root.size==Vector2i(600,600) and not app.size_change.pending(),"host reaches 200%")
	verify(absf(root.position.x+root.size.x*0.5-initial_center)<=0.5,"incremental resizing preserves horizontal center")
	verify(root.position.y+root.size.y==area.end.y,"bottom anchor preserved")
	verify(app.satiety.capacity==original_capacity and app.satiety.used==0 and app.bowl_files.pending.is_empty(),"growth leaves food and fullness unchanged")
	verify(not app.size_flash.image.visible and not app.pet.pickup_pose.food.visible,"prop and flash clear at end")
	app._request_size(150)
	await advance(30)
	verify(root.size==Vector2i(150,150) and not app.size_change.pending(),"host reaches 50%")
	app._request_size(450)
	app.settings_window.show_settings(true,60,180)
	await advance(30)
	verify(root.size.x==150 and app.size_change.state=="waiting","independent settings window safely holds pending animation")
	app.settings_window.hide()
	root.position=Vector2i(area.end.x-root.size.x,area.end.y-root.size.y)
	app.falling.reposition(Vector2(root.position))
	await settle()
	verify(root.size.x==450 and area.encloses(Rect2i(root.position,root.size)),"growth at right/bottom screen edge stays on screen")
	app._request_size(375)
	await advance(9)
	var displayed:Vector2i=app._pet_size()
	var before_grab:=root.position
	verify(displayed.x<root.size.x,"interrupt fixture has a reserved canvas")
	app._capture_hit_area()
	verify(not app._pointer_hits_pet(Vector2(root.size-Vector2i(2,2))),"reserved transparent margin cannot grab the cat")
	app.dragging=true;app.drag_moved=true
	app.drag_pointer=root.position+Vector2i(app.pet.physics_anchor())
	app._begin_grab(false)
	verify(root.size==displayed and root.position==before_grab,"grabbing during shrink commits visible geometry without moving the cat")
	app._advance_size_change(0.02,true)
	verify(app.size_change.state=="waiting" and app.size_change.value==displayed.x,"interrupted resize resumes from visible size")
	app._finish_drag();app.falling.cancel();app.drag_motion.cancel()
	app._request_size(450)
	await settle()
	app._save_settings()
	var saved:=ConfigFile.new();saved.load(app.settings_path)
	verify(saved.get_value("window","size")==450,"completed target persists")
	app._request_size(525)
	app._advance_size_change(0.1,true)
	app._save_settings();saved.load(app.settings_path)
	verify(saved.get_value("window","size")==525 and root.size.x==450,"pending goal persists, intermediate size does not")
	app._load_settings()
	verify(root.size.x==525 and not app.size_change.pending(),"relaunch uses saved preset")
	app._menu_action(20)
	await advance(100)
	verify(root.size.x==300,"reset goes to 100%")
	app.queue_free();await process_frame
	for message in failures: printerr(message)
	print("Size-change host: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
