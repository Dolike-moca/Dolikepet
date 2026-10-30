extends Window
## One shared speech bubble for passive invitations and explicit small-chat entry.
signal answered(text: String)
signal action_requested(action: String)
signal dismissed(reason: String)
signal settings_requested
signal history_requested
signal memory_requested
signal draft_changed(text: String)
signal spoken(text: String)
signal speech_stopped
const SettingsTheme = preload("res://scripts/settings_theme.gd")
const TextReveal = preload("res://scripts/text_reveal.gd")
const SpeechSpeed = preload("res://scripts/speech_speed.gd")
const IdlePolicy = preload("res://scripts/chat_idle_policy.gd")
const SHORT_IDLE_SECONDS := IdlePolicy.SHORT
const LONG_IDLE_SECONDS := IdlePolicy.LONG
const DRAFT_IDLE_SECONDS := IdlePolicy.DRAFT
const LONG_REPLY_CHARACTERS := IdlePolicy.LONG_TEXT
const IDLE_SECONDS := SHORT_IDLE_SECONDS
const FADE_SECONDS := IdlePolicy.FADE
const RESTORE_SECONDS := IdlePolicy.RESTORE
const MAX_DRAFT := 2000
const BUBBLE_WIDTH := 340
const TIP_HEIGHT := 11
class Tip extends Control:
	var points := PackedVector2Array()
	func _draw() -> void:
		if points.size() != 3: return
		draw_colored_polygon(points, Color("201b29"))
		draw_polyline(points, Color("76618e"), 1.0, true)
var native_bridge: Object
var service: Node
var context_provider: Callable
var hover_override := -1
var panel := PanelContainer.new()
var transcript := RichTextLabel.new()
var input := TextEdit.new()
var status_label := Label.new()
var billing := Label.new()
var usage := Button.new()
var send := Button.new()
var stop := Button.new()
var quick := HBoxContainer.new()
var reply_button := Button.new()
var more_button := Button.new()
var tip_above := false
var _tip := Tip.new()
var _layout := VBoxContainer.new()
var _compose_row := HBoxContainer.new()
var _billing_row := HBoxContainer.new()
var _menu := VBoxContainer.new()
var _entries: Array[String] = []
var _streamed := ""
var _submitted_text := ""
var _waiting := false
var _starting := false
var _start_failed := false
var _owner_serial := -1
var _service_has_serial := false
var _composing := false
var _active := false
var _engaged := false
var _suspended := false
var _idle := 0.0
var _opacity := 1.0
var _opacity_from := 1.0
var _opacity_target := 1.0
var _opacity_age := 0.0
var _opacity_duration := RESTORE_SECONDS
var _was_hovered := false
var _last_mouse_position := Vector2i.ZERO
var _mouse_sampled := false
var _reason := ""
var _pet_rect := Rect2i()
var _screen := 0
var _changing_draft := false
var _layout_pending := false
var _body_rect := Rect2()
var _tip_x := 0.0
var _reveal = TextReveal.new()
func _init() -> void:
	title = "和東菱可聊聊"
	size = Vector2i(BUBBLE_WIDTH,130); min_size = Vector2i(240,72)
	visible = false; transient = false; exclusive = false
	borderless = true; transparent = true; transparent_bg = true
	unfocusable = true; popup_window = false; always_on_top = true
