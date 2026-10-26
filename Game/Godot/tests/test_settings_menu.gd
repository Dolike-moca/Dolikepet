extends SceneTree
## Production menu/settings integration; no user files or preferences are used.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func verify(value: bool, message: String) -> void:
	if not value: failures.append(message)
func complete_size(app) -> void:
	for frame in 200:
		if not app.size_change.pending(): return
		app._advance_size_change(1.0/30.0,false)
		await process_frame
	verify(false,"size animation finishes within the bounded duration")
func run() -> void:
	var app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = ProjectSettings.globalize_path("res://../../_work/tests/settings-menu/settings-%d.cfg" % OS.get_process_id())
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
	var settings = app.settings_window
	verify(settings.size == Vector2i(680,540),"compact window size")
	verify(settings.pages.size()==4 and settings.navigation.size()==4,"four pages are present")
	var original_size: int = root.size.x
	var original_gaze: bool = app.gaze_enabled
	var original_topmost: bool = root.always_on_top
	settings.size_buttons[4].pressed.emit()
	settings.gaze.button_pressed = not original_gaze
	settings.topmost.button_pressed = not original_topmost
	verify(root.size.x==original_size and app.gaze_enabled==original_gaze and root.always_on_top==original_topmost,"common draft must not apply before save")
	verify(settings.size_buttons.size()==7 and settings.size_buttons[4].button_pressed and settings.size_buttons[4].text=="150%","seven size presets use 300 baseline")
	settings.navigation[2].pressed.emit()
	verify(settings.current_page==2 and settings.pages[2].visible and not settings.pages[0].visible,"navigation switches one page at a time")
	app.settings_window.digestion_hours.value = 12.0
	app.settings_window.mode = Window.MODE_MINIMIZED
	await process_frame
	app._menu_action(14)
	await process_frame
	verify(app.settings_window.mode==Window.MODE_WINDOWED and app.settings_window.digestion_hours.value==12.0,"reopening minimized settings lost draft")
	verify(settings.current_page==2 and settings.size_pixels==450,"reopen retains page and common draft")
	app.settings_window.cancel_button.pressed.emit()
	app._menu_action(14)
	await process_frame
	verify(app.settings_window.digestion_hours.value==app.satiety.digestion_hours,"cancel did not discard draft")
	verify(settings.size_pixels==original_size and settings.gaze.button_pressed==original_gaze and settings.topmost.button_pressed==original_topmost,"cancel restores common settings")
	settings.activity_buttons[0].pressed.emit()
	settings.automatic.button_pressed = true
	settings.minimum_minutes.value = 2
	settings.maximum_minutes.value = 1
	settings.navigation[0].pressed.emit()
	verify(settings.save_button.disabled and settings.footer_hint.text.contains("活动"),"invalid duration is explained even from a different page")
	settings.automatic.button_pressed = false
	verify(not settings.sit_options.visible and not settings.save_button.disabled,"disabled automatic sitting hides inactive duration controls")
	settings.maximum_minutes.value = 3
	settings.minimum_seconds.value = 0
	settings.maximum_seconds.value = 0
	settings.size_buttons[4].pressed.emit()
	settings.gaze.button_pressed = false
	settings.topmost.button_pressed = false
	settings.bowl_capacity.get_line_edit().text = "0.25"
	settings.stomach_capacity.get_line_edit().text = "0.5"
	settings.digestion_hours.get_line_edit().text = "12.5"
	for field in [settings.bowl_capacity, settings.stomach_capacity, settings.digestion_hours]:
		field.get_line_edit().text_changed.emit(field.get_line_edit().text)
	settings.auto_open_bowl.button_pressed = true
	# SpinBox updates its text at the end of the frame after programmatic values.
	await process_frame
	settings._save()
	await process_frame
	verify(app.size_change.target==450 and app.size_change.pending(),"common save queues growth animation")
	await complete_size(app)
	verify(root.size.x==450 and not app.gaze_enabled and not root.always_on_top and not app.bowl_window.always_on_top and not app.catch_score.always_on_top,"common save updates existing runtime controls")
	verify(app.bowl_capacity==268435456 and app.satiety.capacity==536870912 and app.satiety.digestion_hours==12.5 and app.satiety.auto_open,"typed numbers saved without changing focus, including sub-GB capacity")
	verify(app.roaming.mode=="free" and not app.idle_sitting.enabled and app.idle_sitting.minimum_seconds==120 and app.idle_sitting.maximum_seconds==180,"activity segments and durations saved")
	app._load_settings()
	verify(root.size.x==450 and not app.gaze_enabled and not root.always_on_top and app.satiety.digestion_hours==12.5,"settings persist")
	app._menu_action(14)
	await process_frame
	settings.size_reset.pressed.emit()
	verify(settings.size_pixels==300 and settings.size_buttons[2].button_pressed and root.size.x==450,"reset is a draft until saved")
	settings._save()
	await process_frame
	await complete_size(app)
	verify(root.size.x==300,"reset and save return to 100%")
	app._menu_action(14)
	await process_frame
	verify(app.bowl_capacity==268435456 and app.satiety.capacity==536870912 and app.satiety.digestion_hours==12.5,"saving common reset preserves feeding settings")
	settings.automatic.button_pressed = true
	settings.update_stomach_usage(5*1024,8*1024,true)
	verify(settings.fullness.value==62.5 and settings.fullness_label.text=="62.5%","settings fullness bar and percentage")
	verify(settings.deletion_notice.text.contains("永久删除") and settings.deletion_notice.visible,"permanent deletion notice not hidden in details")
	# Representative preview values, scoped to this unsaved/isolated draft only.
	settings.hide()
	settings.show_settings(true,60,180,"calm",true,1073741824,1073741824,6.0,false,671088640,true,
		{"size":300,"gaze":true,"topmost":true})
	for index in settings.pages.size():
		settings.navigation[index].pressed.emit()
		settings.navigation[index].grab_focus()
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		settings.get_texture().get_image().save_png(app.settings_path.get_base_dir().path_join("page-%d.png" % index))
		verify(settings.pages[index].get_h_scroll_bar().max_value<=settings.pages[index].size.x+1,"no horizontal page overflow")
		verify(settings.pages[index].get_v_scroll_bar().max_value<=settings.pages[index].size.y+1,"collapsed page fits without scrolling: "+str(index))
	settings.navigation[2].pressed.emit()
	settings.details[2].button_pressed = true
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	settings.get_texture().get_image().save_png(app.settings_path.get_base_dir().path_join("feeding-expanded.png"))
	verify(settings.details[2].get_parent().get_child(settings.details[2].get_index()+1).visible,"details expand")
	settings.details[2].button_pressed = false
	verify(not settings.details[2].get_parent().get_child(settings.details[2].get_index()+1).visible,"details collapse")
	settings.updater.state = "downloading"; settings.updater.progress = 0.5
	settings._update_version_status()
	verify(settings.update_progress.visible and settings.update_progress.value==50,"update progress retained")
	settings.updater.state = "download_error"; settings._update_version_status()
	verify(settings.download_button.visible and settings.download_button.text=="重试下载","update retry retained")
	settings.updater.state = "idle"; settings._update_version_status()
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
	verify(not app.settings_window.updater.automatic,"isolated fixture does not contact real update services")
	app.bubble.hide(); app.falling.cancel(); app.bowl_summon.finish()
	app._queue_update_notice("fixture-available","发现新版本喵")
	app.dragging = true; app._show_update_notice()
	verify(app.update_notices.size()==1 and not app.bubble.visible,"update notice waits while dragging")
	app.dragging = false; app._show_update_notice()
	verify(app.bubble.visible and app.bubble_label.text=="发现新版本喵" and app.update_notices.is_empty(),"queued notice uses pet text bubble")
	app._queue_update_notice("fixture-ready","新版本下载完成啦")
	app._show_update_notice()
	verify(app.update_notices.size()==1 and app.bubble_label.text=="发现新版本喵","completion waits for the availability notice")
	app.bubble.hide(); app._show_update_notice()
	verify(app.bubble_label.text=="新版本下载完成啦" and app.update_notices.is_empty(),"completion is displayed separately")
	verify(app.bubble.mouse_filter==Control.MOUSE_FILTER_IGNORE,"update speech cannot block dragging")
	app.queue_free()
	await process_frame
	for message in failures: printerr(message)
	print("Settings/menu integration: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
