extends SceneTree
## Native settings with synthetic credentials and an in-memory service only.
## Official application links are inspected, never clicked.
const Settings = preload("res://scripts/pet_settings.gd")
const SettingsPanel = preload("res://scripts/ai_settings_panel.gd")

class FakeService extends Node:
	signal state_changed
	var settings := {"enabled":true,"auth_method":"api_key","model":"gpt-6-luna",
		"deepseek_model":"deepseek-flash","personality":"温柔简短","memory_enabled":true,
		"auto_memory_enabled":true,"memory_auth_method":"follow","include_pet_state":true,
		"proactive":false,"proactive_rest":true,"proactive_games":true,"proactive_reconnect":true,
		"proactive_daily_limit":4,"proactive_interval_minutes":60,"quiet_enabled":true,
		"quiet_start":22,"quiet_end":8}
	var busy := false
	var status := "准备好了（测试服务）"
	var openai_secret := "fixture-openai-existing"
	var deepseek_secret := ""
	var saves := 0
	var tests := 0
	var fail_save := false
	var last_save := {}
	func has_key() -> bool: return not openai_secret.is_empty()
	func has_deepseek_key() -> bool: return not deepseek_secret.is_empty()
	func ready_to_chat() -> bool:
		return has_deepseek_key() if settings.auth_method == "deepseek" else has_key()
	func apply_settings(draft: Dictionary, new_key: String = "", erase_key: bool = false,
			new_deepseek_key: String = "", erase_deepseek_key: bool = false) -> Error:
		if fail_save:
			status = "测试保存失败"; state_changed.emit(); return ERR_CANT_CREATE
		last_save = {"openai":new_key,"erase_openai":erase_key,"deepseek":new_deepseek_key,"erase_deepseek":erase_deepseek_key}
		if not new_key.is_empty(): openai_secret = new_key
		elif erase_key: openai_secret = ""
		if not new_deepseek_key.is_empty(): deepseek_secret = new_deepseek_key
		elif erase_deepseek_key: deepseek_secret = ""
		settings = draft.duplicate(true); saves += 1; status = "已保存"; state_changed.emit(); return OK
	func test_connection() -> bool: tests += 1; return true

var failures: Array[String] = []
var checks := 0
var output := ""
var settings
var service := FakeService.new()

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	call_deferred("run")

func choose(panel, route: String) -> void:
	var index: int = SettingsPanel.ROUTES.find(route)
	panel.auth_method.select(index); panel.auth_method.item_selected.emit(index)

func type_key(field: LineEdit, value: String) -> void:
	field.text = value; field.text_changed.emit(value)

func screenshot(name: String) -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	settings.get_texture().get_image().save_png(output.path_join(name + ".png"))

func screenshot_providers(panel: Control) -> void:
	if output.is_empty(): return
	panel.auth_method.show_popup()
	await process_frame
	await RenderingServer.frame_post_draw
	var popup: PopupMenu = panel.auth_method.get_popup()
	popup.get_texture().get_image().save_png(output.path_join("provider-order.png"))
	popup.hide()