func _ready() -> void:
	panel.theme = SettingsTheme.make()
	var background := SettingsTheme.box(Color("201b29"),19,14)
	background.content_margin_top = 10; background.content_margin_bottom = 10
	background.set_border_width_all(1); background.border_color = Color("76618e")
	panel.add_theme_stylebox_override("panel",background); add_child(panel)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_tip)
	_layout.add_theme_constant_override("separation",5); panel.add_child(_layout)
	var heading := HBoxContainer.new(); heading.add_theme_constant_override("separation",3)
	var title_label := Label.new(); title_label.text = "東菱可"
	title_label.add_theme_font_size_override("font_size",11)
	title_label.add_theme_color_override("font_color",SettingsTheme.MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.add_child(title_label)
	stop.text = "停止"; stop.tooltip_text = "停止这次回复，保留原消息供重试"
	_small_button(stop); stop.pressed.connect(func():
		if _waiting and is_instance_valid(service): service.cancel())
	heading.add_child(stop)
	more_button.text = "⋯"; more_button.tooltip_text = "聊天记录、记忆与设置"; _small_button(more_button)
	more_button.pressed.connect(func(): _menu.visible = not _menu.visible; _request_layout())
	heading.add_child(more_button)
	var close := Button.new(); close.text = "×"; close.tooltip_text = "收起，保留未发送的文字"
	_small_button(close); close.pressed.connect(_dismiss_user); heading.add_child(close); _layout.add_child(heading)
	transcript.bbcode_enabled = false; transcript.selection_enabled = true
	transcript.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; transcript.scroll_active = true
	transcript.add_theme_color_override("default_color",SettingsTheme.TEXT)
	transcript.add_theme_font_size_override("normal_font_size",14); _layout.add_child(transcript)
	reply_button.text = "回复猫猫"; reply_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_small_button(reply_button); reply_button.pressed.connect(begin_reply); _layout.add_child(reply_button)
	_compose_row.add_theme_constant_override("separation",6)
	input.placeholder_text = "和猫猫说点什么…"; input.tooltip_text = "Ctrl + Enter 发送，Enter 换行"
	input.custom_minimum_size.y = 42; input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.add_theme_stylebox_override("normal",SettingsTheme.box(Color("30283d"),12,9))
	var focus := SettingsTheme.box(Color.TRANSPARENT,12)
	focus.set_border_width_all(1); focus.border_color = SettingsTheme.ACCENT
	input.add_theme_stylebox_override("focus",focus)
	input.add_theme_color_override("font_color",SettingsTheme.TEXT); input.add_theme_color_override("caret_color",SettingsTheme.ACCENT)
	input.gui_input.connect(_input_key); input.text_changed.connect(_draft_edited); _compose_row.add_child(input)
	send.text = "↑"; send.tooltip_text = "发送（Ctrl + Enter）"; send.custom_minimum_size.x = 34
	send.add_theme_stylebox_override("normal",SettingsTheme.box(Color("6a478f"),10,8))
	send.pressed.connect(_send_message); _compose_row.add_child(send); _layout.add_child(_compose_row)
	billing.add_theme_font_size_override("font_size",11); billing.add_theme_color_override("font_color",SettingsTheme.MUTED)
	billing.size_flags_horizontal = Control.SIZE_EXPAND_FILL; billing.clip_text = true; _billing_row.add_child(billing)
	usage.text = "用量"; usage.tooltip_text = "管理 ChatGPT 账户用量"; _small_button(usage)
	usage.pressed.connect(func(): OS.shell_open("https://chatgpt.com/settings/usage")); _billing_row.add_child(usage); _layout.add_child(_billing_row)
	status_label.add_theme_font_size_override("font_size",11); status_label.add_theme_color_override("font_color",SettingsTheme.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _layout.add_child(status_label)
	for item in [["好呀","accepted"],["稍后提醒","snooze"],["今天安静","quiet_today"]]:
		var button := Button.new(); button.text = item[0]; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_small_button(button); button.pressed.connect(_quick_action.bind(item[1])); quick.add_child(button)
	_menu.add_child(quick)
	var links := HBoxContainer.new()
	for item in [["聊天记录",history_requested],["记忆",memory_requested],["设置",settings_requested]]:
		var button := Button.new(); button.text = item[0]; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_small_button(button); button.pressed.connect(_open_link.bind(item[1])); links.add_child(button)
	_menu.add_child(links); _menu.hide(); _layout.add_child(_menu)
	close_requested.connect(_dismiss_user); _refresh_controls()
func _small_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size",12)
	button.add_theme_stylebox_override("normal",SettingsTheme.box(Color.TRANSPARENT,7,5))
	button.add_theme_stylebox_override("hover",SettingsTheme.box(Color("30283d"),7,5)); button.custom_minimum_size.y = 26
	button.pressed.connect(_note_activity)
func _open_link(destination: Signal) -> void:
	_menu.hide(); _request_layout(); destination.emit()
func setup(value: Node) -> void:
	if is_instance_valid(service):
		for pair in [[service.delta,_on_delta],[service.reply_completed,_on_completed],[service.failed,_on_failed],[service.state_changed,_on_state]]:
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
	service = value; _service_has_serial = false
	if is_instance_valid(service):
		for property in service.get_property_list():
			if property.name == "_request_serial": _service_has_serial = true
		service.delta.connect(_on_delta); service.reply_completed.connect(_on_completed)
		service.failed.connect(_on_failed); service.state_changed.connect(_on_state)
	_refresh_controls()
func present(text: String, reason: String, pet_rect: Rect2i, screen: int, revealed_characters: int = 0) -> bool:
	if _active or has_draft() or _waiting or text.strip_edges().is_empty(): return false
	_reason = reason; _pet_rect = pet_rect; _screen = screen; _entries = [text.strip_edges().left(300)]
	_reveal.replace(_entries.back())
	_reveal.seek(revealed_characters)
	_streamed = ""; _submitted_text = ""; _composing = false; _engaged = false; _reset_visibility()
	status_label.text = ""; _menu.hide(); _active = true; _render()
	if not _show_passively(): _active = false; return false
	return true
func _show_passively() -> bool:
	if OS.get_name() != "Windows" or not is_instance_valid(native_bridge) or not native_bridge.has_method("show_companion_without_activation"): return false
	unfocusable = true; _fit_contents(); show()
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,get_window_id())
	if not bool(native_bridge.call("show_companion_without_activation",handle)): hide(); return false
	_suspended = false; return true
func reopen() -> bool:
	if _active and visible: _note_activity()
	else: _reset_visibility()
	_active = true; _engaged = true; _menu.hide()
	_composing = not _waiting; _render()
	if _waiting: _reveal.finish(); _update_visible_characters()
	if not _show_passively(): _active = false; return false
	if _composing: _reveal.clear(); speech_stopped.emit()
	_activate_from_user()
	if _composing: input.grab_focus()
	return true
func begin_reply() -> void:
	if _waiting: return
	_reveal.clear()
	speech_stopped.emit()
	_composing = true; status_label.text = ""; _menu.hide()
	_activate_from_user(); _refresh_controls(); _fit_contents(); input.grab_focus()
func is_composing() -> bool: return _composing
func is_open() -> bool: return _active
func owns_reply() -> bool: return _waiting or _starting
func is_speech_revealing() -> bool: return _active and not _composing and not _reveal.done()
func is_speech_complete() -> bool: return _active and not _composing and not _waiting and not _reveal.full_text.is_empty() and _reveal.done()
func reset_session() -> void:
	_reveal.clear()
	speech_stopped.emit()
	_waiting = false; _starting = false; _streamed = ""; _entries.clear(); _submitted_text = ""; _owner_serial = -1
	_active = false; _engaged = has_draft(); _suspended = false; _composing = has_draft()
	status_label.text = ""; _menu.hide(); hide(); _render()
func engaged() -> bool: return (_active and _engaged) or has_draft() or _waiting
func has_draft() -> bool: return not input.text.is_empty()
func set_draft(text: String) -> void:
	_changing_draft = true; input.text = text.left(MAX_DRAFT); _changing_draft = false
	if has_draft(): _engaged = true
	_note_activity()
	_refresh_controls()
func update_anchor(pet_rect: Rect2i, screen: int) -> void:
	_pet_rect = pet_rect; _screen = screen
	if visible: _reposition()
func _reposition() -> void:
	var area := DisplayServer.screen_get_usable_rect(_screen)
	var center_x := _pet_rect.position.x + _pet_rect.size.x / 2
	var above := _pet_rect.position.y - size.y - 9
	var below := _pet_rect.end.y + 9
	var x := center_x - size.x / 2
	var y := above
	tip_above = false
	if above < area.position.y:
		if below + size.y <= area.end.y: y = below; tip_above = true
		else:
			x = _pet_rect.end.x + 10
			if x + size.x > area.end.x: x = _pet_rect.position.x - size.x - 10
			y = _pet_rect.position.y
			tip_above = y > _pet_rect.position.y + _pet_rect.size.y / 2
	position = Vector2i(clampi(x,area.position.x,maxi(area.position.x,area.end.x-size.x)),clampi(y,area.position.y,maxi(area.position.y,area.end.y-size.y)))
	_tip_x = clampf(float(center_x-position.x),26.0,float(size.x-26))
	_body_rect = Rect2(0,TIP_HEIGHT if tip_above else 0,size.x,size.y-TIP_HEIGHT)
	panel.position = _body_rect.position; panel.size = _body_rect.size; _tip.size = Vector2(size)
	var edge := _body_rect.position.y if tip_above else _body_rect.end.y
	var tip_y := 0.0 if tip_above else float(size.y-1)
	var overlap := 1.0 if tip_above else -1.0
	_tip.points = PackedVector2Array([Vector2(_tip_x-10,edge+overlap),Vector2(_tip_x,tip_y),Vector2(_tip_x+10,edge+overlap)])
	_tip.queue_redraw(); _update_hit_polygon()
func _update_hit_polygon() -> void:
	var points := PackedVector2Array(); var radius := 19.0
	var w := float(size.x); var top := _body_rect.position.y; var bottom := _body_rect.end.y
	points.append(Vector2(radius,top))
	if tip_above:
		points.append(Vector2(_tip_x-10,top)); points.append(Vector2(_tip_x,0)); points.append(Vector2(_tip_x+10,top))
	for step in 5:
		var angle := -PI/2.0 + float(step)*PI/8.0
		points.append(Vector2(w-radius,top+radius)+Vector2(cos(angle),sin(angle))*radius)
	for step in 5:
		var angle := float(step)*PI/8.0
		points.append(Vector2(w-radius,bottom-radius)+Vector2(cos(angle),sin(angle))*radius)
	if not tip_above:
		points.append(Vector2(_tip_x+10,bottom)); points.append(Vector2(_tip_x,size.y-1)); points.append(Vector2(_tip_x-10,bottom))
	for step in 5:
		var angle := PI/2.0 + float(step)*PI/8.0
		points.append(Vector2(radius,bottom-radius)+Vector2(cos(angle),sin(angle))*radius)
	for step in 5:
		var angle := PI + float(step)*PI/8.0
		points.append(Vector2(radius,top+radius)+Vector2(cos(angle),sin(angle))*radius)
	mouse_passthrough_polygon = points
func _request_layout() -> void:
	if _layout_pending or not is_node_ready(): return
	_layout_pending = true; _fit_contents.call_deferred()
func _text_height(text: String, width: float, font_size: int) -> float:
	var paragraph := TextParagraph.new(); paragraph.width = maxf(60.0,width)
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(text,panel.theme.default_font,font_size)
	return paragraph.get_size().y
func _fit_contents() -> void:
	_layout_pending = false
	if not is_node_ready(): return
	var area := DisplayServer.screen_get_usable_rect(_screen)
	var width := mini(BUBBLE_WIDTH,maxi(240,area.size.x-16))
	transcript.custom_minimum_size.y = clampf(_text_height(transcript.text,width-42,14)+5,24,155)
	input.custom_minimum_size.y = clampf(_text_height(input.text if has_draft() else "输入",width-82,14)+18,42,88)
	panel.size.x = width
	var desired := int(ceil(_layout.get_combined_minimum_size().y))+20+TIP_HEIGHT
	size = Vector2i(width,clampi(desired,78,mini(370,maxi(78,area.size.y-16))))
	_reposition()
func suspend() -> void:
	if not _active or _suspended: return
	_note_activity()
	hide(); _suspended = true
	if not engaged(): _active = false; dismissed.emit("interrupted")
func advance(dt: float, allow: bool) -> void:
	if not _active: return
	if not allow: suspend(); return
	if _suspended and not _show_passively(): return
	dt = clampf(dt,0.0,0.25) if is_finite(dt) else 0.0
	var revealing := not _composing and not _reveal.done()
	if revealing:
		_reveal.advance(dt, SpeechSpeed.chars_per_second(int(service.settings.get("speech_speed", SpeechSpeed.DEFAULT)) if is_instance_valid(service) else SpeechSpeed.DEFAULT))
		_update_visible_characters()
	var pointer := _pointer_position()
	var hovered := hover_override == 1 if hover_override >= 0 else Geometry2D.is_point_in_polygon(Vector2(pointer-position),mouse_passthrough_polygon)
	var entered := hovered and not _was_hovered
	var moved := _mouse_sampled and pointer != _last_mouse_position
	_was_hovered = hovered; _last_mouse_position = pointer; _mouse_sampled = true
	# Owning a conversation still blocks a new invitation, but does not keep an
	# untouched bubble open forever. Focus alone is likewise not user activity.
	if _waiting or _starting or revealing or entered or (hovered and moved) or _ime_composing():
		_note_activity()
		_advance_opacity(dt)
	else:
		_idle += dt
		var limit := _idle_limit()
		if _idle >= limit:
			_start_opacity(0.0,FADE_SECONDS)
			_advance_opacity(minf(dt,maxf(0.0,_idle-limit)))
		else:
			_advance_opacity(dt)
	if _opacity <= 0.0 and _opacity_target == 0.0:
		_active = false; _suspended = false; _engaged = false
		_menu.hide(); hide(); dismissed.emit("idle_timeout")
func _idle_limit() -> float:
	return IdlePolicy.idle_seconds(str(_entries.back()) if not _composing and not _entries.is_empty() else "", has_draft())
func _ime_composing() -> bool:
	return _composing and input.has_ime_text()
func _pointer_position() -> Vector2i:
	return Vector2i.ZERO if hover_override >= 0 else DisplayServer.mouse_get_position()
func _note_activity() -> void:
	_idle = 0.0
	_start_opacity(1.0,RESTORE_SECONDS)
func _reset_visibility() -> void:
	_idle = 0.0; _opacity = 1.0; _opacity_from = 1.0; _opacity_target = 1.0
	_was_hovered = false; _mouse_sampled = false
	_opacity_age = 0.0; _opacity_duration = RESTORE_SECONDS; _set_opacity(1.0)
func _start_opacity(target: float, duration: float) -> void:
	if _opacity_target == target: return
	_opacity_from = _opacity; _opacity_target = target; _opacity_age = 0.0; _opacity_duration = duration
func _advance_opacity(dt: float) -> void:
	_opacity_age = minf(_opacity_duration,_opacity_age+dt)
	var progress := smoothstep(0.0,_opacity_duration,_opacity_age)
	_opacity = lerpf(_opacity_from,_opacity_target,progress)
	_set_opacity(_opacity)
func _set_opacity(value: float) -> void: panel.modulate.a = value; _tip.modulate.a = value
func _activate_from_user() -> void:
	_engaged = true; _note_activity()
	if unfocusable:
		unfocusable = false
		var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,get_window_id())
		if is_instance_valid(native_bridge): native_bridge.call("show_companion_without_activation",handle)
		grab_focus()
