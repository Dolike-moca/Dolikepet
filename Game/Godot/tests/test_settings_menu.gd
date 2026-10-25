extends SceneTree
## Production menu/settings integration; no user files or preferences are used.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func verify(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	var app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = ProjectSettings.globalize_path("res://../../_work/tests/settings-menu/settings.cfg")
	DirAccess.make_dir_recursive_absolute(app.settings_path.get_base_dir())
	# A non-default settings path disables the real folder worker.
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	await process_frame
	verify(app.pet.available,"model loads")
	for id in [0,1,2,3,4,5,6,12,13,15,16,18,21]:
		verify(app.menu.get_item_index(id)<0,"developer entry hidden: "+str(id))
	for id in [10,11,14,17,20,22]:
		verify(app.menu.get_item_index(id)>=0,"runtime entry present: "+str(id))
	app._menu_action(14)
	await process_frame
	verify(app.settings_window.visible,"settings opens from menu action")
	verify(not app.settings_window.transient and not app.settings_window.exclusive,"settings must be independent/nonmodal")
	app.settings_window.digestion_hours.value = 12.0
	app.settings_window.mode = Window.MODE_MINIMIZED
	await process_frame
	app._menu_action(14)
	await process_frame
	verify(app.settings_window.mode==Window.MODE_WINDOWED and app.settings_window.digestion_hours.value==12.0,"reopening minimized settings lost draft")
	app.settings_window.cancel_button.pressed.emit()
	app._menu_action(14)
	verify(app.settings_window.digestion_hours.value==app.satiety.digestion_hours,"cancel did not discard draft")
	app.satiety.used = 5*1024; app.satiety.capacity = 8*1024
	app._update_satiety_menu()
	verify(app.menu.get_item_text(app.menu.get_item_index(30))=="饱食度 62.5%" and app.satiety_bar.value==62.5,"menu fullness percentage/bar mismatch")
	verify(app.menu.is_item_disabled(app.menu.get_item_index(30)) and app.satiety_bar.mouse_filter==Control.MOUSE_FILTER_IGNORE,"fullness bar consumes menu clicks")
	app.settings_window.hide()
	app._open_menu(Vector2i(120,120))
	await process_frame; await RenderingServer.frame_post_draw
	app.menu.get_texture().get_image().save_png(app.settings_path.get_base_dir().path_join("menu.png"))
	verify(app.satiety_bar.size.x>100 and app.satiety_bar.size.y>0,"fullness bar has no drawable area")
	app.menu.hide()
	verify(app.settings_window.bowl_button.text=="打开饭盆文件夹","bowl label")
	verify(app.settings_window.open_bowl.is_connected(app.bowl_files.open_folder),"bowl action connected")
	verify(app.settings_window.open_stomach.is_connected(app.bowl_files.open_stomach),"stomach action connected")
	app.settings_window.hide()
	app.queue_free()
	await process_frame
	for message in failures: printerr(message)
	print("Settings/menu integration: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
