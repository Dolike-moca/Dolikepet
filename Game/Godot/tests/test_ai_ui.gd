extends SceneTree
## UI-only fake service. No network, credentials, food folders, or pet preferences.
const Settings = preload("res://scripts/pet_settings.gd")
const Chat = preload("res://scripts/ai_chat_window.gd")
const Memory = preload("res://scripts/ai_memory_window.gd")
var failures: Array[String] = []
var checks := 0

class FakeService extends Node:
	signal delta(text: String)
	signal reply_completed(text: String, proactive: bool)
	signal failed(message: String)
	signal state_changed
	signal memories_changed
	var settings := {"enabled": false, "model": "gpt-6-luna", "auth_method":"api_key", "memory_enabled": true, "include_pet_state": true, "proactive": false, "proactive_rest":true,"proactive_games":true,"proactive_reconnect":true,"proactive_daily_limit":4,"proactive_interval_minutes": 60, "quiet_start": 22, "quiet_end": 8, "personality": "温柔简短"}
	var history: Array = []
	var memories: Array = []
	var busy := false
	var request_kind := ""
	var status := "尚未启用 AI 陪伴"
	var key_present := false
	var saves := 0
	var tests := 0
	var last_context := {}
	var fail_save := false
	var fail_delete := false
	func has_key() -> bool: return key_present
	func apply_settings(draft: Dictionary, new_key: String = "", erase_key: bool = false) -> Error:
		if fail_save:
			status = "测试保存失败"
			return ERR_CANT_CREATE
		settings = draft.duplicate(true)
		if erase_key: key_present = false
		if not new_key.is_empty(): key_present = true
		saves += 1
		status = "已保存"
		state_changed.emit()
		return OK
	func test_connection() -> bool:
		tests += 1
		status = "正在测试已保存配置"
		state_changed.emit()
		return true
	func send_message(text: String, context: Dictionary = {}) -> bool:
		if busy and request_kind != "proactive": return false
		history.append({"role": "user", "text": text, "at": 1})
		last_context = context
		busy = true
		request_kind = "chat"
		status = "猫咪正在想…"
		state_changed.emit()
		return true
	func cancel() -> void:
		busy = false
		request_kind = ""
		status = "已停止"
		state_changed.emit()
	func clear_history() -> void:
		history.clear()
		state_changed.emit()
	func add_memory(text: String) -> bool:
		memories.append(text)
		memories_changed.emit()
		return true
	func update_memory(index: int, text: String) -> bool:
		memories[index] = text
		memories_changed.emit()
		return true
	func remove_memory(index: int) -> void:
		if fail_delete:
			status = "记忆删除失败，请检查存储位置"
			state_changed.emit()
			return
		memories.remove_at(index)
		status = "记忆已删除"
		memories_changed.emit()

