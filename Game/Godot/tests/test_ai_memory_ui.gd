extends SceneTree
## Isolated UI fixtures: no saved preferences, account, network, or food directories.
const Memory = preload("res://scripts/ai_memory_window.gd")
const SettingsPanel = preload("res://scripts/ai_settings_panel.gd")
var checks := 0
var failures: Array[String] = []

class FakeService extends Node:
	signal memories_changed
	signal state_changed
	var settings := {"enabled":false,"memory_enabled":true,"auto_memory_enabled":true,"proactive":true,"proactive_daily_limit":4,"auth_method":"api_key","model":"gpt-6-luna"}
	var entries: Array = [
		{"id":"recent-1","text":"最近在准备考试","tier":"recent","kind":"event","created_at":1793400000,"last_seen":1793486400,"sources":[{"quote":"这周要准备考试。","at":1793486400}],"faded":false},
		{"id":"recent-2","text":"最近喜欢喝茶","tier":"recent","kind":"preference","created_at":1793400000,"last_seen":1793486400,"sources":[{"quote":"我最近喜欢喝茶。","at":1793486400}],"faded":true},
		{"id":"long-1","text":"喜欢薯条","tier":"long","kind":"preference","created_at":1793400000,"last_seen":1793486400,"sources":[{"quote":"我还是最喜欢薯条。","at":1793486400}]},
		{"id":"fixed-1","text":"请叫我小铃","tier":"fixed","created_at":1793400000,"last_seen":1793400000,"sources":[]},
	]
	var busy := false
	var status := "准备好了"
	var fail_save := false
	var changed_id := ""
	var commits := 0
	var reject_memory_route := false
	func memory_entries() -> Array: return entries.duplicate(true)
	func has_key() -> bool: return false
	func apply_settings(draft: Dictionary, _key: String = "", _erase: bool = false) -> Error:
		if reject_memory_route:
			status = "请先配置记忆 AI 使用的接入方式"
			state_changed.emit()
			return ERR_UNCONFIGURED
		settings = draft.duplicate(true)
		commits += 1
		state_changed.emit()
		return OK
	func test_connection() -> bool: return false
	func _find(id: String) -> int:
		for i in entries.size():
			if entries[i].id == id: return i
		return -1
	func _fail() -> bool:
		if not fail_save: return false
		status = "记忆保存失败"
		state_changed.emit()
		return true
	func add_memory(text: String) -> bool:
		if _fail(): return false
		entries.append({"id":"fixed-new","text":text,"tier":"fixed","sources":[]})
		status = "记忆已保存"
		memories_changed.emit()
		return true
	func edit_memory_id(id: String, text: String) -> bool:
		if _fail() or _find(id) < 0: return false
		changed_id = id
		entries[_find(id)].text = text
		status = "记忆已更新"
		memories_changed.emit()
		return true
	func pin_memory_id(id: String) -> bool:
		if _fail() or _find(id) < 0: return false
		changed_id = id
		entries[_find(id)].tier = "fixed"
		status = "记忆已固定"
		memories_changed.emit()
		return true
	func forget_memory_id(id: String) -> bool:
		if _fail() or _find(id) < 0: return false
		changed_id = id
		entries.remove_at(_find(id))
		status = "记忆已删除"
		memories_changed.emit()
		return true

func _initialize() -> void: call_deferred("run")
func verify(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description)

