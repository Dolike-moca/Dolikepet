extends VBoxContainer
## A settings draft. Credentials and preferences change only through commit_draft().

signal chat_requested
signal memory_requested
const SettingsTheme = preload("res://scripts/settings_theme.gd")
const AuthPanel = preload("res://scripts/chatgpt_auth_panel.gd")
const Frequency = preload("res://scripts/companion_frequency.gd")
const SpeechSpeed = preload("res://scripts/speech_speed.gd")
const MEMORY_ROUTES := ["follow", "deepseek", "api_key", "chatgpt"]
const ROUTES := ["deepseek", "api_key", "chatgpt"]
const OPENAI_KEYS_URL := "https://platform.openai.com/api-keys"
const DEEPSEEK_KEYS_URL := "https://platform.deepseek.com/api_keys"
var service: Node
var enabled := CheckButton.new()
var auth_method := OptionButton.new()
var auth_panel = AuthPanel.new()
var api_rows: Array[Control] = []
var deepseek_rows: Array[Control] = []
var api_link := LinkButton.new()
var deepseek_link := LinkButton.new()
var deepseek_model := OptionButton.new()
var deepseek_key := LineEdit.new()
var remove_deepseek_key := Button.new()
var deepseek_erase_pending := false
var _deepseek_models: Array[String] = ["deepseek-flash", "deepseek-v4-pro"]
var billing_hint := Label.new()
var model := LineEdit.new()
var key := LineEdit.new()
var remove_key := Button.new()
var connection := Button.new()
var chat := Button.new()
var memory := Button.new()
var status_label := Label.new()
var advanced_button := Button.new()
var advanced := VBoxContainer.new()
var personality := TextEdit.new()
var speech_speed := HSlider.new()
var speech_speed_label := Label.new()
var memory_enabled := CheckButton.new()
var auto_memory_enabled := CheckButton.new()
var memory_auth_method := OptionButton.new()
var memory_route_hint := Label.new()
var include_pet_state := CheckButton.new()
var proactive := CheckButton.new()
var rest_reminders := CheckButton.new()
var game_invitations := CheckButton.new()
var reconnect_invitations := CheckButton.new()
var daily_limit := SpinBox.new()
var unlimited_daily := CheckButton.new()
var interval := HSlider.new()
var frequency_label := Label.new()
var frequency_hint := Label.new()
var quiet_enabled := CheckButton.new()
var quiet_start := SpinBox.new()
var quiet_end := SpinBox.new()
var _loaded_interval := 60
var _frequency_touched := false
var erase_pending := false
var pending_fields: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_row("启用 AI").add_child(enabled)
	for caption in ["DeepSeek API", "OpenAI API", "ChatGPT 账户"]: auth_method.add_item(caption)
	auth_method.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row("接入方式").add_child(auth_method)
	auth_method.item_selected.connect(func(_index: int): _refresh_route())
	_hint(billing_hint)
	add_child(billing_hint)
	add_child(auth_panel)
	model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model.placeholder_text = "gpt-6-luna"
	model.max_length = 160
	var model_row := _row("模型")
	model_row.add_child(model)
	api_rows.append(model_row.get_parent())
	key.secret = true
	key.max_length = 4096
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.placeholder_text = "输入自己的 API Key"
	key.context_menu_enabled = false
	var key_row := _row("API Key")
	api_rows.append(key_row.get_parent())
	key_row.add_child(key)
	remove_key.text = "删除"
	remove_key.tooltip_text = "保存后删除此设备上的 API Key"
	key_row.add_child(remove_key)
	remove_key.pressed.connect(func():
		erase_pending = not erase_pending
		key.text = ""
		_refresh_key_hint())
	key.text_changed.connect(func(_text: String):
		if not key.text.is_empty(): erase_pending = false
		_refresh_key_hint())
	_api_link(api_link, OPENAI_KEYS_URL)
	api_rows.append(api_link)
	var deepseek_model_row := _row("模型")
	deepseek_rows.append(deepseek_model_row.get_parent())
	deepseek_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deepseek_model.fit_to_longest_item = false; deepseek_model.clip_text = true
	for name in _deepseek_models: deepseek_model.add_item(name)
	deepseek_model_row.add_child(deepseek_model)
	var deepseek_key_row := _row("API Key")
	deepseek_rows.append(deepseek_key_row.get_parent())
	deepseek_key.secret = true; deepseek_key.max_length = 4096
	deepseek_key.context_menu_enabled = false
	deepseek_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deepseek_key_row.add_child(deepseek_key)
	remove_deepseek_key.tooltip_text = "保存后删除此设备上的 DeepSeek API Key"
	deepseek_key_row.add_child(remove_deepseek_key)
	remove_deepseek_key.pressed.connect(func():
		deepseek_erase_pending = not deepseek_erase_pending
		deepseek_key.text = ""; _refresh_key_hint())
	deepseek_key.text_changed.connect(func(_text: String):
		if not deepseek_key.text.is_empty(): deepseek_erase_pending = false
		_refresh_key_hint())
	_api_link(deepseek_link, DEEPSEEK_KEYS_URL)
	deepseek_rows.append(deepseek_link)
	# Keep provider-specific links beside the one test action. Hidden providers
	# retain their drafts; ordering never changes a stored billing route.
	var connection_tools := HBoxContainer.new()
	connection_tools.add_theme_constant_override("separation", 8)
	add_child(connection_tools)
	connection_tools.add_child(api_link); connection_tools.add_child(deepseek_link)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection_tools.add_child(spacer)
	connection.text = "测试连接"
	connection.tooltip_text = "测试已保存的配置；修改连接后请先保存"
	connection_tools.add_child(connection)
	connection.pressed.connect(func():
		if is_instance_valid(service): service.test_connection())
	_hint(status_label)
	status_label.text = "保存后生效"
	add_child(status_label)
	add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	chat.text = "开始聊天"
	memory.text = "管理记忆"
	chat.tooltip_text = "请先保存并关闭设置，再和猫猫聊天"
	chat.add_theme_stylebox_override("normal", SettingsTheme.box(Color("614283")))
	chat.add_theme_stylebox_override("hover", SettingsTheme.box(Color("75529a")))
	for button in [chat, memory]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	chat.pressed.connect(func(): chat_requested.emit())
	memory.pressed.connect(func(): memory_requested.emit())
	advanced_button.text = "▸  陪伴与隐私"
	advanced_button.toggle_mode = true
	advanced_button.flat = true
	advanced_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(advanced_button)
	advanced.add_theme_constant_override("separation", 8)
	advanced.visible = false
	add_child(advanced)
	advanced_button.toggled.connect(func(value: bool):
		advanced.visible = value
		advanced_button.text = ("▾  " if value else "▸  ") + "陪伴与隐私")
	_section("表达与记忆", advanced)
	speech_speed.min_value = 0; speech_speed.max_value = 4; speech_speed.step = 1
	speech_speed.tick_count = 5; speech_speed.ticks_on_borders = true
	speech_speed.scrollable = false
	speech_speed.custom_minimum_size = Vector2(130, 24)
	speech_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech_speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speech_speed.tooltip_text = "慢 · 较慢 · 正常 · 较快 · 快；同时调整文字出现和嘴部开合"
	var speech_controls := _row("说话速度", advanced)
	speech_controls.add_child(speech_speed)
	speech_speed_label.custom_minimum_size.x = 34
	speech_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speech_speed_label.add_theme_color_override("font_color", SettingsTheme.ACCENT)
	speech_controls.add_child(speech_speed_label)
	speech_speed.value_changed.connect(func(_value: float): _refresh_speech_speed())
	var speech_hint := Label.new()
	speech_hint.text = "文字逐字出现与嘴部开合，按同一档位调整。"
	_hint(speech_hint); advanced.add_child(speech_hint)
	var personality_label := Label.new()
	personality_label.text = "猫咪的说话风格"
	advanced.add_child(personality_label)
	personality.custom_minimum_size.y = 86
	personality.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	personality.placeholder_text = "例如：温柔、简短，偶尔用喵结尾。"
	_style_editor(personality)
	advanced.add_child(personality)
	_row("使用本地记忆", advanced).add_child(memory_enabled)
	_row("自动记忆日常聊天", advanced).add_child(auto_memory_enabled)
	for caption in ["跟随聊天 AI（默认）", "DeepSeek API", "OpenAI API", "ChatGPT 账户"]: memory_auth_method.add_item(caption)
	memory_auth_method.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row("默认记忆 AI", advanced).add_child(memory_auth_method)
	memory_auth_method.item_selected.connect(func(_index: int): _refresh_memory())
	_hint(memory_route_hint)
	advanced.add_child(memory_route_hint)
	memory_enabled.toggled.connect(func(_value: bool): _refresh_memory())
	_row("分享桌宠状态", advanced).add_child(include_pet_state)
	var memory_hint := Label.new()
	memory_hint.text = "记忆保存在本机；自动整理使用所选 AI 的额度。"
	memory_hint.tooltip_text = "每天空闲时整理新增聊天；启用记忆时，相关记忆会随聊天发送。可编辑、固定或忘记，不读取屏幕或文件。"
	_hint(memory_hint)
	advanced.add_child(memory_hint)
	_section("主动陪伴", advanced)
	_row("主动问候", advanced).add_child(proactive)
	_row("休息提醒", advanced).add_child(rest_reminders)
	_row("游戏后闲聊", advanced).add_child(game_invitations)
	_row("久未互动问候", advanced).add_child(reconnect_invitations)
	daily_limit.min_value = 1; daily_limit.max_value = 8; daily_limit.step = 1
	daily_limit.suffix = "次"; daily_limit.custom_minimum_size.x = 80
	_row("每天最多", advanced).add_child(daily_limit)
	unlimited_daily.tooltip_text = "只取消每日次数上限；仍遵守问候间隔、静默时段及忙碌避让。"
	_row("无上限", advanced).add_child(unlimited_daily)
	unlimited_daily.toggled.connect(func(_value: bool): _refresh_proactive())
	daily_limit.get_line_edit().text_changed.connect(func(_text: String): pending_fields[daily_limit] = true)
	interval.min_value = 0
	interval.max_value = 4
	interval.step = 1
	interval.tick_count = 5
	interval.ticks_on_borders = true
	interval.scrollable = false
	interval.custom_minimum_size = Vector2(130, 24)
	interval.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interval.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	interval.tooltip_text = "很少 · 偶尔 · 适中 · 经常 · 频繁"
	var frequency := VBoxContainer.new()
	frequency.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frequency.add_theme_constant_override("separation", 0)
	_row("常说话", advanced).add_child(frequency)
	var frequency_line := HBoxContainer.new()
	frequency_line.add_theme_constant_override("separation", 8)
	frequency.add_child(frequency_line)
	frequency_line.add_child(interval)
	frequency_label.custom_minimum_size.x = 34
	frequency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frequency_label.add_theme_color_override("font_color", SettingsTheme.ACCENT)
	frequency_line.add_child(frequency_label)
	var endpoints := HBoxContainer.new()
	frequency.add_child(endpoints)
	for caption in ["少", "多"]:
		var label := Label.new()
		label.text = caption
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if caption == "少" else HORIZONTAL_ALIGNMENT_RIGHT
		_hint(label)
		endpoints.add_child(label)
	_hint(frequency_hint)
	advanced.add_child(frequency_hint)
	interval.value_changed.connect(func(_value: float): _touch_frequency())
	interval.drag_started.connect(_touch_frequency)
	_row("静默时段", advanced).add_child(quiet_enabled)
	quiet_enabled.toggled.connect(_quiet_toggled)
	var quiet := _row("时间", advanced)
	for field in [quiet_start, quiet_end]:
		field.min_value = 0
		field.max_value = 23
		field.step = 1
		field.suffix = "时"
		field.custom_minimum_size.x = 80
	quiet.add_child(quiet_start)
	var dash := Label.new()
	dash.text = "至"
	quiet.add_child(dash)
	quiet.add_child(quiet_end)
	var quiet_hint := Label.new()
	quiet_hint.text = "静默开启时，这段时间不主动打扰；关闭后保留已选时间。"
	_hint(quiet_hint)
	advanced.add_child(quiet_hint)
	proactive.toggled.connect(func(_value: bool): _refresh_proactive())
	for field in [quiet_start, quiet_end]:
		field.get_line_edit().text_changed.connect(func(_text: String): pending_fields[field] = true)
	load_draft(service)

