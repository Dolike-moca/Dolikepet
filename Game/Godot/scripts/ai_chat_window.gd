extends Window
## Independent chat surface. Replies are plain text and never own pet input.

signal memory_requested
signal settings_requested
signal idle_closed
const SettingsTheme = preload("res://scripts/settings_theme.gd")
const TextReveal = preload("res://scripts/text_reveal.gd")
const SpeechSpeed = preload("res://scripts/speech_speed.gd")
const IdlePolicy = preload("res://scripts/chat_idle_policy.gd")
const SHORT_IDLE_SECONDS := IdlePolicy.SHORT
const LONG_IDLE_SECONDS := IdlePolicy.LONG
const DRAFT_IDLE_SECONDS := IdlePolicy.DRAFT
const LONG_REPLY_CHARACTERS := IdlePolicy.LONG_TEXT
const FADE_SECONDS := IdlePolicy.FADE
const RESTORE_SECONDS := IdlePolicy.RESTORE
var native_bridge: Object
var service: Node
var context_provider: Callable
var hover_override := -1
var transcript := RichTextLabel.new()
var input := TextEdit.new()
var status_label := Label.new()
var send := Button.new()
var stop := Button.new()
var clear := Button.new()
var remember := Button.new()
var settings := Button.new()
var streamed_text := ""
var previous_busy := false
var rendered_text := ""
var billing := Label.new()
var usage := LinkButton.new()
var _reveal = TextReveal.new()
var _live_turn := false
var _completed_index := -1
var _reveal_offset := -1
var _idle := 0.0
var _opacity := 1.0
var _idle_fading := false
var _idle_fade_elapsed := 0.0
var _opacity_from := 1.0
var _opacity_target := 1.0
var _opacity_age := 0.0
var _opacity_duration := RESTORE_SECONDS
var _pointer_sampled := false
var _last_pointer := Vector2i()
var _last_hover := false
var _changing_draft := false

func _init() -> void:
	title = "和猫咪聊天 · AI"
	size = Vector2i(490, 620)
	min_size = Vector2i(400, 480)
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
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title_label := Label.new()
	title_label.text = "猫咪陪你聊"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	settings.text = "AI 设置"
	settings.pressed.connect(func(): settings_requested.emit())
	heading.add_child(settings)
	var tools := HBoxContainer.new()
	layout.add_child(tools)
	clear.text = "清空对话"
	clear.tooltip_text = "清空这台设备上的聊天记录；已添加的记忆保留"
	clear.pressed.connect(_clear_history)
	tools.add_child(clear)
	remember.text = "记住选中文字"
	remember.tooltip_text = "把对话中选中的文字加入本地记忆；不自动记住聊天内容"
	remember.pressed.connect(_remember_selection)
	tools.add_child(remember)
	var manage := Button.new()
	manage.text = "管理记忆"
	manage.pressed.connect(func(): memory_requested.emit())
	tools.add_child(manage)
	transcript.bbcode_enabled = false
	transcript.selection_enabled = true
	transcript.context_menu_enabled = true
	transcript.scroll_following = false
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript.add_theme_color_override("default_color", SettingsTheme.TEXT)
	transcript.add_theme_stylebox_override("normal", SettingsTheme.box(Color("1b1921")))
	layout.add_child(transcript)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", SettingsTheme.MUTED)
	layout.add_child(status_label)
	var account_line := HBoxContainer.new()
	billing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	billing.add_theme_font_size_override("font_size", 12)
	billing.add_theme_color_override("font_color", SettingsTheme.MUTED)
	account_line.add_child(billing)
	usage.text = "管理用量"
	usage.pressed.connect(func(): OS.shell_open("https://chatgpt.com/settings/usage"))
	account_line.add_child(usage)
	layout.add_child(account_line)
	input.placeholder_text = "说点什么吧… Ctrl + Enter 发送，Enter 换行"
	input.custom_minimum_size.y = 92
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.add_theme_stylebox_override("normal", SettingsTheme.box(Color("25232b")))
	var input_focus := SettingsTheme.box(Color.TRANSPARENT)
	input_focus.set_border_width_all(1)
	input_focus.border_color = SettingsTheme.ACCENT
	input.add_theme_stylebox_override("focus", input_focus)
	input.add_theme_color_override("font_color", SettingsTheme.TEXT)
	input.add_theme_color_override("caret_color", SettingsTheme.ACCENT)
	input.gui_input.connect(_input_key)
	input.text_changed.connect(_draft_edited)
	layout.add_child(input)
	var actions := HBoxContainer.new()
	var local_hint := Label.new()
	local_hint.text = "聊天记录保存在本机"
	local_hint.add_theme_font_size_override("font_size", 12)
	local_hint.add_theme_color_override("font_color", SettingsTheme.MUTED)
	local_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(local_hint)
	stop.text = "停止"
	stop.pressed.connect(func():
		if is_instance_valid(service): service.cancel())
	actions.add_child(stop)
	send.text = "发送"
	send.custom_minimum_size.x = 76
	send.add_theme_stylebox_override("normal", SettingsTheme.box(Color("654592")))
	send.pressed.connect(_send_message)
	actions.add_child(send)
	layout.add_child(actions)
	close_requested.connect(hide)
	visibility_changed.connect(_visibility_changed)
	_refresh_all()

