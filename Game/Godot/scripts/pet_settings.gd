extends Window
## A native settings window; drafts are applied only with Save.

signal settings_saved(auto_sit_enabled: bool, minimum_seconds: float, maximum_seconds: float, roaming_mode: String, auto_fall_enabled: bool)
signal bowl_settings_saved(capacity_bytes: int)
signal stomach_settings_saved(capacity_bytes: int, hours: float, auto_open: bool)
signal open_stomach
signal open_bowl
const BowlCapacity = preload("res://scripts/bowl_capacity.gd")
const IdleSitting = preload("res://scripts/idle_sitting.gd")
const Roaming = preload("res://scripts/roaming.gd")
const AppUpdate = preload("res://scripts/app_update.gd")
var updater := AppUpdate.new()
var update_button := Button.new()
var download_button := Button.new()
var update_status := Label.new()

var activity := OptionButton.new()
var activity_hint := Label.new()
var automatic := CheckButton.new()
var auto_fall := CheckButton.new()
var minimum_minutes := SpinBox.new()
var minimum_seconds := SpinBox.new()
var maximum_minutes := SpinBox.new()
var maximum_seconds := SpinBox.new()
var delay_hint := Label.new()
var save_button := Button.new()
var cancel_button := Button.new()
var bowl_capacity := SpinBox.new()
var bowl_unit := OptionButton.new()
var bowl_hint := Label.new()
var bowl_button := Button.new()
var stomach_capacity := SpinBox.new()
var stomach_unit := OptionButton.new()
var digestion_hours := SpinBox.new()
var auto_open_bowl := CheckButton.new()
var stomach_usage := Label.new()
var stomach_button := Button.new()