func _section(caption: String, parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new(); label.text = caption
	label.add_theme_color_override("font_color", SettingsTheme.ACCENT)
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)

func _selected_route() -> String:
	return ROUTES[clampi(auth_method.selected, 0, ROUTES.size() - 1)]

func _selected_memory_route() -> String:
	return MEMORY_ROUTES[clampi(memory_auth_method.selected, 0, MEMORY_ROUTES.size() - 1)]

func _row(caption: String, parent: VBoxContainer = null) -> HBoxContainer:
	if parent == null: parent = self
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 100
	row.add_child(label)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 5)
	row.add_child(controls)
	return controls

func _hint(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SettingsTheme.MUTED)

func _style_editor(editor: TextEdit) -> void:
	editor.add_theme_stylebox_override("normal", SettingsTheme.box(Color("25232b")))
	var focus := SettingsTheme.box(Color.TRANSPARENT)
	focus.set_border_width_all(1)
	focus.border_color = SettingsTheme.ACCENT
	editor.add_theme_stylebox_override("focus", focus)
	editor.add_theme_color_override("font_color", SettingsTheme.TEXT)
	editor.add_theme_color_override("caret_color", SettingsTheme.ACCENT)

func _api_link(link: LinkButton, url: String) -> void:
	link.text = "申请 API Key ↗"
	link.tooltip_text = "在系统浏览器打开官方密钥页面：" + url
	link.size_flags_horizontal = Control.SIZE_SHRINK_END
	link.add_theme_font_size_override("font_size", 12)
	link.pressed.connect(func(): OS.shell_open(url))

