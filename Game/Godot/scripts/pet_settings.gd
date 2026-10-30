extends Window
## A native settings window; drafts are applied only with Save.

signal settings_saved(auto_sit_enabled: bool, minimum_seconds: float, maximum_seconds: float, roaming_mode: String, auto_fall_enabled: bool)
signal common_settings_saved(pixels: int, gaze: bool, topmost: bool)
signal bowl_settings_saved(capacity_bytes: int)
signal stomach_settings_saved(capacity_bytes: int, hours: float, auto_open: bool)
signal sleep_settings_saved(value: Dictionary)
signal open_stomach
signal open_bowl
signal ai_chat_requested
signal ai_memory_requested
const SettingsTheme = preload("res://scripts/settings_theme.gd")
const AISettingsPanel = preload("res://scripts/ai_settings_panel.gd")
const Sizes = preload("res://scripts/pet_size.gd")
const BowlCapacity = preload("res://scripts/bowl_capacity.gd")
const IdleSitting = preload("res://scripts/idle_sitting.gd")
const Roaming = preload("res://scripts/roaming.gd")
const AppUpdate = preload("res://scripts/app_update.gd")
var updater := AppUpdate.new()
var update_button := Button.new()
var download_button := Button.new()
var update_status := Label.new()
var update_progress := ProgressBar.new()

var activity_index := 1
var activity_buttons: Array[Button] = []
var navigation: Array[Button] = []
var pages: Array[ScrollContainer] = []
var current_page := 0
var details: Array[Button] = []
var sit_options := VBoxContainer.new()
var size_pixels := Sizes.BASE
var size_slider := HSlider.new()
var size_value := Label.new()
var size_reset := Button.new()
var gaze := CheckButton.new()
var topmost := CheckButton.new()
var fullness := ProgressBar.new()
var fullness_label := Label.new()
var footer_hint := Label.new()
var deletion_notice := Label.new()
var pending_fields: Dictionary = {}
var activity_hint := Label.new()
var automatic := CheckButton.new()
var auto_fall := CheckButton.new()
var minimum_minutes := SpinBox.new()
var minimum_seconds := SpinBox.new()
var maximum_minutes := SpinBox.new()
var maximum_seconds := SpinBox.new()
var delay_hint := Label.new()
var sleep_enabled := CheckButton.new()
var sleep_start_hour := SpinBox.new()
var sleep_start_minute := SpinBox.new()
var sleep_end_hour := SpinBox.new()
var sleep_end_minute := SpinBox.new()
var sleep_frequency := HSlider.new()
var sleep_frequency_label := Label.new()
var sleep_period_hint := Label.new()
var sleep_detail: Button
var save_button := Button.new()
var cancel_button := Button.new()
var bowl_capacity := SpinBox.new()
var bowl_unit := OptionButton.new()
var bowl_button := Button.new()
var stomach_capacity := SpinBox.new()
var stomach_unit := OptionButton.new()
var digestion_hours := SpinBox.new()
var auto_open_bowl := CheckButton.new()
var stomach_usage := Label.new()
var stomach_button := Button.new()
var ai_service: Node
var ai_panel := AISettingsPanel.new()

func _init() -> void:
	title = "桌宠设置"
	size = Vector2i(680, 540)
	min_size = size
	max_size = size
	unresizable = true
	borderless = false
	transparent = false
	transparent_bg = false
	visible = false