func _input(event: InputEvent) -> void:
	if not _active or not visible: return
	if event is InputEventMouseButton and event.pressed:
		_note_activity()
		if event.button_index == MOUSE_BUTTON_LEFT: _activate_from_user()
	elif event is InputEventKey and event.pressed:
		_note_activity()
		if event.keycode == KEY_ESCAPE: _dismiss_user(); set_input_as_handled()
	elif event is InputEventPanGesture or event is InputEventScreenTouch:
		_note_activity()
func _input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed: _note_activity()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and event.ctrl_pressed and not event.shift_pressed: input.accept_event(); _send_message()
func _draft_edited() -> void:
	if _changing_draft: return
	_note_activity()
	if input.text.length() > MAX_DRAFT:
		set_draft(input.text.left(MAX_DRAFT)); input.set_caret_line(input.get_line_count()-1); input.set_caret_column(input.get_line(input.get_caret_line()).length())
	_engaged = true; draft_changed.emit(input.text); _refresh_controls()
func _send_message() -> void:
	_note_activity()
	if not is_instance_valid(service) or _waiting: return
	var text := input.text.strip_edges()
	if text.is_empty() or (service.busy and str(service.request_kind) != "proactive"): return
	_submitted_text = text; _waiting = true; _streamed = ""; _start_failed = false; _owner_serial = -1
	_reveal.clear()
	_composing = false; status_label.text = ""; _menu.hide(); _entries.clear()
	var context: Dictionary = context_provider.call() if context_provider.is_valid() else {}
	_starting = true
	var accepted: bool = service.send_message(text,context)
	_starting = false
	if accepted and not _start_failed:
		_owner_serial = int(service.get("_request_serial")) if _service_has_serial else -1
		set_draft(""); draft_changed.emit(""); _engaged = true; answered.emit(text)
	else:
		_waiting = false; _composing = true; status_label.text = str(service.status).left(180)
	_render()