func load_draft(value: Node) -> void:
	if is_instance_valid(service) and service.state_changed.is_connected(_refresh_status):
		service.state_changed.disconnect(_refresh_status)
	service = value
	if is_instance_valid(service): service.state_changed.connect(_refresh_status)
	var draft: Dictionary = service.settings if is_instance_valid(service) else {}
	enabled.set_pressed_no_signal(bool(draft.get("enabled", false)))
	auth_method.select(maxi(0, ROUTES.find(str(draft.get("auth_method", "api_key")))))
	auth_panel.setup(service.auth if is_instance_valid(service) and service.has_method("bind_auth") else null)
	model.text = str(draft.get("model", "gpt-6-luna"))
	speech_speed.set_value_no_signal(clampi(int(draft.get("speech_speed", SpeechSpeed.DEFAULT)), 0, 4))
	_refresh_speech_speed()
	var saved_deepseek := str(draft.get("deepseek_model", "deepseek-flash"))
	if not _deepseek_models.has(saved_deepseek):
		_deepseek_models.append(saved_deepseek); deepseek_model.add_item(saved_deepseek)
	deepseek_model.select(_deepseek_models.find(saved_deepseek))
	personality.text = str(draft.get("personality", ""))
	memory_enabled.set_pressed_no_signal(bool(draft.get("memory_enabled", true)))
	auto_memory_enabled.set_pressed_no_signal(bool(draft.get("auto_memory_enabled", true)))
	var memory_route_index := MEMORY_ROUTES.find(str(draft.get("memory_auth_method", "follow")))
	memory_auth_method.select(maxi(0, memory_route_index))
	include_pet_state.set_pressed_no_signal(bool(draft.get("include_pet_state", true)))
	proactive.set_pressed_no_signal(bool(draft.get("proactive", false)))
	rest_reminders.set_pressed_no_signal(bool(draft.get("proactive_rest", true)))
	game_invitations.set_pressed_no_signal(bool(draft.get("proactive_games", true)))
	reconnect_invitations.set_pressed_no_signal(bool(draft.get("proactive_reconnect", true)))
	var saved_daily_limit := int(draft.get("proactive_daily_limit", 4))
	unlimited_daily.set_pressed_no_signal(saved_daily_limit == 0)
	daily_limit.value = saved_daily_limit if saved_daily_limit > 0 else 4
	_loaded_interval = clampi(int(draft.get("proactive_interval_minutes", 60)), 5, 240)
	_frequency_touched = false
	interval.set_value_no_signal(Frequency.nearest(_loaded_interval))
	quiet_start.value = int(draft.get("quiet_start", 22))
	quiet_end.value = int(draft.get("quiet_end", 8))
	quiet_enabled.set_pressed_no_signal(bool(draft.get("quiet_enabled", int(quiet_start.value) != int(quiet_end.value))))
	pending_fields.clear()
	erase_pending = false
	key.text = ""
	deepseek_erase_pending = false
	deepseek_key.text = ""
	_refresh_key_hint()
	_refresh_proactive()
	_refresh_frequency()
	_refresh_memory()
	_refresh_status()
	_refresh_route()