func run() -> void:
	root.add_child(service)
	settings = Settings.new(); settings.ai_service = service; root.add_child(settings)
	await process_frame
	settings.show_settings(false, 60, 180); settings._select_page(3)
	var panel = settings.ai_panel
	verify(panel.auth_method.item_count == 3 and panel.auth_method.get_item_text(0) == "DeepSeek API" and SettingsPanel.ROUTES == ["deepseek","api_key","chatgpt"], "provider picker lists DeepSeek first while keeping stable route identities")
	verify(panel.auth_method.get_item_text(1) == "OpenAI API" and panel.auth_method.get_item_text(2) == "ChatGPT 账户", "all three displayed labels match their reordered stable identities")
	verify(SettingsPanel.MEMORY_ROUTES == ["follow","deepseek","api_key","chatgpt"], "memory picker keeps follow-chat first and groups providers in the same order")
	verify(panel.api_link.visible and not panel.deepseek_link.visible and not panel.auth_panel.visible, "OpenAI shows only its own credential controls and official link")
	verify(SettingsPanel.OPENAI_KEYS_URL == "https://platform.openai.com/api-keys" and panel.api_link.tooltip_text.ends_with(SettingsPanel.OPENAI_KEYS_URL), "OpenAI application link points to its fixed official key page")
	verify(SettingsPanel.DEEPSEEK_KEYS_URL == "https://platform.deepseek.com/api_keys" and panel.deepseek_link.tooltip_text.ends_with(SettingsPanel.DEEPSEEK_KEYS_URL), "DeepSeek application link points to its fixed official key page")
	verify(panel.key.secret and panel.deepseek_key.secret and not panel.key.context_menu_enabled and not panel.deepseek_key.context_menu_enabled, "both provider keys are masked with credential context menus disabled")
	verify(panel.key.text.is_empty() and panel.key.placeholder_text.contains("已安全保存") and panel.deepseek_key.text.is_empty(), "stored secrets are never loaded into editable fields")
	verify(not panel.connection.disabled, "matching saved OpenAI configuration can be tested")
	verify(panel.speech_speed is HSlider and panel.speech_speed.min_value == 0 and panel.speech_speed.max_value == 4 and panel.speech_speed.step == 1 and panel.speech_speed.tick_count == 5,
		"speech speed uses one slider with exactly five stops")
	verify(panel.speech_speed.value == 2 and panel.speech_speed_label.text == "正常" and not service.settings.has("speech_speed") and service.saves == 0,
		"old configuration opens at normal speech speed without eagerly migrating or saving")
	await screenshot("openai-api-settings")
	await screenshot_providers(panel)
	type_key(panel.key, "fixture-openai-draft")
	panel.model.text = "gpt-custom-draft"
	choose(panel, "deepseek")
	verify(panel.deepseek_key.is_visible_in_tree() and panel.deepseek_link.visible and not panel.api_link.visible and not panel.key.is_visible_in_tree(), "DeepSeek displays its own model key and application link")
	verify(panel.deepseek_model.item_count >= 2 and panel._deepseek_models[0] == "deepseek-flash" and panel._deepseek_models[1] == "deepseek-v4-pro", "DeepSeek exposes its two configured model choices")
	verify(panel.connection.disabled and service.tests == 0, "unsaved provider change cannot test the previous provider")
	type_key(panel.deepseek_key, "fixture-deepseek-draft")
	panel.deepseek_model.select(1)
	var deepseek_memory_index: int = SettingsPanel.MEMORY_ROUTES.find("deepseek")
	panel.memory_auth_method.select(deepseek_memory_index); panel.memory_auth_method.item_selected.emit(deepseek_memory_index)
	verify(panel.memory_route_hint.text.contains("DeepSeek"), "memory AI can independently select DeepSeek")
	choose(panel, "chatgpt")
	verify(panel.auth_panel.visible and not panel.api_link.visible and not panel.deepseek_link.visible, "ChatGPT login hides both API application links")
	choose(panel, "api_key")
	verify(panel.key.text == "fixture-openai-draft" and panel.model.text == "gpt-custom-draft", "switching routes preserves the OpenAI draft")
	choose(panel, "deepseek")
	verify(panel.deepseek_key.text == "fixture-deepseek-draft" and panel.deepseek_model.selected == 1, "switching routes preserves the independent DeepSeek draft")
	verify(service.saves == 0 and service.openai_secret == "fixture-openai-existing" and service.deepseek_secret.is_empty(), "draft editing never changes stored credentials")
	await screenshot("deepseek-api-settings")
	verify(panel.commit_draft() == OK, "save accepts DeepSeek and its separate credential")
	verify(service.last_save.openai == "fixture-openai-draft" and service.last_save.deepseek == "fixture-deepseek-draft" and not service.last_save.erase_openai and not service.last_save.erase_deepseek, "save sends each secret in its own provider argument")
	verify(service.settings.auth_method == "deepseek" and service.settings.model == "gpt-custom-draft" and service.settings.deepseek_model == "deepseek-v4-pro", "selected provider and both model preferences persist separately")
	verify(service.settings.memory_auth_method == "deepseek", "memory provider selection is saved")
	verify(panel.key.text.is_empty() and panel.deepseek_key.text.is_empty() and panel.deepseek_key.placeholder_text.contains("已安全保存"), "successful save clears both secret drafts")
	verify(not panel.connection.disabled, "saved DeepSeek configuration can be tested")
	panel.connection.pressed.emit()
	verify(service.tests == 1, "test button reaches only the saved in-memory configuration")

	# Deletion stays a draft until saving and always targets one provider.
	panel.remove_deepseek_key.pressed.emit()
	verify(panel.deepseek_erase_pending and service.has_deepseek_key() and not panel.erase_pending, "DeepSeek deletion is an independent pending draft")
	settings.hide()
	verify(not panel.deepseek_erase_pending and panel.deepseek_key.text.is_empty() and panel.key.text.is_empty(), "closing settings discards both secret drafts and pending removal")
	settings.show_settings(false, 60, 180); settings._select_page(3)
	verify(service.has_deepseek_key() and not panel.deepseek_erase_pending, "canceling deletion preserves the saved DeepSeek credential")
	panel.enabled.button_pressed = false
	panel.remove_deepseek_key.pressed.emit(); panel.commit_draft()
	verify(service.deepseek_secret.is_empty() and service.openai_secret == "fixture-openai-draft" and service.last_save.erase_deepseek and not service.last_save.erase_openai, "saving DeepSeek deletion leaves OpenAI credentials intact")
	type_key(panel.deepseek_key, "fixture-deepseek-replacement"); panel.commit_draft()
	choose(panel, "api_key"); panel.remove_key.pressed.emit(); panel.commit_draft()
	verify(service.openai_secret.is_empty() and service.deepseek_secret == "fixture-deepseek-replacement" and service.last_save.erase_openai and not service.last_save.erase_deepseek, "saving OpenAI deletion leaves DeepSeek credentials intact")

	# A failed save retains drafts for correction; Cancel then removes both.
	choose(panel, "deepseek"); type_key(panel.deepseek_key, "fixture-deepseek-unsaved")
	type_key(panel.key, "fixture-openai-unsaved"); service.fail_save = true
	verify(panel.commit_draft() == ERR_CANT_CREATE and panel.deepseek_key.text == "fixture-deepseek-unsaved" and panel.key.text == "fixture-openai-unsaved", "failed save retains editable secret drafts")
	verify(service.openai_secret.is_empty() and service.deepseek_secret == "fixture-deepseek-replacement", "failed save does not change either provider credential")
	settings.hide()
	verify(panel.key.text.is_empty() and panel.deepseek_key.text.is_empty(), "cancel clears both secrets after a failed save")
	service.fail_save = false
	verify_legacy_routes(panel)
	await verify_speech_speed(panel)
	settings.queue_free(); service.queue_free(); await process_frame
	for failure in failures: printerr("DEEPSEEK UI: " + failure)
	print("DeepSeek UI: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func verify_legacy_routes(panel: Control) -> void:
	# Older settings persist route names, never picker indexes. Reordering the
	# controls must not opt existing users into another provider or memory bill.
	var saved_openai := service.openai_secret
	var saved_deepseek := service.deepseek_secret
	var saved_openai_model: String = service.settings.model
	var saved_deepseek_model: String = service.settings.deepseek_model
	for route in ["api_key", "chatgpt", "deepseek"]:
		for memory_route in ["follow", "api_key", "chatgpt", "deepseek"]:
			service.settings.auth_method = route
			service.settings.memory_auth_method = memory_route
			panel.load_draft(service)
			verify(panel.auth_method.selected == SettingsPanel.ROUTES.find(route) \
				and panel.memory_auth_method.selected == SettingsPanel.MEMORY_ROUTES.find(memory_route),
				"old " + route + "/" + memory_route + " settings select the same named providers")
			panel.include_pet_state.button_pressed = not panel.include_pet_state.button_pressed
			verify(panel.commit_draft() == OK and service.settings.auth_method == route \
				and service.settings.memory_auth_method == memory_route,
				"unrelated save preserves old " + route + "/" + memory_route + " billing routes")
	verify(service.openai_secret == saved_openai and service.deepseek_secret == saved_deepseek \
		and service.settings.model == saved_openai_model and service.settings.deepseek_model == saved_deepseek_model,
		"provider reorder round-trips never modify stored credentials or per-provider models")

func verify_speech_speed(panel: Control) -> void:
	# Use a legacy configuration and keep both provider identities and secrets
	# observable while exercising the new draft-only control.
	service.settings.erase("speech_speed")
	service.openai_secret = "fixture-openai-speech-existing"
	service.deepseek_secret = "fixture-deepseek-speech-existing"
	var original: Dictionary = service.settings.duplicate(true)
	var saves_before := service.saves
	settings.show_settings(false, 60, 180); settings._select_page(3)
	panel.advanced_button.button_pressed = true
	var labels := ["慢", "较慢", "正常", "较快", "快"]
	for index in range(labels.size()):
		panel.speech_speed.value = index
		verify(panel.speech_speed_label.text == labels[index], "speech speed stop " + str(index) + " shows " + labels[index])
	verify(service.saves == saves_before and service.settings == original,
		"moving through every speech-speed stop changes only the unsaved draft")
	settings.hide()
	settings.show_settings(false, 60, 180); settings._select_page(3)
	verify(panel.speech_speed.value == 2 and panel.speech_speed_label.text == "正常" and service.settings == original and service.saves == saves_before,
		"canceling an old configuration restores normal speed without changing providers or other preferences")
	panel.advanced_button.button_pressed = true
	panel.speech_speed.value = 3
	await process_frame
	await process_frame
	var page: ScrollContainer = settings.pages[3]
	page.scroll_vertical += roundi(panel.advanced_button.get_global_rect().position.y - page.get_global_rect().position.y)
	await process_frame
	await screenshot("speech-speed-settings")
	verify(panel.speech_speed.is_visible_in_tree() and panel.speech_speed.size.x >= 130 and panel.speech_speed_label.text == "较快",
		"expanded expression settings display the speed slider and current stop together")
	verify(settings.pages[3].get_h_scroll_bar().max_value <= settings.pages[3].size.x + 1,
		"expanded speech-speed settings fit without horizontal scrolling")
	verify(panel.speech_speed.get_global_rect().end.x <= panel.speech_speed_label.get_global_rect().position.x + 1,
		"speech slider and its label do not overlap horizontally")
	verify(panel.speech_speed_label.get_global_rect().end.x <= page.get_global_rect().end.x and panel.speech_speed.get_global_rect().position.y >= page.get_global_rect().position.y and panel.speech_speed.get_global_rect().end.y <= page.get_global_rect().end.y,
		"speech speed stays within the visible page bounds at the native settings size")
	panel.speech_speed.value = 4
	settings._save()
	verify(not settings.visible and service.saves == saves_before + 1 and service.settings.get("speech_speed") == 4,
		"Save applies the chosen speech speed and closes the settings window")
	var without_speed: Dictionary = service.settings.duplicate(true)
	without_speed.erase("speech_speed")
	verify(without_speed == original and service.openai_secret == "fixture-openai-speech-existing" and service.deepseek_secret == "fixture-deepseek-speech-existing",
		"saving speech speed preserves both credentials, provider routes and every other preference")
	settings.show_settings(false, 60, 180); settings._select_page(3)
	verify(panel.speech_speed.value == 4 and panel.speech_speed_label.text == "快",
		"reopening settings restores the saved speech speed and matching label")
	verify(panel.commit_draft() == OK and service.saves == saves_before + 1,
		"unchanged speech speed does not resave or interrupt the current AI request")
	panel.speech_speed.value = 0
	service.fail_save = true
	settings._save()
	verify(settings.visible and panel.speech_speed.value == 0 and service.settings.speech_speed == 4 and service.saves == saves_before + 1,
		"failed speech-speed save retains the editable draft and the previous stored speed")
	service.fail_save = false
	settings.hide()
	settings.show_settings(false, 60, 180); settings._select_page(3)
	verify(panel.speech_speed.value == 4 and panel.speech_speed_label.text == "快",
		"cancel after a failed save restores the previously stored speed")
	settings.hide()