func setup(value: Node) -> void:
	if is_instance_valid(service):
		for pair in [[service.delta, _on_delta], [service.reply_completed, _on_completed], [service.failed, _on_failed], [service.state_changed, _on_state]]:
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
		for name in ["history_cleared", "account_changed"]:
			if service.has_signal(name) and service.is_connected(name, _reset_presentation): service.disconnect(name, _reset_presentation)
	service = value
	_reset_presentation()
	if is_instance_valid(service):
		service.delta.connect(_on_delta)
		service.reply_completed.connect(_on_completed)
		service.failed.connect(_on_failed)
		service.state_changed.connect(_on_state)
		for name in ["history_cleared", "account_changed"]:
			if service.has_signal(name): service.connect(name, _reset_presentation)
	if is_node_ready(): _refresh_all()

func open_panel() -> void:
	if not visible:
		var area := DisplayServer.screen_get_usable_rect(get_parent().get_window().current_screen)
		position = area.position + (area.size - size) / 2
		_reset_idle_visibility()
	else: note_activity()
	mode = Window.MODE_WINDOWED
	show()
	grab_focus()
	input.grab_focus()
	_refresh_all()

func _input_key(event: InputEvent) -> void:
	_note_input_activity(event)
	if _ime_composing(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and event.ctrl_pressed and not event.shift_pressed:
		input.accept_event()
		_send_message()

func _send_message() -> void:
	if not is_instance_valid(service): return
	var text := input.text.strip_edges()
	if text.is_empty() or (service.busy and str(service.request_kind) != "proactive"): return
	note_activity()
	var context: Dictionary = context_provider.call() if context_provider.is_valid() else {}
	streamed_text = ""
	if service.send_message(text, context):
		_changing_draft = true
		input.text = ""
		_changing_draft = false
	_refresh_all()

func _on_delta(text: String) -> void:
	if not is_instance_valid(service) or not service.busy or str(service.request_kind) not in ["chat", "proactive"]: return
	streamed_text = (streamed_text + text).left(8000)
	_reveal.set_text(streamed_text)
	if not visible: _reveal.finish()
	_render_history()

func _on_completed(text: String, _proactive: bool) -> void:
	note_activity()
	if visible and _live_turn and is_instance_valid(service) and not service.history.is_empty():
		var entry: Variant = service.history.back()
		if entry is Dictionary and str(entry.get("role", "")) == "assistant" and str(entry.get("text", "")) == text:
			_reveal.set_text(text)
			_completed_index = service.history.size() - 1
	else: _reset_reveal()
	streamed_text = ""
	_refresh_all()

func _on_failed(_message: String) -> void:
	note_activity()
	_reset_reveal()
	streamed_text = ""
	_refresh_all()

func _on_state() -> void:
	var now_busy: bool = is_instance_valid(service) and service.busy
	if now_busy != previous_busy:
		note_activity()
		streamed_text = ""
		if now_busy:
			_reset_reveal()
			_live_turn = visible and str(service.request_kind) in ["chat", "proactive"]
		elif _completed_index < 0: _reset_reveal()
	previous_busy = now_busy
	_refresh_all()

func _refresh_all() -> void:
	if not is_node_ready(): return
	_render_history()
	_refresh_controls()

func _render_history() -> void:
	var parts: PackedStringArray = []
	_reveal_offset = -1
	var characters := 0
	if is_instance_valid(service):
		for index in service.history.size():
			var entry: Variant = service.history[index]
			if not entry is Dictionary: continue
			var who := "你" if str(entry.get("role", "user")) == "user" else "猫咪"
			if not parts.is_empty(): characters += 2
			if index == _completed_index: _reveal_offset = characters + who.length() + 1
			var part := who + "\n" + str(entry.get("text", ""))
			parts.append(part); characters += part.length()
	if not streamed_text.is_empty():
		_reveal_offset = characters + (2 if not parts.is_empty() else 0) + 3
		parts.append("猫咪\n" + streamed_text + " ▍")
	var content := "\n\n".join(parts)
	if content.is_empty(): content = "想聊点什么？\n\n先在 AI 设置中选择连接方式并启用 AI。你可以聊日常、请猫咪帮忙想点子，也可以把希望它记住的事加入本地记忆。"
	if content == rendered_text:
		_update_visible_characters(); return
	var scrollbar := transcript.get_v_scroll_bar()
	var follow := rendered_text.is_empty() or scrollbar.value >= scrollbar.max_value - scrollbar.page - 28
	rendered_text = content
	transcript.text = content
	_update_visible_characters()
	if follow: _scroll_to_end.call_deferred()

func _reset_reveal() -> void:
	_reveal.clear(); _live_turn = false; _completed_index = -1; _reveal_offset = -1

func _reset_presentation() -> void:
	_reset_reveal(); streamed_text = ""
	if is_node_ready(): _refresh_all()

func _visibility_changed() -> void:
	# Opening history never replays old replies or a backlog received offscreen.
	if not visible:
		_reset_reveal()
		_pointer_sampled = false
	else:
		_reset_idle_visibility()
		if is_instance_valid(service) and service.busy and str(service.request_kind) in ["chat", "proactive"]:
			_live_turn = true; _reveal.set_text(streamed_text); _reveal.finish()
	_update_visible_characters()

func _process(dt: float) -> void:
	advance(dt)

func advance(dt: float) -> void:
	if not visible or not is_finite(dt) or dt <= 0.0: return
	var step := minf(dt, 0.25)
	var was_revealing := _live_turn and not _reveal.done()
	if was_revealing:
		_reveal.advance(step, SpeechSpeed.chars_per_second(int(service.settings.get("speech_speed", SpeechSpeed.DEFAULT)) if is_instance_valid(service) else SpeechSpeed.DEFAULT))
		_update_visible_characters()
	var activity := _sample_pointer_activity()
	if activity or _waiting_for_reply() or was_revealing or _ime_composing() or _dialog_active():
		note_activity()
		_advance_opacity(step)
		return
	_idle += step
	if not _idle_fading and _idle >= _idle_seconds():
		_idle_fading = true
		_idle_fade_elapsed = 0.0
		_transition_opacity(0.0, FADE_SECONDS)
		# The deadline frame belongs to the reading interval, not to its fade.
		return
	if _idle_fading: _idle_fade_elapsed += step
	_advance_opacity(step)
	if _idle_fading and is_zero_approx(_opacity):
		hide()
		idle_closed.emit()

func _waiting_for_reply() -> bool:
	return is_instance_valid(service) and service.busy and str(service.request_kind) in ["chat", "proactive", "test"]

func _idle_seconds() -> float:
	var latest_reply := ""
	if is_instance_valid(service):
		for index in range(service.history.size() - 1, -1, -1):
			var entry: Variant = service.history[index]
			if entry is Dictionary and str(entry.get("role", "")) == "assistant":
				latest_reply = str(entry.get("text", ""))
				break
	return IdlePolicy.idle_seconds(latest_reply, not input.text.strip_edges().is_empty())

func _ime_composing() -> bool:
	return input.has_ime_text()

func _dialog_active() -> bool:
	# Context menus need time to choose an action, but focus alone is not activity.
	return input.get_menu().visible or transcript.get_menu().visible

func _draft_edited() -> void:
	if not _changing_draft: note_activity()
	_refresh_controls()

func note_activity() -> void:
	if not visible: return
	_idle = 0.0
	_idle_fading = false
	_idle_fade_elapsed = 0.0
	_transition_opacity(1.0, RESTORE_SECONDS)

func _note_activity() -> void:
	note_activity()

func _note_input_activity(event: InputEvent) -> void:
	if not visible: return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or event is InputEventPanGesture:
		note_activity()
	elif event is InputEventMouseMotion:
		# Local mouse coordinates also change when a window moves under a still
		# pointer. Only real screen-position changes are user movement.
		if _sample_pointer_activity(): note_activity()

func _pointer_inside() -> bool:
	if hover_override >= 0: return hover_override == 1
	return Rect2i(position, size).has_point(_pointer_position())

func _pointer_position() -> Vector2i:
	return DisplayServer.mouse_get_position()

func _sample_pointer_activity() -> bool:
	var pointer := _pointer_position()
	var hovered := _pointer_inside()
	var active := _pointer_sampled and hovered and (pointer != _last_pointer or (hover_override >= 0 and not _last_hover))
	_last_pointer = pointer
	_last_hover = hovered
	_pointer_sampled = true
	return active

func _reset_idle_visibility() -> void:
	_idle = 0.0; _idle_fading = false; _idle_fade_elapsed = 0.0
	_opacity = 1.0; _opacity_from = 1.0; _opacity_target = 1.0; _opacity_age = 0.0
	_pointer_sampled = false
	_sample_pointer_activity()
	_apply_window_opacity()

func _transition_opacity(target: float, duration: float) -> void:
	if is_equal_approx(_opacity_target, target): return
	_opacity_from = _opacity; _opacity_target = target; _opacity_age = 0.0
	_opacity_duration = duration

func _advance_opacity(dt: float) -> void:
	if is_equal_approx(_opacity, _opacity_target): return
	_opacity_age = minf(_opacity_duration, _opacity_age + dt)
	var fraction := _opacity_age / _opacity_duration
	_opacity = lerpf(_opacity_from, _opacity_target, smoothstep(0.0, 1.0, fraction))
	_apply_window_opacity()

func _apply_window_opacity() -> void:
	if not is_instance_valid(native_bridge) or not native_bridge.has_method("set_companion_window_opacity"): return
	var window_id := get_window_id()
	if window_id < 0: return
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window_id)
	if handle != 0: native_bridge.call("set_companion_window_opacity", handle, _opacity)