func _refresh_route() -> void:
	var route := _selected_route()
	auth_panel.visible = route == "chatgpt"
	for row in api_rows: row.visible = route == "api_key"
	for row in deepseek_rows: row.visible = route == "deepseek"
	billing_hint.visible = route != "chatgpt"
	match route:
		"chatgpt": billing_hint.text = "使用 ChatGPT 账户授权"
		"deepseek": billing_hint.text = "使用个人密钥 · DeepSeek 账户计费"
		_: billing_hint.text = "使用个人密钥 · OpenAI 账户计费"
	_refresh_status()
	if is_instance_valid(service) and str(service.settings.get("auth_method", "api_key")) != route:
		status_label.text = "已切换接入方式，保存后可测试连接。"

func _refresh_proactive() -> void:
	interval.editable = proactive.button_pressed
	interval.modulate.a = 1.0 if proactive.button_pressed else 0.5
	frequency_label.modulate.a = interval.modulate.a
	daily_limit.editable = proactive.button_pressed and not unlimited_daily.button_pressed
	daily_limit.modulate.a = 1.0 if daily_limit.editable else 0.5
	unlimited_daily.disabled = not proactive.button_pressed
	quiet_enabled.disabled = not proactive.button_pressed
	_refresh_quiet()
	for field in [rest_reminders, game_invitations, reconnect_invitations]: field.disabled = not proactive.button_pressed

