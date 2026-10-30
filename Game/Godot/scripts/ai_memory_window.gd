extends Window
## Local memory groups. Stable IDs keep background merges from editing the wrong row.

const SettingsTheme = preload("res://scripts/settings_theme.gd")
const TIERS := ["recent", "long", "fixed"]
var service: Node
var tabs := TabBar.new()
var items := ItemList.new()
var editor := TextEdit.new()
var source_label := RichTextLabel.new()
var status_label := Label.new()
var privacy_label := Label.new()
var group_hint := Label.new()
var add := Button.new()
var save := Button.new()
var remove := Button.new()
var pin := Button.new()
var selected := -1
var selected_id := ""
var _entries: Array = []
var _visible_entries: Array = []
var _drafts: Dictionary = {}
var _editor_original := ""

func _init() -> void:
	title = "猫咪的记忆"
	size = Vector2i(510, 640)
	min_size = Vector2i(420, 560)
	visible = false
	transient = false
	exclusive = false
	borderless = false
	transparent = false
	transparent_bg = false

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.theme = SettingsTheme.make()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	margin.add_child(layout)
	var title_label := Label.new()
	title_label.text = "猫猫记住的事"
	title_label.add_theme_font_size_override("font_size", 22)
	layout.add_child(title_label)
	_hint(privacy_label)
	layout.add_child(privacy_label)
	for caption in ["近期", "长期", "固定"]: tabs.add_tab(caption)
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.tab_changed.connect(_change_tab)
	layout.add_child(tabs)
	_hint(group_hint)
	layout.add_child(group_hint)
	items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.custom_minimum_size.y = 112
	items.add_theme_stylebox_override("panel", SettingsTheme.box(Color("1b1921")))
	items.add_theme_color_override("font_color", SettingsTheme.TEXT)
	items.item_selected.connect(_select_item)
	layout.add_child(items)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	layout.add_child(tools)
	add.text = "新增固定记忆"
	add.pressed.connect(_new_memory)
	tools.add_child(add)
	pin.text = "固定所选"
	pin.pressed.connect(_pin_memory)
	tools.add_child(pin)
	remove.text = "忘记所选"
	remove.pressed.connect(_delete_memory)
	tools.add_child(remove)
	source_label.bbcode_enabled = false
	source_label.selection_enabled = true
	source_label.custom_minimum_size.y = 68
	source_label.add_theme_font_size_override("normal_font_size", 12)
	source_label.add_theme_color_override("default_color", SettingsTheme.MUTED)
	source_label.text = "选中记忆，可以查看来源与最近提及的时间。"
	layout.add_child(source_label)
	editor.placeholder_text = "例如：我喜欢简短温柔的回复。手动添加的记忆不会自动遗忘。"
	editor.custom_minimum_size.y = 100
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.add_theme_stylebox_override("normal", SettingsTheme.box(Color("25232b")))
	var editor_focus := SettingsTheme.box(Color.TRANSPARENT)
	editor_focus.set_border_width_all(1)
	editor_focus.border_color = SettingsTheme.ACCENT
	editor.add_theme_stylebox_override("focus", editor_focus)
	editor.add_theme_color_override("font_color", SettingsTheme.TEXT)
	editor.add_theme_color_override("caret_color", SettingsTheme.ACCENT)
	editor.text_changed.connect(_refresh_controls)
	layout.add_child(editor)
	_hint(status_label)
	layout.add_child(status_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(actions)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(hide)
	actions.add_child(close)
	save.text = "添加固定记忆"
	save.pressed.connect(_save_memory)
	save.add_theme_stylebox_override("normal", SettingsTheme.box(Color("654592")))
	actions.add_child(save)
	close_requested.connect(hide)
	_refresh()

func _hint(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", SettingsTheme.MUTED)

func setup(value: Node) -> void:
	if is_instance_valid(service):
		if service.memories_changed.is_connected(_refresh): service.memories_changed.disconnect(_refresh)
		if service.state_changed.is_connected(_refresh_controls): service.state_changed.disconnect(_refresh_controls)
	service = value
	if is_instance_valid(service):
		service.memories_changed.connect(_refresh)
		service.state_changed.connect(_refresh_controls)
	if is_node_ready(): _refresh()

func open_panel() -> void:
	if not visible:
		var area := DisplayServer.screen_get_usable_rect(get_parent().get_window().current_screen)
		position = area.position + (area.size - size) / 2
	mode = Window.MODE_WINDOWED
	show()
	grab_focus()
	_refresh()

func _all_entries() -> Array:
	if not is_instance_valid(service): return []
	if service.has_method("memory_entries"): return service.memory_entries()
	# Preserve compatibility with the previous explicit-memory service and test fixtures.
	var result: Array = []
	for index in service.memories.size():
		result.append({"id":"legacy_" + str(index), "text":str(service.memories[index]), "tier":"fixed", "legacy_index":index})
	return result

func _entry_by_id(id: String) -> Dictionary:
	for entry in _entries:
		if str(entry.id) == id: return entry
	return {}

func _refresh() -> void:
	if not is_node_ready(): return
	_entries = _all_entries()
	_visible_entries.clear()
	items.clear()
	selected = -1
	var counts := {"recent":0, "long":0, "fixed":0}
	for entry in _entries:
		var tier := str(entry.get("tier", "fixed"))
		if counts.has(tier): counts[tier] += 1
		if tier != TIERS[tabs.current_tab]: continue
		_visible_entries.append(entry)
		var text := str(entry.text).replace("\n", "  ")
		if bool(entry.get("faded", false)): text = "渐渐淡忘 · " + text
		var index := items.add_item(text)
		items.set_item_tooltip(index, str(entry.text))
		if str(entry.id) == selected_id:
			selected = index
			items.select(index)
	for i in TIERS.size(): tabs.set_tab_title(i, ["近期", "长期", "固定"][i] + "  " + str(counts[TIERS[i]]))
	group_hint.text = ["日常聊天记下的事，会随时间淡忘。", "在不同日子反复提及，猫猫记得更牢。", "你指定保留的内容，不会自动遗忘。"][tabs.current_tab]
	if not selected_id.is_empty():
		var selected_entry := _entry_by_id(selected_id)
		if not selected_entry.is_empty() and editor.text == _editor_original:
			_editor_original = str(selected_entry.text)
			editor.text = _editor_original
		_show_source(selected_entry)
	_refresh_controls()

func _refresh_controls() -> void:
	if not is_node_ready(): return
	var available := is_instance_valid(service)
	var enabled: bool = available and bool(service.settings.get("memory_enabled", true))
	var automatic: bool = available and bool(service.settings.get("auto_memory_enabled", true))
	privacy_label.text = ("日常聊天会自动整理；记忆保存在本机，启用时随对话发送。" if automatic else "自动记忆已关闭；已有记忆保存在本机，启用时随对话发送。") if enabled else "目前未启用记忆：内容保存在本机，不会随对话发送，也不会自动整理。"
	var entry := _entry_by_id(selected_id)
	var missing := not selected_id.is_empty() and entry.is_empty()
	save.text = "保存修改" if not selected_id.is_empty() else "添加固定记忆"
	save.disabled = not available or editor.text.strip_edges().is_empty() or missing
	remove.disabled = not available or entry.is_empty()
	pin.disabled = not available or entry.is_empty() or str(entry.get("tier", "")) == "fixed"
	add.disabled = not available
	if missing: status_label.text = "这条记忆已被移除；编辑草稿仍保留，请复制后另存。"

func _change_tab(_index: int) -> void:
	# Browsing another group must not discard an unfinished edit.
	_refresh()

func _select_item(index: int) -> void:
	if not is_instance_valid(service) or index < 0 or index >= _visible_entries.size(): return
	_keep_draft()
	var entry: Dictionary = _visible_entries[index]
	selected = index
	selected_id = str(entry.id)
	_editor_original = str(entry.text)
	editor.text = str(_drafts.get(selected_id, entry.text))
	status_label.text = "修改后点击「保存修改」生效。"
	_show_source(entry)
	_refresh_controls()

func _show_source(entry: Dictionary) -> void:
	if entry.is_empty():
		source_label.text = "原记忆已不在列表中。"
		return
	var tier := str(entry.get("tier", "fixed"))
	var lines: Array[String] = []
	lines.append("固定保留" if tier == "fixed" else ("长期记忆" if tier == "long" else "近期记忆"))
	var created := int(entry.get("created_at", 0))
	var last_seen := int(entry.get("last_seen", 0))
	if created > 0: lines.append("记下于 " + _date(created) + (" · 最近提及 " + _date(last_seen) if last_seen > 0 else ""))
	var sources: Variant = entry.get("sources", [])
	if sources is Array:
		for source in sources:
			if not source is Dictionary or str(source.get("quote", "")).is_empty(): continue
			lines.append(_date(int(source.get("at", 0))) + "  “" + str(source.quote) + "”")
	if lines.size() <= 2 and tier == "fixed" and (not sources is Array or sources.is_empty()): lines.append("由你手动保存或固定。")
	source_label.text = "\n".join(lines)
	source_label.scroll_to_line(0)

func _date(timestamp: int) -> String:
	if timestamp <= 0: return ""
	return Time.get_datetime_string_from_unix_time(timestamp + int(Time.get_time_zone_from_system().bias) * 60).substr(0, 10)

func _new_memory() -> void:
	_keep_draft()
	selected = -1
	selected_id = ""
	_editor_original = ""
	tabs.current_tab = 2
	items.deselect_all()
	editor.text = str(_drafts.get("", ""))
	source_label.text = "手动添加的内容会固定保存，不会自动遗忘。"
	status_label.text = "写下希望猫猫一直记住的事情。"
	editor.grab_focus()
	_refresh_controls()

func _keep_draft() -> void:
	if editor.text != _editor_original: _drafts[selected_id] = editor.text
	else: _drafts.erase(selected_id)

func _save_memory() -> void:
	if not is_instance_valid(service): return
	var text := editor.text.strip_edges()
	if text.is_empty(): return
	var was_new := selected_id.is_empty()
	var success := false
	if was_new:
		success = service.add_memory(text)
	elif service.has_method("edit_memory_id"):
		success = service.edit_memory_id(selected_id, text)
	else:
		var entry := _entry_by_id(selected_id)
		if not entry.is_empty(): success = service.update_memory(int(entry.legacy_index), text)
	if success:
		_drafts.erase(selected_id)
		selected = -1
		selected_id = ""
		_editor_original = ""
		editor.text = ""
		if was_new: tabs.current_tab = 2
		source_label.text = "选中记忆，可以查看来源与最近提及的时间。"
		status_label.text = "已固定保存。" if was_new else "已保存修改。"
		_refresh()
	else:
		status_label.text = str(service.status)

func _delete_memory() -> void:
	if not is_instance_valid(service) or selected_id.is_empty(): return
	var entry := _entry_by_id(selected_id)
	if entry.is_empty(): return
	var success := false
	if service.has_method("forget_memory_id"):
		success = service.forget_memory_id(selected_id)
	else:
		var before_count: int = service.memories.size()
		service.remove_memory(int(entry.legacy_index))
		success = service.memories.size() < before_count
	if success:
		_drafts.erase(selected_id)
		selected = -1
		selected_id = ""
		_editor_original = ""
		editor.text = ""
		source_label.text = "已忘记这条记忆。"
	status_label.text = str(service.status)
	_refresh()

func _pin_memory() -> void:
	if not is_instance_valid(service) or selected_id.is_empty() or not service.has_method("pin_memory_id"): return
	if service.pin_memory_id(selected_id):
		tabs.current_tab = 2
		status_label.text = "已固定，不会自动遗忘。"
		_refresh()
	else:
		status_label.text = str(service.status)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		set_input_as_handled()