func _exit_tree() -> void:
	_opacity = 1.0
	_apply_window_opacity()

func is_speech_revealing() -> bool:
	return visible and _live_turn and _reveal_offset >= 0 and not _reveal.done()

func is_speech_complete() -> bool:
	return visible and _live_turn and _completed_index >= 0 and _reveal.done()

func _update_visible_characters() -> void:
	transcript.visible_characters = _reveal_offset + _reveal.visible_text().length() if visible and _live_turn and _reveal_offset >= 0 and not _reveal.done() else -1

func _scroll_to_end() -> void:
	if is_instance_valid(transcript):
		var scrollbar := transcript.get_v_scroll_bar()
		scrollbar.value = scrollbar.max_value

func _refresh_controls() -> void:
	if not is_node_ready(): return
	var available := is_instance_valid(service)
	var active: bool = available and service.busy
	billing.text = service.billing_label() if available and service.has_method("billing_label") else "使用 API Key"
	usage.visible = available and service.settings.get("auth_method", "api_key") == "chatgpt"
	var can_interrupt: bool = active and str(service.request_kind) == "proactive"
	send.disabled = not available or (active and not can_interrupt) or input.text.strip_edges().is_empty()
	stop.visible = active
	clear.disabled = active or not available or service.history.is_empty()
	remember.disabled = not available
	status_label.text = str(service.status) if available else "AI 服务准备中。"
	if status_label.text.is_empty(): status_label.text = "回复仅供参考；关闭聊天窗口也能继续与猫咪互动。"

func _clear_history() -> void:
	if not is_instance_valid(service) or service.busy: return
	note_activity()
	service.clear_history()
	_reset_reveal()
	streamed_text = ""
	_refresh_all()

func _remember_selection() -> void:
	if not is_instance_valid(service): return
	note_activity()
	var selected := transcript.get_selected_text().strip_edges()
	if selected.is_empty():
		status_label.text = "先在聊天记录中选中想记住的文字。"
		return
	if service.add_memory(selected): status_label.text = "已加入本地记忆，可在「管理记忆」中修改或删除。"
	else: status_label.text = str(service.status)

func _input(event: InputEvent) -> void:
	_note_input_activity(event)
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		set_input_as_handled()