func _ready() -> void:
	# Independent native page: minimizing drafts never blocks the pet's windows.
	transient = false
	exclusive = false
	var panel := PanelContainer.new()
	panel.theme = SettingsTheme.make()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", SettingsTheme.box(Color("141318"), 0, 0))
	add_child(panel)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 0)
	panel.add_child(split)
	var rail := PanelContainer.new()
	rail.custom_minimum_size.x = 142
	rail.add_theme_stylebox_override("panel", SettingsTheme.box(Color("1b191f"), 0, 0))
	split.add_child(rail)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	_margin(rail, 14, 20).add_child(nav)
	_label(nav, "Dolike", 23)
	_label(nav, "桌宠设置", 12, true)
	var nav_gap := Control.new()
	nav_gap.custom_minimum_size.y = 22
	nav.add_child(nav_gap)
	var nav_group := ButtonGroup.new()
	for caption in ["常用", "活动", "喂食", "AI", "关于"]:
		var button := Button.new()
		button.text = caption
		button.toggle_mode = true
		button.button_group = nav_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 40
		button.add_theme_stylebox_override("normal", SettingsTheme.box(Color.TRANSPARENT))
		var index := navigation.size()
		button.pressed.connect(func(): _select_page(index))
		navigation.append(button)
		nav.add_child(button)
	var nav_space := Control.new()
	nav_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_space)
	_label(nav, "v" + AppUpdate.VERSION, 12, true)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	var main_margin := _margin(split, 24, 18)
	main_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_margin.add_child(main)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(stack)
	var common := _page(stack, "常用", "调整猫咪在桌面上的样子。")
	var size_controls := _row(common, "桌宠大小")
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 5)
	size_controls.add_child(choices)
	var size_header := HBoxContainer.new()
	choices.add_child(size_header)
	size_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_value.add_theme_color_override("font_color", SettingsTheme.ACCENT)
	size_header.add_child(size_value)
	size_reset.text = "重置"
	size_reset.tooltip_text = "恢复为 100%，保存后生效"
	size_header.add_child(size_reset)
	size_reset.pressed.connect(func(): _choose_size(Sizes.BASE))
	size_slider.min_value = 0
	size_slider.max_value = Sizes.PIXELS.size() - 1
	size_slider.step = 1
	size_slider.rounded = true
	size_slider.tick_count = Sizes.PIXELS.size()
	size_slider.ticks_on_borders = true
	size_slider.scrollable = false
	size_slider.custom_minimum_size = Vector2(180, 28)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.tooltip_text = "50%、75%、100%、125%、150%、175%、200%；保存后生效"
	choices.add_child(size_slider)
	size_slider.value_changed.connect(func(value: float): _choose_size(Sizes.PIXELS[clampi(roundi(value), 0, Sizes.PIXELS.size() - 1)]))
	var size_range := HBoxContainer.new()
	choices.add_child(size_range)
	_label(size_range, "50%", 12, true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(size_range, "200%", 12, true)
	_choose_size(Sizes.BASE)
	_toggle(common, "视线跟随鼠标", gaze)
	_toggle(common, "始终置顶", topmost)
	_detail(common, "缩放与显示说明", "100% 对应当前默认大小（300）。滚轮放大和缩小一次只改变一档；等待及缩放期间的额外滚动不会累积，动画结束且停滚后，再次滚动才改变下一档。\n这里选择的比例在保存后生效。放大时在掌心召唤蘑菇、双手抱着、闭眼分五小口吃完，再闪光长大；缩小平滑过渡，忙碌时等待。\n置顶设置同时应用到猫咪、坩埚和计分窗口。")
	var behavior := _page(stack, "活动", "按你的节奏，走走或歇一会儿。")
	var segments := _row(behavior, "走动习惯")
	segments.add_theme_constant_override("separation", 3)
	var group := ButtonGroup.new()
	for caption in ["常走动", "多待着", "不乱动"]:
		var button := Button.new()
		button.text = caption
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index := activity_buttons.size()
		button.pressed.connect(func(): _select_activity(index))
		activity_buttons.append(button)
		segments.add_child(button)
	_style_hint(activity_hint)
	behavior.add_child(activity_hint)
	_toggle(behavior, "离开底边自动下落", auto_fall)
	_toggle(behavior, "自动坐下休息", automatic)
	sit_options.add_theme_constant_override("separation", 10)
	behavior.add_child(sit_options)
	_duration_row(sit_options, "最短等待", minimum_minutes, minimum_seconds)
	_duration_row(sit_options, "最长等待", maximum_minutes, maximum_seconds)
	_style_hint(delay_hint)
	sit_options.add_child(delay_hint)
	_detail(behavior, "活动规则", "每轮在等待范围内随机一次；互动后重新计时。最短和最长相同时按固定时长等待。\n走动前回到当前屏幕底部；点击、拖动、缩放或打开菜单会暂停走动。\n自动坐下后点击会起身，手动坐下则保持坐姿。\n松手保留惯性，碰到侧边或顶部会反弹。自动下落关闭后缓慢停住，可在空中再次抓取。")
	_add_sleep_controls(behavior)
	var feeding := _page(stack, "喂食", "饭盆装食物，胃袋慢慢消化。")
	feeding.add_theme_constant_override("separation", 8)
	var status_row := HBoxContainer.new()
	feeding.add_child(status_row)
	_label(status_row, "饱食度", 14).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullness_label.add_theme_color_override("font_color", Color("a6cc68"))
	status_row.add_child(fullness_label)
	fullness.custom_minimum_size.y = 6
	fullness.show_percentage = false
	fullness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fullness.add_theme_stylebox_override("fill", SettingsTheme.box(Color("79a63d"), 3, 0))
	fullness.add_theme_stylebox_override("background", SettingsTheme.box(Color("2a3024"), 3, 0))
	feeding.add_child(fullness)
	_style_hint(stomach_usage)
	feeding.add_child(stomach_usage)
	_capacity_row(feeding, "满锅容量", bowl_capacity, bowl_unit)
	_capacity_row(feeding, "吃饱容量", stomach_capacity, stomach_unit)
	digestion_hours.min_value = 0.01
	digestion_hours.max_value = 8760
	digestion_hours.step = 0.01
	digestion_hours.suffix = "小时"
	digestion_hours.custom_minimum_size.x = 150
	_row(feeding, "消化时间").add_child(digestion_hours)
	deletion_notice.text = "到期永久删除，关机时间也计入。"
	_style_hint(deletion_notice)
	deletion_notice.add_theme_color_override("font_color", Color("c6b49b"))
	feeding.add_child(deletion_notice)
	_toggle(feeding, "饥饿时自动打开锅", auto_open_bowl)
	var folders := HBoxContainer.new()
	folders.add_theme_constant_override("separation", 10)
	feeding.add_child(folders)
	bowl_button.text = "打开饭盆文件夹"
	stomach_button.text = "打开猫的胃袋"
	for button in [bowl_button, stomach_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		folders.add_child(button)
	bowl_button.pressed.connect(func(): open_bowl.emit())
	stomach_button.pressed.connect(func(): open_stomach.emit())
	_detail(feeding, "投喂与消化规则", "拖入的文件会移动到饭盆；按放入先后取食，吃完移入胃袋。\n吃饱后休息，饱食度低于 50% 且下一份能放下才恢复；锅靠近才取食。未开锅时会请求打开。\n若锅内每份文件都大于吃饱容量，饱食度低于 50% 时也能按顺序吃一份；吃后显示 100%，按文件实际大小计入胃袋并等待消化。\n汤量按文件总大小分段增加，小文件也有反馈；满锅后仍能放入文件。\n消化从移入胃袋开始按现实时间计算；到期永久删除，不进回收站。退出期间到期的文件下次启动处理，修改消化时间也影响胃袋内已有文件。")
	var ai := _page(stack, "AI 陪伴", "连接 AI，和猫咪聊聊日常。")
	ai.add_theme_constant_override("separation", 8)
	ai.add_child(ai_panel)
	ai_panel.chat_requested.connect(func(): ai_chat_requested.emit())
	ai_panel.memory_requested.connect(func(): ai_memory_requested.emit())
	var about := _page(stack, "关于", "一个更有陪伴感的实用小桌宠。")
	_label(about, "Dolikepet  " + AppUpdate.VERSION, 20)
	_label(about, AppUpdate.RELEASE_NAME, 14, true)
	about.add_child(HSeparator.new())
	_style_hint(update_status)
	about.add_child(update_status)
	update_progress.custom_minimum_size.y = 8
	update_progress.show_percentage = false
	about.add_child(update_progress)
	var update_actions := HBoxContainer.new()
	update_actions.add_theme_constant_override("separation", 8)
	about.add_child(update_actions)
	update_button.text = "检查更新"
	update_button.pressed.connect(updater.check)
	update_actions.add_child(update_button)
	download_button.pressed.connect(func():
		if updater.has_download(): OS.shell_open(updater.verified_path.get_base_dir())
		else: updater.download_update())
	update_actions.add_child(download_button)
	var releases_button := Button.new()
	releases_button.text = "GitHub 发布页  ↗"
	releases_button.pressed.connect(func(): OS.shell_open(AppUpdate.REPOSITORY + "/releases"))
	about.add_child(releases_button)
	_detail(about, "自动更新说明", "启动后自动检查，有新版本时联网下载。猫咪会分别提醒发现新版本和下载完成。\n下载后校验完整性，不会自动安装；更新时保留饭盆、胃袋和个人设置。")
	add_child(updater)
	updater.changed.connect(_update_version_status)
	_update_version_status()
	main.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	main.add_child(buttons)
	_style_hint(footer_hint)
	footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(footer_hint)
	cancel_button.text = "取消"
	save_button.text = "保存"
	for button in [cancel_button, save_button]:
		button.custom_minimum_size = Vector2(76, 36)
		buttons.add_child(button)
	save_button.add_theme_stylebox_override("normal", SettingsTheme.box(Color("654592")))
	save_button.add_theme_stylebox_override("hover", SettingsTheme.box(Color("7956a8")))
	close_requested.connect(hide)
	cancel_button.pressed.connect(hide)
	visibility_changed.connect(func():
		if not visible: ai_panel.discard_secret_draft())
	save_button.pressed.connect(_save)
	automatic.toggled.connect(func(_value: bool): _update_controls())
	sleep_enabled.toggled.connect(func(_value: bool): _update_sleep_controls())
	sleep_frequency.value_changed.connect(func(_value: float): _update_sleep_controls())
	for field in _sleep_fields():
		field.value_changed.connect(func(_value: float): _update_sleep_controls())
	for field in _fields():
		field.value_changed.connect(func(_value: float): _update_controls())
	for field in _fields() + _sleep_fields() + [bowl_capacity, stomach_capacity, digestion_hours]:
		field.get_line_edit().text_changed.connect(func(_text: String): pending_fields[field] = true)
	_select_page(0)

func _margin(parent: Node, horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, horizontal)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, vertical)
	parent.add_child(margin)
	return margin

func _label(parent: Node, text: String, font_size: int = 14, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if muted: label.add_theme_color_override("font_color", SettingsTheme.MUTED)
	parent.add_child(label)
	return label

func _style_hint(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SettingsTheme.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _page(parent: Control, heading: String, subtitle: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	pages.append(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	scroll.add_child(layout)
	_label(layout, heading, 24)
	_label(layout, subtitle, 12, true)
	layout.add_child(HSeparator.new())
	return layout

func _row(parent: VBoxContainer, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 32
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_label(row, caption).custom_minimum_size.x = 136
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 8)
	row.add_child(controls)
	return controls

func _toggle(parent: VBoxContainer, caption: String, control: CheckButton) -> void:
	control.tooltip_text = caption
	_row(parent, caption).add_child(control)

func _detail(parent: VBoxContainer, caption: String, text: String, tracked: bool = true) -> Button:
	var button := Button.new()
	button.text = "▸  " + caption
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.flat = true
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", SettingsTheme.MUTED)
	parent.add_child(button)
	if tracked: details.append(button)
	var explanation := Label.new()
	explanation.text = text
	_style_hint(explanation)
	explanation.visible = false
	parent.add_child(explanation)
	button.toggled.connect(func(expanded: bool):
		explanation.visible = expanded
		button.text = ("▾  " if expanded else "▸  ") + caption)
	return button

func _add_sleep_controls(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	_label(parent, "猫猫作息", 17)
	_toggle(parent, "自动睡觉", sleep_enabled)
	var clock_row := _row(parent, "睡觉时间")
	clock_row.add_theme_constant_override("separation", 4)
	_add_sleep_clock(clock_row, sleep_start_hour, sleep_start_minute)
	_label(clock_row, "—", 12, true)
	_add_sleep_clock(clock_row, sleep_end_hour, sleep_end_minute)
	_style_hint(sleep_period_hint)
	parent.add_child(sleep_period_hint)
	var frequency_row := _row(parent, "日常小睡频率")
	sleep_frequency.min_value = 0; sleep_frequency.max_value = 2
	sleep_frequency.step = 1; sleep_frequency.rounded = true
	sleep_frequency.tick_count = 3; sleep_frequency.ticks_on_borders = true
	sleep_frequency.scrollable = false
	sleep_frequency.custom_minimum_size = Vector2(130, 26)
	sleep_frequency.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sleep_frequency.tooltip_text = "少 / 适中 / 多；仅调整睡觉时段以外的小睡概率"
	frequency_row.add_child(sleep_frequency)
	sleep_frequency_label.custom_minimum_size.x = 32
	sleep_frequency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sleep_frequency_label.add_theme_color_override("font_color", SettingsTheme.ACCENT)
	frequency_row.add_child(sleep_frequency_label)
	sleep_detail = _detail(parent, "入睡与叫醒规则", "日常无互动 3 分钟后，每分钟按频率有 10% / 20% / 40% 概率小睡；随机睡 3～8 分钟后自然醒。\n睡觉时段内，无互动 30 秒后每 30 秒有 60% 概率入睡；没人叫醒就持续睡，时段结束后自然醒。开始与结束时间相同表示全天。\n点击、拖拽、缩放或主动聊天会叫醒，之后至少清醒 2 分钟；鼠标经过或在其他软件工作不会叫醒。\n聊天、设置、进食、小游戏和物理动作期间避让。睡着后暂停走动、取食和主动问候；自动坐下遵循睡眠状态，不会把熟睡的猫猫唤醒。", false)

func _add_sleep_clock(parent: HBoxContainer, hours: SpinBox, minutes: SpinBox) -> void:
	for field in [hours, minutes]:
		field.min_value = 0; field.max_value = 23 if field == hours else 59
		field.step = 1; field.custom_minimum_size.x = 50
		field.select_all_on_focus = true
		field.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
		field.get_line_edit().add_theme_constant_override("minimum_character_width", 2)
		field.get_line_edit().add_theme_stylebox_override("normal", SettingsTheme.box(Color("25232b"), 7, 5))
		parent.add_child(field)
		if field == hours: _label(parent, ":", 14, true)

func _sleep_fields() -> Array[SpinBox]:
	return [sleep_start_hour, sleep_start_minute, sleep_end_hour, sleep_end_minute]

static func _sleep_number(value: Variant, fallback: int, maximum: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)): return fallback
	return clampi(int(value), 0, maximum)

func _load_sleep_draft(value: Variant) -> void:
	var saved: Dictionary = value if value is Dictionary else {}
	var enabled_value: Variant = saved.get("enabled", true)
	sleep_enabled.set_pressed_no_signal(enabled_value if enabled_value is bool else true)
	var start := _sleep_number(saved.get("start_minute", 1380), 1380, 1439)
	var end := _sleep_number(saved.get("end_minute", 480), 480, 1439)
	sleep_start_hour.set_value_no_signal(start / 60)
	sleep_start_minute.set_value_no_signal(start % 60)
	sleep_end_hour.set_value_no_signal(end / 60)
	sleep_end_minute.set_value_no_signal(end % 60)
	sleep_frequency.set_value_no_signal(_sleep_number(saved.get("frequency", 1), 1, 2))
	_update_sleep_controls()

func _sleep_draft() -> Dictionary:
	return {"enabled": sleep_enabled.button_pressed,
		"start_minute": int(sleep_start_hour.value)*60 + int(sleep_start_minute.value),
		"end_minute": int(sleep_end_hour.value)*60 + int(sleep_end_minute.value),
		"frequency": int(sleep_frequency.value)}

func _update_sleep_controls() -> void:
	var draft := _sleep_draft()
	sleep_frequency.editable = sleep_enabled.button_pressed
	sleep_frequency.modulate.a = 1.0 if sleep_enabled.button_pressed else 0.5
	sleep_frequency_label.text = ["少", "适中", "多"][clampi(int(sleep_frequency.value), 0, 2)]
	for field in _sleep_fields():
		field.editable = sleep_enabled.button_pressed
		field.modulate.a = 1.0 if sleep_enabled.button_pressed else 0.5
	sleep_period_hint.text = "按本机时间 · 全天睡眠时段" if draft.start_minute == draft.end_minute else ("按本机时间 · 跨午夜至次日" if draft.start_minute > draft.end_minute else "按本机时间 · 当日时段")
	if not sleep_enabled.button_pressed: sleep_period_hint.text = "自动睡觉已关闭；仍可从右键菜单手动睡觉。"
	_format_sleep_time.call_deferred()

func _format_sleep_time() -> void:
	for field in _sleep_fields():
		if not field.get_line_edit().has_focus(): field.get_line_edit().text = "%02d" % int(field.value)

func _capacity_row(parent: VBoxContainer, caption: String, field: SpinBox, unit: OptionButton) -> void:
	var row := _row(parent, caption)
	field.min_value = 0.01
	field.max_value = 1048576
	field.step = 0.01
	field.custom_minimum_size.x = 120
	row.add_child(field)
	unit.add_item("MB")
	unit.add_item("GB")
	unit.custom_minimum_size.x = 65
	row.add_child(unit)
	unit.item_selected.connect(func(_index: int): field.max_value = 1024 if unit.selected == 1 else 1048576)

func _select_page(index: int) -> void:
	current_page = index
	for i in pages.size():
		pages[i].visible = i == index
		navigation[i].set_pressed_no_signal(i == index)

func _select_activity(index: int) -> void:
	activity_index = index
	for i in activity_buttons.size(): activity_buttons[i].set_pressed_no_signal(i == index)
	_update_controls()

func _choose_size(pixels: int) -> void:
	size_pixels = Sizes.nearest(pixels)
	var index := Sizes.PIXELS.find(size_pixels)
	size_slider.set_value_no_signal(index)
	size_value.text = "%d%%" % Sizes.PERCENTS[index]

func _fields() -> Array[SpinBox]:
	return [minimum_minutes, minimum_seconds, maximum_minutes, maximum_seconds]

func _update_version_status() -> void:
	update_status.text = updater.message
	update_button.disabled = updater.busy()
	update_progress.visible = updater.state in ["downloading","verifying"]
	update_progress.value = updater.progress*100.0
	download_button.visible = updater.has_download() or updater.state in ["available","download_error","ready"]
	download_button.text = "打开下载文件夹" if updater.has_download() else ("重试下载" if updater.state == "download_error" else "立即下载新版本")

func _duration_row(layout: VBoxContainer, label: String, minutes: SpinBox, seconds: SpinBox) -> void:
	var row := _row(layout, label)
	for field in [minutes, seconds]:
		field.min_value = 0
		field.max_value = 60 if field == minutes else 59
		field.step = 1
		field.suffix = "分" if field == minutes else "秒"
		field.custom_minimum_size.x = 85
		row.add_child(field)

func show_settings(enabled: bool, minimum: float, maximum: float, roaming_mode: String = "calm", auto_fall_enabled: bool = true, full_bytes: int = BowlCapacity.DEFAULT,
		stomach_bytes: int = BowlCapacity.DEFAULT, hours: float = 6.0, auto_open: bool = false, used: int = 0, resting: bool = false, common: Dictionary = {}) -> void:
	if visible:
		# An open/minimized page owns an unsaved draft; reopening only restores it.
		mode = Window.MODE_WINDOWED
		grab_focus()
		return
	pending_fields.clear()
	ai_panel.load_draft(ai_service)
	_choose_size(int(common.get("size", Sizes.BASE)))
	gaze.set_pressed_no_signal(bool(common.get("gaze", true)))
	topmost.set_pressed_no_signal(bool(common.get("topmost", true)))
	_load_sleep_draft(common.get("sleep", {}))
	stomach_unit.select(1 if stomach_bytes>=BowlCapacity.GB else 0)
	stomach_capacity.max_value = 1024 if stomach_unit.selected==1 else 1048576
	stomach_capacity.value = float(stomach_bytes)/(BowlCapacity.GB if stomach_unit.selected==1 else BowlCapacity.MB)
	digestion_hours.value = hours
	auto_open_bowl.set_pressed_no_signal(auto_open)
	update_stomach_usage(used,stomach_bytes,resting)
	var bytes := BowlCapacity.sanitize(full_bytes)
	bowl_unit.select(1 if bytes >= BowlCapacity.GB else 0)
	bowl_capacity.max_value = 1024 if bowl_unit.selected == 1 else 1048576
	bowl_capacity.value = float(bytes)/(BowlCapacity.GB if bowl_unit.selected == 1 else BowlCapacity.MB)
	_select_activity(maxi(0, Roaming.MODES.find(roaming_mode)))
	automatic.set_pressed_no_signal(enabled)
	auto_fall.set_pressed_no_signal(auto_fall_enabled)
	minimum_minutes.value = floor(minimum / 60.0)
	minimum_seconds.value = int(round(minimum)) % 60
	maximum_minutes.value = floor(maximum / 60.0)
	maximum_seconds.value = int(round(maximum)) % 60
	_update_controls()
	mode = Window.MODE_WINDOWED
	# Hidden native Windows have no OS handle yet; derive the center from the
	# host's monitor before showing instead of querying this hidden window.
	var area := DisplayServer.screen_get_usable_rect(get_parent().get_window().current_screen)
	position = area.position+(area.size-size)/2
	show()
	grab_focus()
	navigation[current_page].grab_focus()

func _update_controls() -> void:
	activity_hint.text = [
		"时常左右走动，偶尔坐下短暂休息。",
		"大部分时间待着或坐下休息，偶尔起来走一段。",
		"不自主走动，只按下方设置坐下休息。",
	][activity_index]
	sit_options.visible = automatic.button_pressed
	for field in _fields():
		field.editable = automatic.button_pressed
		field.modulate.a = 1.0 if automatic.button_pressed else 0.5
	var minimum := minimum_minutes.value * 60 + minimum_seconds.value
	var maximum := maximum_minutes.value * 60 + maximum_seconds.value
	var error := ""
	if minimum < IdleSitting.MIN_SECONDS or maximum < IdleSitting.MIN_SECONDS:
		error = "最短和最长等待都不能少于 5 秒。"
	elif minimum > IdleSitting.MAX_SECONDS or maximum > IdleSitting.MAX_SECONDS:
		error = "等待时长不能超过 60 分钟。"
	elif maximum < minimum:
		error = "最长等待不能短于最短等待。"
	if not automatic.button_pressed: error = ""
	save_button.disabled = not error.is_empty()
	footer_hint.text = "请检查「活动」页的等待时间" if not error.is_empty() else "保存后生效"
	footer_hint.add_theme_color_override("font_color", Color("ffb3ab") if not error.is_empty() else SettingsTheme.MUTED)
	delay_hint.text = error if not error.is_empty() else "范围可设置为 5 秒～60 分钟；保存后重新计时。"
	delay_hint.modulate = Color("#ffb3ab") if not error.is_empty() else Color.WHITE

func _save() -> void:
	# Hidden SpinBoxes defer their displayed text. Only commit actual user edits;
	# applying every field would overwrite loaded values on unvisited pages.
	for field in pending_fields:
		field.apply()
	pending_fields.clear()
	_update_controls()
	if save_button.disabled:
		return
	if ai_panel.commit_draft() != OK:
		_select_page(3)
		footer_hint.text = "AI 设置未保存，请检查提示"
		footer_hint.add_theme_color_override("font_color", Color("ffb3ab"))
		return
	common_settings_saved.emit(size_pixels, gaze.button_pressed, topmost.button_pressed)
	settings_saved.emit(automatic.button_pressed,
		minimum_minutes.value * 60 + minimum_seconds.value,
		maximum_minutes.value * 60 + maximum_seconds.value,
		Roaming.MODES[activity_index], auto_fall.button_pressed)
	bowl_settings_saved.emit(BowlCapacity.sanitize(roundi(bowl_capacity.value * (BowlCapacity.GB if bowl_unit.selected == 1 else BowlCapacity.MB))))
	stomach_settings_saved.emit(BowlCapacity.sanitize(roundi(stomach_capacity.value*(BowlCapacity.GB if stomach_unit.selected==1 else BowlCapacity.MB))),digestion_hours.value,auto_open_bowl.button_pressed)
	sleep_settings_saved.emit(_sleep_draft())
	hide()

func update_stomach_usage(used: int, capacity: int, resting: bool) -> void:
	fullness.value = 100.0*used/maxi(1,capacity)
	fullness_label.text = "%.1f%%" % fullness.value
	stomach_usage.text = "%s / %s · %s" % [String.humanize_size(used),String.humanize_size(capacity),
		"吃饱休息中" if resting else "等待靠近的饭盆"]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		set_input_as_handled()