func _touch_frequency() -> void:
	_frequency_touched = true
	_refresh_frequency()

func _refresh_speech_speed() -> void:
	speech_speed_label.text = SpeechSpeed.label_at(int(speech_speed.value))

func _refresh_frequency() -> void:
	frequency_label.text = Frequency.label_at(int(interval.value))
	var mapped: int = Frequency.minute_at(int(interval.value))
	frequency_hint.text = "保留原频率（%d 分钟）；调整滑块后使用所选档位。" % _loaded_interval if not _frequency_touched and mapped != _loaded_interval else "只在适合聊天时主动问候，仍遵守每日次数和静默设置。"

func _quiet_toggled(value: bool) -> void:
	# An old equal-hour range meant 'off'. Explicitly switching it on gets a
	# useful default, while loading/canceling never changes the saved hours.
	if value and int(quiet_start.value) == int(quiet_end.value):
		quiet_start.value = 22
		quiet_end.value = 8
	_refresh_quiet()

func _refresh_quiet() -> void:
	for field in [quiet_start, quiet_end]:
		field.editable = proactive.button_pressed and quiet_enabled.button_pressed
		field.modulate.a = 1.0 if field.editable else 0.5

func _refresh_memory() -> void:
	auto_memory_enabled.disabled = not memory_enabled.button_pressed
	auto_memory_enabled.modulate.a = 1.0 if memory_enabled.button_pressed else 0.5
	memory_auth_method.disabled = not memory_enabled.button_pressed
	match _selected_memory_route():
		"api_key": memory_route_hint.text = "使用已保存的 OpenAI 密钥与模型。"
		"chatgpt": memory_route_hint.text = "使用当前 ChatGPT 账户与模型。"
		"deepseek": memory_route_hint.text = "使用已保存的 DeepSeek 密钥与模型。"
		_: memory_route_hint.text = "沿用聊天的连接与模型。"
	memory_route_hint.tooltip_text = "连接不可用时不会自动切换服务或计费账户。"

