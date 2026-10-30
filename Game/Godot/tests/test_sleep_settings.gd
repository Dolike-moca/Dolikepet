extends SceneTree
## Own settings Window only; no account, user configuration, food, or global input.
const Settings = preload("res://scripts/pet_settings.gd")
class FixturePanel extends "res://scripts/ai_settings_panel.gd":
	var reject := false
	func commit_draft() -> Error:
		return ERR_INVALID_DATA if reject else super.commit_draft()
var checks := 0
var failures: Array[String] = []
var emitted: Array[Dictionary] = []
var ui
var out := ""

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("SLEEP SETTINGS: fixture timeout"); quit(1))
	call_deferred("run")

func show_draft(sleep: Variant = {}) -> void:
	ui.show_settings(true,60.0,180.0,"calm",true,1073741824,1073741824,6.0,false,0,false,{"sleep":sleep})

func frames() -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): out = ProjectSettings.globalize_path("res://../../_work/tests/sleep-settings/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(out)
	ui = Settings.new()
	# Build the default panel's owned controls before disposing it; its eager
	# child field instances are attached by _ready(), not by its constructor.
	root.add_child(ui.ai_panel)
	ui.ai_panel.free()
	ui.ai_panel = FixturePanel.new()
	root.add_child(ui)
	ui.sleep_settings_saved.connect(func(value: Dictionary): emitted.append(value.duplicate(true)))
	show_draft()
	await frames()
	verify(ui._sleep_draft() == {"enabled":true,"start_minute":1380,"end_minute":480,"frequency":1},"default draft uses 23:00 to 08:00 and moderate frequency")
	verify(ui.sleep_start_hour.get_line_edit().text == "23" and ui.sleep_start_minute.get_line_edit().text == "00"
		and ui.sleep_end_hour.get_line_edit().text == "08" and ui.sleep_end_minute.get_line_edit().text == "00","clock displays HH:MM with padded minutes and hours")
	verify(ui.sleep_period_hint.text.contains("跨午夜") and ui.sleep_frequency_label.text == "适中","default schedule and frequency have readable summaries")
	verify(ui.navigation.size() == 5 and ui.size == Vector2i(680,540),"schedule does not add a page or enlarge the settings window")
	verify(ui._fields() == [ui.minimum_minutes,ui.minimum_seconds,ui.maximum_minutes,ui.maximum_seconds],"sleep fields do not alter sitting duration field semantics")
	for index in 3:
		ui.sleep_frequency.value = index
		verify(ui.sleep_frequency_label.text == ["少","适中","多"][index],"slider stop displays its matching frequency")
	verify(emitted.is_empty(),"scrubbing frequency must not save preferences")
	ui.sleep_start_hour.value = 22; ui.sleep_start_minute.value = 30
	ui.sleep_end_hour.value = 7; ui.sleep_end_minute.value = 45
	var before_minimize: Dictionary = ui._sleep_draft()
	ui.mode = Window.MODE_MINIMIZED
	await process_frame
	show_draft({"enabled":false})
	await frames()
	verify(ui.mode == Window.MODE_WINDOWED and ui._sleep_draft() == before_minimize and emitted.is_empty(),"restoring minimized settings preserves its unsaved sleep draft")
	ui.cancel_button.pressed.emit()
	show_draft()
	await frames()
	verify(ui._sleep_draft().start_minute == 1380 and ui._sleep_draft().end_minute == 480 and emitted.is_empty(),"cancel discards sleep edits without emitting a save")
	ui.sleep_enabled.button_pressed = false
	verify(not ui.sleep_start_hour.editable and not ui.sleep_frequency.editable and ui.sleep_period_hint.text.contains("手动睡觉"),"disabled automatic sleep disables only its schedule controls and explains manual sleep")
	verify(ui.automatic.button_pressed and ui.minimum_minutes.editable,"sleep toggle does not disable existing automatic sitting")
	ui.sleep_enabled.button_pressed = true
	verify(ui.sleep_end_minute.editable and ui.sleep_frequency.editable,"enabling automatic sleep restores its controls")
	ui._select_page(1)
	await frames()
	var page: ScrollContainer = ui.pages[1]
	verify(page.get_h_scroll_bar().max_value <= page.size.x+1,"clock and frequency controls fit without horizontal scrolling")
	verify(ui.sleep_end_minute.get_global_rect().end.x <= ui.size.x-18
		and ui.sleep_frequency_label.get_global_rect().end.x <= ui.size.x-18
		and ui.activity_buttons.back().get_global_rect().end.x <= ui.size.x-18,"schedule minimum widths do not stretch or clip the activity page")
	verify(page.get_v_scroll_bar().visible,"activity remains scrollable after adding the schedule")
	verify(ui.sleep_detail.get_parent().get_child(ui.sleep_detail.get_index()+1).text.contains("开始与结束时间相同表示全天"),"all-day schedule semantics are documented")
	ui.get_texture().get_image().save_png(out.path_join("activity-top.png"))
	page.ensure_control_visible(ui.sleep_frequency)
	await frames()
	ui.get_texture().get_image().save_png(out.path_join("sleep-controls.png"))
	verify(Rect2(Vector2.ZERO,Vector2(ui.size)).encloses(ui.save_button.get_global_rect())
		and Rect2(Vector2.ZERO,Vector2(ui.size)).encloses(ui.cancel_button.get_global_rect()),"save and cancel remain fixed and visible while activity scrolls")
	ui.sleep_detail.button_pressed = true
	await frames()
	verify(ui.sleep_detail.get_parent().get_child(ui.sleep_detail.get_index()+1).visible
		and page.get_h_scroll_bar().max_value <= page.size.x+1,"long rule text wraps inside the existing scroll area")
	ui.sleep_detail.button_pressed = false
	# Commit numbers typed into SpinBoxes even if the user never leaves the field.
	for pair in [[ui.sleep_start_hour,"21"],[ui.sleep_start_minute,"15"],[ui.sleep_end_hour,"6"],[ui.sleep_end_minute,"5"]]:
		pair[0].get_line_edit().text = pair[1]
		pair[0].get_line_edit().text_changed.emit(pair[1])
	ui.sleep_frequency.value = 2
	ui._save()
	verify(emitted.size() == 1 and emitted[0] == {"enabled":true,"start_minute":1275,"end_minute":365,"frequency":2},"save commits exact typed schedule and slider draft once")
	verify(not ui.visible,"successful save closes settings")
	show_draft({"enabled":false,"start_minute":1307,"end_minute":431,"frequency":0})
	await frames()
	ui._select_page(0)
	ui._save()
	verify(emitted.size() == 2 and emitted[1] == {"enabled":false,"start_minute":1307,"end_minute":431,"frequency":0},"saving an unvisited activity page preserves loaded minute precision and disabled values")
	show_draft({"enabled":true,"start_minute":0,"end_minute":0,"frequency":1})
	await frames()
	verify(ui.sleep_period_hint.text.contains("全天"),"equal start and end are presented as all-day sleep")
	ui.minimum_minutes.value = 0; ui.minimum_seconds.value = 0
	ui._save()
	verify(emitted.size() == 2 and ui.visible and ui.save_button.disabled,"invalid existing duration blocks sleep preferences too")
	ui.minimum_minutes.value = 1
	ui.ai_panel.reject = true
	ui._save()
	verify(emitted.size() == 2 and ui.visible and ui.current_page == 3 and ui.footer_hint.text.contains("AI"),"failed AI validation does not partially save sleep settings")
	ui.ai_panel.reject = false
	ui.cancel_button.pressed.emit()
	show_draft({"enabled":"bad","start_minute":NAN,"end_minute":INF,"frequency":-3})
	await frames()
	verify(ui._sleep_draft() == {"enabled":true,"start_minute":1380,"end_minute":480,"frequency":0},"malformed schedule draft falls back safely and bounds frequency")
	ui.hide(); show_draft({"start_minute":99999,"end_minute":-80,"frequency":99})
	await frames()
	verify(ui._sleep_draft().start_minute == 1439 and ui._sleep_draft().end_minute == 0 and ui._sleep_draft().frequency == 2,"numeric schedule fields clamp to clock and frequency bounds")
	verify(not ui.updater.automatic and not is_instance_valid(ui.ai_service),"settings fixture never starts update or AI services")
	ui.hide(); ui.queue_free()
	await process_frame
	for failure in failures: printerr("SLEEP SETTINGS: " + failure)
	print("Sleep settings: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