func _init() -> void:
	title = "桌宠设置"
	size = Vector2i(510, 760)
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
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	margin.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	scroll.add_child(layout)
	var heading := Label.new()
	heading.text = "日常活动"
	heading.add_theme_font_size_override("font_size", 22)
	layout.add_child(heading)
	activity.add_item("常走动")
	activity.add_item("多待着")
	activity.add_item("不乱动")
	activity.custom_minimum_size.y = 36
	layout.add_child(activity)
	activity_hint.add_theme_font_size_override("font_size", 14)
	activity_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(activity_hint)
	auto_fall.text = "离开底边时自动下落"
	layout.add_child(auto_fall)
	var fall_hint := Label.new()
	fall_hint.text = "松手保留惯性，碰到屏幕侧边或顶部会反弹。\n开启后受重力下落；关闭后缓慢停住，可在空中重新抓取。"
	fall_hint.add_theme_font_size_override("font_size", 13)
	fall_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(fall_hint)
	automatic.text = "无互动后自动坐下休息"
	layout.add_child(automatic)
	_duration_row(layout, "最短等待", minimum_minutes, minimum_seconds)
	_duration_row(layout, "最长等待", maximum_minutes, maximum_seconds)
	var random_hint := Label.new()
	random_hint.text = "每轮在此范围内随机等待一次；互动后重新抽取。\n最短与最长相同，则按固定时长等待。"
	random_hint.add_theme_font_size_override("font_size", 13)
	random_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(random_hint)
	delay_hint.add_theme_font_size_override("font_size", 13)
	delay_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(delay_hint)
	var help := Label.new()
	help.text = "走动前先回到当前屏幕底部，不会走出屏幕。\n点击、拖动、缩放或打开菜单会暂停走动。\n自动坐下后，点击会起身；手动坐下则保持坐姿。"
	help.add_theme_font_size_override("font_size", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(help)
	var bowl_heading := Label.new()
	bowl_heading.text = "猫的饭盆"
	bowl_heading.add_theme_font_size_override("font_size", 20)
	layout.add_child(bowl_heading)
	var bowl_row := HBoxContainer.new()
	layout.add_child(bowl_row)
	var bowl_caption := Label.new()
	bowl_caption.text = "满锅容量"
	bowl_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bowl_row.add_child(bowl_caption)
	bowl_capacity.min_value = 1
	bowl_capacity.max_value = 1048576
	bowl_capacity.step = 0.01
	bowl_capacity.custom_minimum_size.x = 140
	bowl_row.add_child(bowl_capacity)
	bowl_unit.add_item("MB")
	bowl_unit.add_item("GB")
	bowl_row.add_child(bowl_unit)
	bowl_hint.text = "按饭盆内文件总大小分段增加汤量，小文件也有反馈。\n达到容量后显示满锅，仍可继续放入文件。\n拖入文件会移动至饭盆；吃完后移入猫的胃袋。"
	bowl_hint.add_theme_font_size_override("font_size", 13)
	bowl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(bowl_hint)
	bowl_button.text = "打开饭盆文件夹"
	bowl_button.pressed.connect(func(): open_bowl.emit())
	layout.add_child(bowl_button)
	bowl_unit.item_selected.connect(func(_index: int):
		bowl_capacity.max_value = 1024 if bowl_unit.selected == 1 else 1048576)
	var stomach_heading := Label.new()
	stomach_heading.text = "猫的胃袋"
	stomach_heading.add_theme_font_size_override("font_size",20)
	layout.add_child(stomach_heading)
	stomach_usage.add_theme_font_size_override("font_size",14)
	stomach_usage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(stomach_usage)
	var stomach_row := HBoxContainer.new()
	layout.add_child(stomach_row)
	var stomach_caption := Label.new()
	stomach_caption.text = "吃饱容量"
	stomach_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stomach_row.add_child(stomach_caption)
	stomach_capacity.min_value = 0.01
	stomach_capacity.max_value = 1048576
	stomach_capacity.step = 0.01
	stomach_capacity.custom_minimum_size.x = 140
	stomach_row.add_child(stomach_capacity)
	stomach_unit.add_item("MB"); stomach_unit.add_item("GB")
	stomach_row.add_child(stomach_unit)
	stomach_unit.item_selected.connect(func(_index: int):
		stomach_capacity.max_value = 1024 if stomach_unit.selected==1 else 1048576)
	var hours_row := HBoxContainer.new()
	layout.add_child(hours_row)
	var hours_caption := Label.new()
	hours_caption.text = "每份食物的消化时间"
	hours_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hours_row.add_child(hours_caption)
	digestion_hours.min_value = 0.01; digestion_hours.max_value = 8760
	digestion_hours.step = 0.01; digestion_hours.suffix = "小时"
	digestion_hours.custom_minimum_size.x = 160
	hours_row.add_child(digestion_hours)
	auto_open_bowl.text = "桌宠自动打开锅"
	layout.add_child(auto_open_bowl)
	var stomach_hint := Label.new()
	stomach_hint.text = "吃饱后休息，饱食度低于 50% 才恢复进食；锅靠近才取食。\n未开锅时会用台词请求；勾选后，饥饿时自动显示坩埚。\n文件按放入饭盆的先后顺序吃；单份放不下时等待。\n消化从移入胃袋时开始，按现实时间计算，关机时间也计入。\n到期文件永久删除，不进回收站；退出期间到期的文件下次启动处理。\n修改消化时间会应用到胃袋内已有文件。"
	stomach_hint.add_theme_font_size_override("font_size",13)
	stomach_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(stomach_hint)
	stomach_button.text = "打开猫的胃袋"
	stomach_button.pressed.connect(func(): open_stomach.emit())
	layout.add_child(stomach_button)
	add_child(updater)
	var version_heading := Label.new()
	version_heading.text = "版本与更新 · " + AppUpdate.VERSION + " · " + AppUpdate.RELEASE_NAME
	version_heading.add_theme_font_size_override("font_size", 20)
	layout.add_child(version_heading)
	update_status.add_theme_font_size_override("font_size", 13)
	update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(update_status)
	update_button.text = "检查更新"
	update_button.pressed.connect(updater.check)
	layout.add_child(update_button)
	download_button.text = "查看并下载新版本"
	download_button.pressed.connect(func():
		if not updater.release_url.is_empty(): OS.shell_open(updater.release_url))
	layout.add_child(download_button)
	var releases_button := Button.new()
	releases_button.text = "GitHub 发布页"
	releases_button.pressed.connect(func(): OS.shell_open(AppUpdate.REPOSITORY + "/releases"))
	layout.add_child(releases_button)
	updater.changed.connect(_update_version_status)
	_update_version_status()
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	cancel_button.text = "取消"
	cancel_button.custom_minimum_size = Vector2(90, 34)
	save_button.text = "保存"
	save_button.custom_minimum_size = Vector2(90, 34)
	buttons.add_child(cancel_button)
	buttons.add_child(save_button)
	close_requested.connect(hide)
	cancel_button.pressed.connect(hide)
	save_button.pressed.connect(_save)
	automatic.toggled.connect(func(_value: bool): _update_controls())
	activity.item_selected.connect(func(_index: int): _update_controls())
	for field in _fields():
		field.value_changed.connect(func(_value: float): _update_controls())

func _fields() -> Array[SpinBox]:
	return [minimum_minutes, minimum_seconds, maximum_minutes, maximum_seconds]

func _update_version_status() -> void:
	update_status.text = updater.message
	update_button.disabled = updater.state == "checking"
	download_button.visible = updater.state == "available"

func _duration_row(layout: VBoxContainer, label: String, minutes: SpinBox, seconds: SpinBox) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	layout.add_child(row)
	var caption := Label.new()
	caption.text = label
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	for field in [minutes, seconds]:
		field.min_value = 0
		field.max_value = 60 if field == minutes else 59
		field.step = 1
		field.suffix = "分" if field == minutes else "秒"
		field.custom_minimum_size.x = 110
		row.add_child(field)

func show_settings(enabled: bool, minimum: float, maximum: float, roaming_mode: String = "calm", auto_fall_enabled: bool = true, full_bytes: int = BowlCapacity.DEFAULT,
		stomach_bytes: int = BowlCapacity.DEFAULT, hours: float = 6.0, auto_open: bool = false, used: int = 0, resting: bool = false) -> void:
	if visible:
		# An open/minimized page owns an unsaved draft; reopening only restores it.
		mode = Window.MODE_WINDOWED
		grab_focus()
		return
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
	activity.select(maxi(0, Roaming.MODES.find(roaming_mode)))
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
	automatic.grab_focus()

func _update_controls() -> void:
	activity_hint.text = [
		"时常左右走动，偶尔坐下短暂休息。",
		"大部分时间待着或坐下休息，偶尔起来走一段。",
		"不自主走动，只按下方设置坐下休息。",
	][activity.selected]
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
	save_button.disabled = not error.is_empty()
	delay_hint.text = error if not error.is_empty() else "范围可设置为 5 秒～60 分钟；保存后重新计时。"
	delay_hint.modulate = Color("#ffb3ab") if not error.is_empty() else Color.WHITE

func _save() -> void:
	bowl_capacity.apply()
	stomach_capacity.apply(); digestion_hours.apply()
	# Commit text typed into the SpinBox even if focus has not left its field.
	for field in _fields():
		field.apply()
	_update_controls()
	if save_button.disabled:
		return
	settings_saved.emit(automatic.button_pressed,
		minimum_minutes.value * 60 + minimum_seconds.value,
		maximum_minutes.value * 60 + maximum_seconds.value,
		Roaming.MODES[activity.selected], auto_fall.button_pressed)
	bowl_settings_saved.emit(BowlCapacity.sanitize(roundi(bowl_capacity.value * (BowlCapacity.GB if bowl_unit.selected == 1 else BowlCapacity.MB))))
	stomach_settings_saved.emit(BowlCapacity.sanitize(roundi(stomach_capacity.value*(BowlCapacity.GB if stomach_unit.selected==1 else BowlCapacity.MB))),digestion_hours.value,auto_open_bowl.button_pressed)
	hide()

func update_stomach_usage(used: int, capacity: int, resting: bool) -> void:
	stomach_usage.text = "饱食度 %.1f%% · %s / %s\n%s" % [100.0*used/maxi(1,capacity),String.humanize_size(used),String.humanize_size(capacity),
		"吃饱休息中，低于 50% 且下一份能放下时恢复" if resting else "可以进食，等待靠近的饭盆"]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		set_input_as_handled()