func _refresh_key_hint() -> void:
	remove_key.text = "撤销删除" if erase_pending else "删除"
	key.placeholder_text = "保存后删除密钥" if erase_pending else ("已安全保存，留空保持" if is_instance_valid(service) and service.has_key() else "输入自己的 API Key")
	remove_key.disabled = not erase_pending and key.text.is_empty() and (not is_instance_valid(service) or not service.has_key())
	var has_deepseek: bool = is_instance_valid(service) and service.has_method("has_deepseek_key") and service.has_deepseek_key()
	remove_deepseek_key.text = "撤销删除" if deepseek_erase_pending else "删除"
	deepseek_key.placeholder_text = "保存后删除密钥" if deepseek_erase_pending else ("已安全保存，留空保持" if has_deepseek else "输入 DeepSeek API Key")
	remove_deepseek_key.disabled = not deepseek_erase_pending and deepseek_key.text.is_empty() and not has_deepseek

func _refresh_status() -> void:
	var available := is_instance_valid(service)
	var credentials: bool = available and (service.ready_to_chat() if service.has_method("ready_to_chat") else service.has_key())
	connection.disabled = not available or service.busy or not credentials
	var route_changed: bool = available and str(service.settings.get("auth_method", "api_key")) != _selected_route()
	if route_changed: connection.disabled = true
	chat.disabled = not available
	memory.disabled = not available
	status_label.text = str(service.status) if available else "AI 服务准备中。"
	if status_label.text.is_empty(): status_label.text = "配置保存后生效。"

func commit_draft() -> Error:
	if not is_instance_valid(service): return OK
	# Unvisited SpinBoxes can still display their construction-time text.
	# Commit only fields actually typed into, preserving loaded hidden values.
	for field in pending_fields: field.apply()
	pending_fields.clear()
	var draft := {
		"enabled": enabled.button_pressed,
		"auth_method": _selected_route(),
		"model": model.text.strip_edges(),
		"personality": personality.text.strip_edges(),
		"speech_speed": int(speech_speed.value),
		"memory_enabled": memory_enabled.button_pressed,
		"auto_memory_enabled": auto_memory_enabled.button_pressed,
		"memory_auth_method": _selected_memory_route(),
		"include_pet_state": include_pet_state.button_pressed,
		"proactive": proactive.button_pressed,
		"proactive_rest": rest_reminders.button_pressed,
		"proactive_games": game_invitations.button_pressed,
		"proactive_reconnect": reconnect_invitations.button_pressed,
		"proactive_daily_limit": 0 if unlimited_daily.button_pressed else int(daily_limit.value),
		"proactive_interval_minutes": Frequency.minute_at(int(interval.value)) if _frequency_touched else _loaded_interval,
		"quiet_enabled": quiet_enabled.button_pressed,
		"quiet_start": int(quiet_start.value),
		"quiet_end": int(quiet_end.value),
	}
	var changed := erase_pending or not key.text.strip_edges().is_empty()
	var supports_deepseek: bool = service.has_method("has_deepseek_key")
	if supports_deepseek:
		draft.deepseek_model = _deepseek_models[maxi(0,deepseek_model.selected)]
		changed = changed or deepseek_erase_pending or not deepseek_key.text.strip_edges().is_empty()
	for name in draft:
		if draft[name] != service.settings.get(name): changed = true
	# Saving an unrelated pet setting must not cancel an in-flight AI reply.
	if not changed: return OK
	var result: Error
	if supports_deepseek:
		result = service.apply_settings(draft, key.text.strip_edges(), erase_pending, deepseek_key.text.strip_edges(), deepseek_erase_pending)
	else: result = service.apply_settings(draft, key.text.strip_edges(), erase_pending)
	if result == OK:
		key.text = ""
		erase_pending = false
		deepseek_key.text = ""; deepseek_erase_pending = false
		_loaded_interval = int(draft.proactive_interval_minutes)
		_frequency_touched = false
		_refresh_frequency()
		_refresh_key_hint()
	_refresh_status()
	return result

func discard_secret_draft() -> void:
	key.text = ""
	erase_pending = false
	deepseek_key.text = ""; deepseek_erase_pending = false
	pending_fields.clear()