func _quick_action(action: String) -> void:
	_note_activity()
	if action == "accepted":
		_engaged = true; action_requested.emit(action)
		_entries = ["好呀，先休息一小会儿，猫猫陪着你喵。" if _reason == "rest" else "好呀，想聊什么都可以喵。"]
		_reveal.replace(_entries.back())
		_composing = false; _menu.hide(); _reason = ""; _render()
		spoken.emit(_entries.back())
		return
	action_requested.emit(action); _active = false; hide(); dismissed.emit(action)
func _dismiss_user() -> void:
	_reveal.clear()
	var responded := _engaged or has_draft() or _waiting
	_active = false; _suspended = false; _menu.hide(); hide(); dismissed.emit("closed" if responded else "ignored")
func _same_request() -> bool: return _starting or not _service_has_serial or int(service.get("_request_serial")) == _owner_serial
func _on_delta(text: String) -> void:
	if not _waiting or not _same_request(): return
	_note_activity()
	_streamed = (_streamed+text).left(8000); _render()
func _on_completed(text: String, proactive: bool) -> void:
	if not _waiting or proactive or not _same_request(): return
	_note_activity()
	_waiting = false; _streamed = ""; _submitted_text = ""; _entries = [text.left(8000)]
	_composing = false; status_label.text = ""; _reason = ""; _render()