func _initialize() -> void: call_deferred("run")
func verify(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	var service := FakeService.new()
	root.add_child(service)
	var settings := Settings.new()
	settings.ai_service = service
	root.add_child(settings)
	await process_frame
	settings.show_settings(false, 60, 180)
	var panel = settings.ai_panel
	verify(settings.pages.size() == 5 and settings.navigation[3].text == "AI", "dedicated AI page")
	verify(not settings.transient and not settings.exclusive, "settings remain nonmodal")
	verify(not panel.enabled.button_pressed and not panel.proactive.button_pressed, "AI and proactive default off")
	verify(panel.interval is HSlider and panel.interval.tick_count == 5 and panel.frequency_label.text == "偶尔", "talk frequency is a five-stop slider with the saved default level")
	verify(panel.quiet_enabled.button_pressed and not panel.quiet_start.editable, "legacy quiet hours migrate to an explicit disabled-while-inactive toggle")
	verify(panel.key.secret and not panel.key.context_menu_enabled and panel.key.text.is_empty(), "secret key starts masked and empty")
	panel.enabled.button_pressed = true
	panel.key.text = "fake-test-value"
	panel.model.text = "unsaved-model"
	verify(service.saves == 0 and not service.settings.enabled and not service.key_present, "draft is not applied eagerly")
	settings.hide()
	verify(panel.key.text.is_empty(), "hiding settings clears credential draft from field")
	settings.show_settings(false, 60, 180)
	verify(panel.model.text == "gpt-6-luna" and not panel.enabled.button_pressed, "cancel discards AI draft")
	panel.enabled.button_pressed = true
	panel.key.text = "fake-test-value"
	settings._save()
	verify(service.saves == 1 and service.key_present and service.settings.enabled and not settings.visible, "save commits AI preferences and key")
	verify(service.settings.proactive_interval_minutes == 60 and service.settings.quiet_start == 22 and service.settings.quiet_end == 8, "saving collapsed advanced panel preserves loaded timing")
	settings.show_settings(false, 60, 180)
	verify(panel.key.text.is_empty() and panel.key.placeholder_text.contains("已安全保存"), "saved key is never displayed")
	panel.commit_draft()
	verify(service.saves == 1, "unchanged AI draft does not resave or interrupt an active request")
	panel.model.text = "unsaved-model"
	panel.connection.pressed.emit()
	verify(service.tests == 1 and service.settings.model == "gpt-6-luna", "connection test uses saved configuration only")
	panel.remove_key.pressed.emit()
	verify(service.key_present and panel.erase_pending, "delete key is a reversible draft")
	settings.hide()
	settings.show_settings(false, 60, 180)
	verify(service.key_present and not panel.erase_pending, "cancel key deletion")
	service.fail_save = true
	panel.model.text = "change-for-failure"
	settings._save()
	verify(settings.visible and settings.current_page == 3 and settings.footer_hint.text.contains("AI"), "failed AI save keeps settings open")
	service.fail_save = false
	panel.enabled.button_pressed = false
	panel.remove_key.pressed.emit()
	settings._save()
	verify(not service.key_present and not service.settings.enabled, "save removes key and can disable AI")
	var chat := Chat.new()
	chat.setup(service)
	chat.context_provider = func(): return {"fullness_percent": 50}
	root.add_child(chat)
	await process_frame
	verify(not chat.transient and not chat.exclusive and not chat.transcript.bbcode_enabled, "chat window is nonmodal and plain text")
	chat.input.text = "你好 [url=bad]字面文字[/url]"
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	chat._input_key(enter)
	verify(service.history.is_empty(), "plain Enter does not accidentally submit an IME candidate")
	enter.ctrl_pressed = true
	chat._input_key(enter)
	verify(service.busy and service.history.size() == 1 and chat.input.text.is_empty(), "send starts one request and clears input")
	verify(service.last_context.get("fullness_percent") == 50, "chat supplies approved pet context")
	service.delta.emit("你好喵 [b]字面文字[/b]")
	verify(chat.transcript.text.contains("[b]字面文字[/b]") and chat.streamed_text.contains("你好喵"), "streaming content stays literal")
	chat.input.text = "第二次"
	chat._send_message()
	verify(service.history.size() == 1 and chat.input.text == "第二次", "busy chat cannot queue duplicate request")
	service.history.append({"role": "assistant", "text": "你好喵 [b]字面文字[/b]", "at": 2})
	service.busy = false
	service.reply_completed.emit("你好喵 [b]字面文字[/b]", false)
	service.state_changed.emit()
	verify(chat.streamed_text.is_empty() and chat.transcript.text.count("你好喵") == 1, "completed reply does not duplicate streamed content")
	chat._send_message()
	service.delta.emit("没有完成")
	service.cancel()
	verify(chat.streamed_text.is_empty() and not chat.transcript.text.contains("没有完成"), "cancel removes transient partial reply")
	chat._clear_history()
	verify(service.history.is_empty(), "clear chat history")
	service.busy = true
	service.request_kind = "proactive"
	chat.input.text = "我想先说一句"
	chat._send_message()
	verify(service.history.size() == 1 and service.request_kind == "chat", "manual chat can interrupt a proactive greeting")
	service.cancel()
	chat._clear_history()
	var memory := Memory.new()
	memory.setup(service)
	root.add_child(memory)
	await process_frame
	verify(not memory.transient and not memory.exclusive, "memory window nonmodal")
	memory.editor.text = "我喜欢猫"
	memory._save_memory()
	verify(service.memories == ["我喜欢猫"] and memory.items.item_count == 1, "explicit memory add")
	memory._select_item(0)
	memory.editor.text = "我喜欢紫色"
	memory._save_memory()
	verify(service.memories == ["我喜欢紫色"], "memory edit")
	memory._select_item(0)
	service.fail_delete = true
	memory._delete_memory()
	verify(service.memories == ["我喜欢紫色"] and memory.selected == 0 and memory.editor.text == "我喜欢紫色" and memory.status_label.text.contains("失败"), "failed memory delete preserves selection and editor and reports failure")
	service.fail_delete = false
	memory._delete_memory()
	verify(service.memories.is_empty() and memory.items.item_count == 0, "memory delete")
	service.settings.memory_enabled = false
	service.state_changed.emit()
	verify(memory.privacy_label.text.contains("不会随对话发送"), "disabled memory clearly explained")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review="):
			var output := argument.trim_prefix("--review=")
			DirAccess.make_dir_recursive_absolute(output)
			service.settings.model = "gpt-6-luna"
			settings.show_settings(false, 60, 180)
			settings._select_page(3)
			await screenshot(settings, output.path_join("settings-ai.png"))
			verify(settings.pages[3].get_h_scroll_bar().max_value <= settings.pages[3].size.x + 1, "AI page has no horizontal overflow")
			verify(settings.pages[3].get_v_scroll_bar().max_value <= settings.pages[3].size.y + 1, "AI collapsed page fits without scrolling")
			panel.advanced_button.button_pressed = true
			await screenshot(settings, output.path_join("settings-ai-expanded.png"))
			settings.pages[3].scroll_vertical = 9999
			await screenshot(settings, output.path_join("settings-ai-advanced-bottom.png"))
			verify(settings.pages[3].get_h_scroll_bar().max_value <= settings.pages[3].size.x + 1, "AI advanced controls have no horizontal overflow")
			panel.advanced_button.button_pressed = false
			panel.auth_method.select(panel.ROUTES.find("chatgpt")); panel._refresh_route()
			settings.pages[3].scroll_vertical = 0
			await screenshot(settings, output.path_join("settings-chatgpt.png"))
			verify(panel.auth_panel.visible and not panel.api_rows[0].visible, "account login has an explicit separate billing path")
			verify(settings.pages[3].get_h_scroll_bar().max_value <= settings.pages[3].size.x + 1, "ChatGPT login controls have no horizontal overflow")
			settings.hide()
			service.history = [{"role": "user", "text": "今天忙了一整天，有点累。", "at": 1}, {"role": "assistant", "text": "辛苦啦，先歇一小会儿吧喵。要不要喝点水、伸个懒腰？我就在这里陪着你。", "at": 2}]
			chat.open_panel()
			await screenshot(chat, output.path_join("chat.png"))
			chat.hide()
			service.add_memory("我喜欢简短、温柔的回复。")
			memory.open_panel()
			memory._select_item(0)
			await screenshot(memory, output.path_join("memory.png"))
			memory.hide()
	settings.queue_free()
	chat.queue_free()
	memory.queue_free()
	service.queue_free()
	await process_frame
	for message in failures: printerr(message)
	print("AI UI: %d checks, %s" % [checks, "PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)

func screenshot(window: Window, path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	window.get_texture().get_image().save_png(path)