func run() -> void:
	var service := FakeService.new()
	root.add_child(service)
	var memory := Memory.new()
	memory.setup(service)
	root.add_child(memory)
	var panel := SettingsPanel.new()
	root.add_child(panel)
	panel.load_draft(service)
	await process_frame
	verify(memory.tabs.tab_count == 3 and memory.items.item_count == 2, "recent/long/fixed groups filter entries")
	verify(memory.items.get_item_text(1).contains("渐渐淡忘"), "fading entry is explained without fabricating loss")
	memory._select_item(0)
	verify(memory.source_label.text.contains("这周要准备考试") and memory.source_label.text.contains("2026-"), "selected memory shows dated user source")
	verify(not memory.source_label.bbcode_enabled and memory.source_label.selection_enabled, "source remains selectable plain text")
	service.entries[0].text = "正在准备本周考试"
	service.memories_changed.emit()
	verify(memory.editor.text == "正在准备本周考试", "background correction updates an unedited selection")
	memory.editor.text = "考试之后想休息一下"
	service.entries.push_front({"id":"new-first","text":"新的条目","tier":"recent","sources":[]})
	service.memories_changed.emit()
	verify(memory.selected_id == "recent-1" and memory.selected == 1 and memory.editor.text == "考试之后想休息一下", "background insertion preserves editor and stable selection")
	memory._save_memory()
	verify(service.changed_id == "recent-1" and service.entries[0].text == "新的条目", "save targets stable id after list reordered")
	memory._select_item(2)
	memory.editor.text = "尚未保存的喝茶偏好"
	memory.tabs.current_tab = 1
	verify(memory.items.item_count == 1 and memory.editor.text == "尚未保存的喝茶偏好", "changing groups preserves unfinished edit")
	memory._select_item(0)
	memory.tabs.current_tab = 0
	memory._select_item(2)
	verify(memory.editor.text == "尚未保存的喝茶偏好", "returning to edited item restores its draft")
	memory._pin_memory()
	verify(service.changed_id == "recent-2" and memory.tabs.current_tab == 2 and memory.selected_id == "recent-2", "pin moves same selected entry into fixed group")
	verify(memory.pin.disabled and memory.editor.text == "尚未保存的喝茶偏好", "pin keeps unsaved editor and prevents redundant pin")
	service.fail_save = true
	memory._delete_memory()
	verify(memory.selected_id == "recent-2" and memory.editor.text == "尚未保存的喝茶偏好" and memory.status_label.text.contains("失败"), "failed forget preserves selected draft and surfaces error")
	service.fail_save = false
	memory._delete_memory()
	verify(service.changed_id == "recent-2" and memory.selected_id.is_empty() and memory.editor.text.is_empty(), "successful forget clears only selected editor")
	memory._new_memory()
	memory.editor.text = "以后叫我大人"
	memory._save_memory()
	verify(service.entries.back().tier == "fixed" and memory.tabs.current_tab == 2, "manual additions remain fixed and are visible immediately")
	memory._select_item(memory.items.item_count - 1)
	memory.editor.text = "未保存的称呼"
	service.entries.remove_at(service.entries.size() - 1)
	service.memories_changed.emit()
	verify(memory.editor.text == "未保存的称呼" and memory.save.disabled and memory.remove.disabled, "entry removed in background retains draft and cannot edit a different row")
	verify(memory.status_label.text.contains("草稿"), "removed selected entry explains preserved draft")
	service.settings.memory_enabled = false
	service.state_changed.emit()
	verify(memory.privacy_label.text.contains("不会随对话发送") and memory.privacy_label.text.contains("不会自动整理"), "disabled memory accurately explains both uses")
	panel.load_draft(service)
	verify(panel.auto_memory_enabled.disabled and panel.auto_memory_enabled.button_pressed, "disabling memory disables automatic control without losing preference")
	verify(panel.memory_auth_method.selected == SettingsPanel.MEMORY_ROUTES.find("follow") and panel.memory_auth_method.disabled, "memory AI defaults to following chat and disables with memory")
	panel.memory_enabled.button_pressed = true
	verify(not panel.auto_memory_enabled.disabled, "restoring memory re-enables automatic control")
	verify(not panel.memory_auth_method.disabled, "restoring memory re-enables saved route selection")
	panel.memory_auth_method.select(SettingsPanel.MEMORY_ROUTES.find("api_key"))
	panel._refresh_memory()
	verify(panel.memory_route_hint.text.contains("OpenAI") and panel.memory_route_hint.tooltip_text.contains("不会自动切换"), "selected API memory route explains provider and no fallback")
	panel.auto_memory_enabled.button_pressed = false
	panel.daily_limit.value = 6
	panel.unlimited_daily.button_pressed = true
	verify(not panel.daily_limit.editable and panel.daily_limit.value == 6, "unlimited disables number while preserving finite draft")
	panel.commit_draft()
	verify(service.settings.proactive_daily_limit == 0 and not service.settings.auto_memory_enabled, "unlimited sentinel and automatic memory preference save together")
	verify(service.settings.memory_auth_method == "api_key", "memory route is saved independently from chat route")
	panel.memory_auth_method.select(SettingsPanel.MEMORY_ROUTES.find("chatgpt"))
	service.reject_memory_route = true
	verify(panel.commit_draft() == ERR_UNCONFIGURED and panel.memory_auth_method.selected == SettingsPanel.MEMORY_ROUTES.find("chatgpt") and service.settings.memory_auth_method == "api_key", "route validation failure preserves draft and previously saved route")
	verify(panel.status_label.text.contains("请先配置"), "route validation failure remains visible")
	service.reject_memory_route = false
	panel.commit_draft()
	panel.load_draft(service)
	verify(panel.memory_auth_method.selected == SettingsPanel.MEMORY_ROUTES.find("chatgpt") and panel.memory_route_hint.text.contains("ChatGPT"), "saved separate ChatGPT memory route reloads")
	# Preserve the earlier finite-limit draft for the unlimited toggle checks below.
	panel.daily_limit.value = 6
	panel.unlimited_daily.button_pressed = false
	verify(panel.daily_limit.editable and panel.daily_limit.value == 6, "switching back restores finite draft value")
	panel.commit_draft()
	verify(service.settings.proactive_daily_limit == 6, "finite limit persists after unlimited switch")
	var commits_before := service.commits
	panel.commit_draft()
	verify(service.commits == commits_before, "unchanged new settings do not interrupt service")
	service.settings.proactive_daily_limit = 0
	panel.load_draft(service)
	verify(panel.unlimited_daily.button_pressed and not panel.daily_limit.editable, "saved unlimited preference loads without forcing a finite limit")
	panel.proactive.button_pressed = false
	verify(panel.unlimited_daily.disabled and not panel.daily_limit.editable, "disabled proactive also disables limit choices")
	verify_frequency_draft(panel, service)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review="):
			var output := argument.trim_prefix("--review=")
			DirAccess.make_dir_recursive_absolute(output)
			service.settings.memory_enabled = true
			service.settings.auto_memory_enabled = true
			memory.selected_id = ""
			memory.tabs.current_tab = 0
			memory._refresh()
			memory._select_item(1)
			memory.open_panel()
			await screenshot(memory, output.path_join("memory-recent.png"))
			memory.tabs.current_tab = 1
			memory._select_item(0)
			await screenshot(memory, output.path_join("memory-long.png"))
			memory.tabs.current_tab = 2
			memory._select_item(0)
			await screenshot(memory, output.path_join("memory-fixed.png"))
			memory.size = memory.min_size
			await screenshot(memory, output.path_join("memory-minimum.png"))
			verify(memory.save.get_global_rect().end.y <= memory.size.y and memory.remove.get_global_rect().end.x <= memory.size.x, "minimum window keeps action controls inside bounds")
	memory.queue_free()
	panel.queue_free()
	service.queue_free()
	await process_frame
	for description in failures: printerr(description)
	print("AI memory UI: %d checks, %s" % [checks, "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func verify_frequency_draft(panel: Control, service: FakeService) -> void:
	service.settings.proactive = true
	service.settings.proactive_interval_minutes = 45
	service.settings.quiet_start = 19
	service.settings.quiet_end = 7
	service.settings.erase("quiet_enabled")
	panel.load_draft(service)
	verify(panel.interval is HSlider and panel.interval.tick_count == 5 and not panel.interval.scrollable, "frequency slider is discrete and scrolling the page cannot change it")
	verify(not panel._frequency_touched and panel.frequency_hint.text.contains("45") and panel.quiet_enabled.button_pressed, "legacy interval is retained and unequal hours migrate to enabled quiet time")
	panel.include_pet_state.button_pressed = not panel.include_pet_state.button_pressed
	panel.commit_draft()
	verify(service.settings.proactive_interval_minutes == 45 and service.settings.quiet_start == 19 and service.settings.quiet_end == 7, "unrelated save preserves exact legacy interval and quiet hours")
	panel.interval.value = 4
	verify(panel.frequency_label.text == "频繁" and service.settings.proactive_interval_minutes == 45, "slider updates draft label without changing live service")
	panel.load_draft(service)
	verify(not panel._frequency_touched and panel.interval.value == SettingsPanel.Frequency.nearest(45), "cancel/reopen restores the old interval without snapping its persisted value")
	panel.interval.value = 4
	panel.commit_draft()
	verify(service.settings.proactive_interval_minutes == 5, "highest frequency saves five-minute minimum")
	panel.load_draft(service)
	verify(panel.interval.value == 4 and panel.frequency_label.text == "频繁", "new frequency round-trips through settings")
	service.settings.proactive_interval_minutes = 45
	panel.load_draft(service)
	panel.interval.drag_started.emit()
	panel.commit_draft()
	verify(service.settings.proactive_interval_minutes == SettingsPanel.Frequency.minute_at(SettingsPanel.Frequency.nearest(45)), "explicitly dragging the nearest unchanged thumb applies that chosen stop")
	panel.quiet_enabled.button_pressed = false
	verify(not panel.quiet_start.editable and not panel.quiet_end.editable and panel.quiet_start.value == 19 and panel.quiet_end.value == 7, "quiet off disables fields without erasing selected hours")
	panel.commit_draft()
	verify(not service.settings.quiet_enabled and service.settings.quiet_start == 19 and service.settings.quiet_end == 7, "quiet-off state and original hours save separately")
	panel.quiet_enabled.button_pressed = true
	verify(panel.quiet_start.editable and panel.quiet_start.value == 19 and panel.quiet_end.value == 7, "quiet on restores the chosen nonempty range")
	panel.load_draft(service)
	verify(not panel.quiet_enabled.button_pressed, "cancel discards unsaved quiet toggle")
	service.settings.quiet_start = 0
	service.settings.quiet_end = 0
	service.settings.erase("quiet_enabled")
	panel.load_draft(service)
	verify(not panel.quiet_enabled.button_pressed and panel.quiet_start.value == 0, "legacy equal-hour disabled schedule stays unchanged on load")
	panel.quiet_enabled.button_pressed = true
	verify(panel.quiet_start.value == 22 and panel.quiet_end.value == 8 and service.settings.quiet_start == 0, "explicitly enabling an empty legacy range proposes a useful draft only")
	panel.commit_draft()
	verify(service.settings.quiet_enabled and service.settings.quiet_start == 22 and service.settings.quiet_end == 8, "new explicit quiet schedule persists")
	var before := service.commits
	panel.load_draft(service)
	panel.commit_draft()
	verify(service.commits == before, "unchanged slider and quiet drafts do not resave or interrupt an active reply")

func screenshot(window: Window, path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	window.get_texture().get_image().save_png(path)