func _restore_after_interruption(message: String) -> void:
	_note_activity()
	_reveal.clear()
	_waiting = false; _streamed = ""; _composing = true; _start_failed = true
	if not has_draft() and not _submitted_text.is_empty(): set_draft(_submitted_text); draft_changed.emit(input.text)
	status_label.text = message.left(180); _render()
func _on_failed(message: String) -> void:
	if not _waiting or not _same_request(): return
	_restore_after_interruption(message)
func _on_state() -> void:
	if _waiting and not _starting and is_instance_valid(service):
		if not _same_request(): _restore_after_interruption("上一条回复已中断，消息已保留。")
		elif not service.busy: _restore_after_interruption(str(service.status))
	_refresh_controls()
func _render() -> void:
	transcript.text = (_streamed+" ▍") if not _streamed.is_empty() else ("猫猫想一想…" if _waiting else (_entries.back() if not _entries.is_empty() else ""))
	_reveal.set_text(_streamed if not _streamed.is_empty() else (_entries.back() if not _waiting and not _entries.is_empty() else ""))
	_update_visible_characters()
	_refresh_controls()
	if _waiting: _scroll_end.call_deferred()
func _update_visible_characters() -> void:
	# Lay out the complete sentence once; only its drawn characters advance.
	# This avoids a growing bubble jumping around the cat for every letter.
	transcript.visible_characters = -1 if _waiting and _streamed.is_empty() else _reveal.visible_text().length()
	if _waiting and _reveal.done() and not _streamed.is_empty(): transcript.visible_characters = -1
func _scroll_end() -> void:
	if is_instance_valid(transcript): transcript.get_v_scroll_bar().value = transcript.get_v_scroll_bar().max_value
func _refresh_controls() -> void:
	if not is_node_ready(): return
	var available := is_instance_valid(service)
	var occupied: bool = available and service.busy and str(service.request_kind) != "proactive"
	send.disabled = not available or _waiting or occupied or input.text.strip_edges().is_empty(); stop.visible = _waiting
	transcript.visible = not _composing; reply_button.visible = not _composing and not _waiting
	_compose_row.visible = _composing; _billing_row.visible = _composing
	billing.text = str(service.billing_label()) if available and service.has_method("billing_label") else "OpenAI API"; billing.tooltip_text = billing.text
	usage.visible = available and str(service.settings.get("auth_method","api_key")) == "chatgpt"
	quick.visible = not _reason.is_empty() and not _waiting
	status_label.visible = not status_label.text.is_empty(); _request_layout()
