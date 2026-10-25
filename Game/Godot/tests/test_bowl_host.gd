extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
const Food = preload("res://scripts/food_item.gd")
var app
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL HOST: "+words)
func tick(count: int) -> void:
	for i in count:
		app._process(1.0/60)
		await process_frame
func run() -> void:
	var cfg := ConfigFile.new()
	var settings_path := "res://../../_work/tests/bowl-host-settings.cfg"
	cfg.set_value("window","size",420)
	cfg.set_value("pet","auto_fall_enabled",false)
	cfg.set_value("pet","auto_sit_enabled",false)
	cfg.set_value("pet","roaming_mode","off")
	cfg.save(settings_path)
	app = Scene.instantiate(); app.settings_path = settings_path
	root.add_child(app); app.set_process(false); app.set_process_input(false)
	root.mouse_passthrough = true
	check(app.pet.available,app.pet.failure)
	if not app.pet.available: quit(1); return
	app.bowl_window.set_process(false)
	app.bowl_files.set_process(false)
	app.bowl_files.initialized = true; app.bowl_files.storage_ready = true
	app.bowl_window.show(); app.bowl_window.mouse_passthrough = true
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x+600,area.end.y-420)
	var real_source := ProjectSettings.globalize_path("res://../../_work/tests/bowl-host-food.txt")
	var file := FileAccess.open(real_source,FileAccess.WRITE); file.store_string("isolated host fixture"); file.close()
	var entry := {"path":real_source,"token":"host-fixture","icon":"","label":"test.txt"}
	app.bowl_files.entries = [entry]
	app.bowl_files.stable[entry.token] = true
	app.bowl_files.textures[entry.token] = Food.DEMO_TEXTURES[0]
	app.bowl_window.place(Vector2i(area.position.x+80,area.end.y-app.bowl_window.size.y))
	await tick(30)
	check(not app.pickup.active(),"far bowl was eaten")
	check(app.roaming.state=="idle","B3 must not approach a distant bowl")
	# Put the bowl into actual reach and let the same host settle, sit, and take.
	app.roaming.interrupt(); app.roaming.weight = 0.0
	app.bowl_window.place(Vector2i(root.position.x+15,area.end.y-app.bowl_window.size.y))
	await tick(220)
	check(app.pickup.active() and app.pickup.current!=null,"close bowl never started a meal")
	check(not app.pet.pickup_pose.bowl.visible,"old demo bowl overlapped real cauldron")
	check(app.pet.pickup_pose.hold_rig.enabled,"approved feeding rig missing")
	check(app.bowl_files.jobs.is_empty(),"file deletion queued before eating completed")
	if app.pickup.current != null:
		# A held icon finishes after the bowl is moved away; the next icon must wait.
		app.bowl_window.place(Vector2i(area.position.x+10,area.position.y+10))
		app.pickup.age = app.pickup.food_end+app.pickup.tail_time-0.01
		await tick(3)
		check(app.bowl_files.jobs.size()==1 and app.bowl_files.jobs[0].action=="swallow","completion did not request exactly one swallow")
		check(FileAccess.file_exists(real_source),"host directly deleted a fixture before worker validation")
	app.pickup.cancel(true); app.bowl_files.entries.clear(); app.bowl_files.jobs.clear()
	app.pet.sitting.seated = false; app.pet.sitting.amount = 0.0; app.pet.sitting.velocity = 0.0
	app.roaming.interrupt(); app.roaming.weight = 0.0
	root.position.y = area.end.y-420
	app.bowl_window.place(Vector2i(root.position.x+15,root.position.y+30))
	app.bowl_window.dragging = true
	await tick(65)
	check(app.bowl_jump.active(),"held high bowl did not trigger hop")
	check(root.position.y<area.end.y-420,"hop did not lift pet")
	check(not app.falling.active(),"ordinary gravity interrupted controlled hop")
	check(app.pet.bowl_reach.eyes[0].visible,"squeezed eyes missing")
	var saw_open := false; var saw_closed := false
	for i in 100:
		await tick(1)
		saw_open = saw_open or app.pet.bowl_reach.shout.visible
		saw_closed = saw_closed or not app.pet.bowl_reach.shout.visible
	check(saw_open and saw_closed,"shouting did not alternate open and fully closed mouth")
	check(not app.pet.bite_face.mouth.visible,"feeding mouth leaked into shouting")
	check(app.pet.bowl_reach.shout.texture.resource_path=="res://assets/bowl/shout_mouth.png","shouting mouth not packaged")
	check(app.pet.pickup_pose.hold_rig.far.z_index==app.pet.meshes.ArtMesh26.z_index,"far arm covered far cheek")
	app.bowl_window.dragging = false
	await tick(130)
	check(not app.bowl_jump.active() and root.position.y==area.end.y-420,"release did not land")
	check(not app.pet.bowl_reach.shout.visible and not app.pet.bowl_reach.eye_recovery.recovering,"face did not finish recovery")
	app.bowl_capacity = 5*app.BowlCapacity.MB; app._save_settings()
	var saved := ConfigFile.new(); saved.load(settings_path)
	check(saved.get_value("bowl","capacity_bytes")==5*app.BowlCapacity.MB,"capacity not persisted")
	app.bowl_files.pending.clear()
	app.bowl_files.stomach_bytes = app.satiety.capacity
	app._observe_stomach()
	check(app.satiety.resting,"full stomach did not persist rest")
	app.bowl_window.dragging = true
	app.bowl_window.place(Vector2i(root.position.x+15,root.position.y+30))
	await tick(180)
	check(not app.bowl_jump.active(),"full pet reached for bowl")
	check(app.bubble_label.text=="吃饱了" and not app.satiety.full_pending,"satisfied response absent")
	var reacted_until: float = app.behavior.reaction_until
	app._observe_stomach(); await tick(20)
	check(app.behavior.reaction_until==reacted_until,"full response repeated")
	saved.load(settings_path)
	check(saved.get_value("stomach","resting",false),"rest latch not saved")
	app.bowl_window.dragging = false
	app.bowl_files.stomach_bytes = app.satiety.capacity/2
	app._observe_stomach()
	check(app.satiety.resting,"exactly half resumed")
	app._set_bowl_visible(false); app.satiety.reminder_wait = 0.0
	await tick(2)
	check(not app.bowl_window.visible and app.bubble_label.text=="吃饱了","resting pet requested hidden bowl")
	app.bowl_files.stomach_bytes -= 1; app._observe_stomach()
	app.satiety.reminder_wait = 0.0; await tick(2)
	check(not app.satiety.resting and app.bubble_label.text.contains("打开饭盆"),"hungry request missing")
	app.satiety.auto_open = true; app.satiety.reminder_wait = 0.0
	await tick(2)
	check(app.bowl_window.visible,"auto open did not show ornament")
	app.settings_window.show_settings(false,60,120,"off",false,app.bowl_capacity,2*app.BowlCapacity.GB,3.5,true,app.satiety.used,false)
	await tick(2)
	app.settings_window._save()
	check(app.satiety.capacity==2*app.BowlCapacity.GB and app.satiety.digestion_hours==3.5 and app.satiety.auto_open,"settings did not apply")
	saved.load(settings_path)
	check(saved.get_value("stomach","digestion_hours")==3.5 and saved.get_value("stomach","auto_open"),"stomach settings not persisted")
	print("BOWL HOST: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

