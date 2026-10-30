extends SceneTree
## Native Window + local push_input events, fake service/opacity bridge only.
## No global input, credentials, network, persistent history or user folders.
const Chat = preload("res://scripts/ai_chat_window.gd")
class FixtureChat extends Chat:
	var composing_ime := false
	var pointer_position := Vector2i(100, 100)
	func _ime_composing() -> bool: return composing_ime
	func _pointer_position() -> Vector2i: return pointer_position
class Bridge extends RefCounted:
	var calls: Array[Dictionary] = []
	var window: WeakRef
	func set_companion_window_opacity(handle: int, opacity: float) -> bool:
		var target: Window = window.get_ref() if window != null else null
		calls.append({"handle":handle, "opacity":opacity, "visible":target.visible if target != null else false})
		return true
class Service extends Node:
	signal delta(text: String)
	signal reply_completed(text: String, proactive: bool)
	signal failed(message: String)
	signal state_changed
	signal history_cleared
	signal account_changed
	var settings := {"auth_method":"api_key", "speech_speed":2}
	var history: Array = []
	var busy := false
	var request_kind := ""
	var status := "离线回归服务"
	var request_count := 0
	func billing_label() -> String: return "离线回归服务"
	func send_message(text: String, _context: Dictionary = {}) -> bool:
		if busy: return false
		request_count += 1; busy = true; request_kind = "chat"
		history.append({"role":"user", "text":text}); state_changed.emit(); return true
	func finish(text: String) -> void:
		history.append({"role":"assistant", "text":text}); busy = false; request_kind = ""
		reply_completed.emit(text, false); state_changed.emit()
	func cancel() -> void:
		busy = false; request_kind = ""; status = "已停止"; state_changed.emit()
	func error() -> void:
		busy = false; request_kind = ""; status = "模拟离线失败"; failed.emit(status); state_changed.emit()
	func clear_history() -> void:
		history.clear(); history_cleared.emit(); state_changed.emit()
var checks := 0
var failures: Array[String] = []
var chat: FixtureChat
var service: Service
var bridge: Bridge
var timeouts: Array[bool] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("FULL CHAT IDLE: " + message)
func tick(seconds: float, step: float = 0.25) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var dt := minf(remaining, minf(step, 0.25))
		chat.advance(dt); remaining -= dt
func fresh(entries: Array = [], draft: String = "") -> void:
	chat.hide(); service.busy = false; service.request_kind = ""
	service.history = entries.duplicate(true); service.settings.speech_speed = 2
	chat.composing_ime = false; chat.hover_override = 0; chat.input.text = draft
	chat.setup(service); chat.open_panel(); timeouts.clear(); bridge.calls.clear()
func short_history(text: String) -> Array:
	return [{"role":"user", "text":"聊一句"}, {"role":"assistant", "text":text}]
func edit_draft(text: String) -> void:
	chat.input.text = text; chat.input.text_changed.emit()
func send_message(text: String) -> void:
	edit_draft(text); chat._send_message()
func run() -> void:
	root.title = "Dolike full-chat idle fixture"
	root.size = Vector2i(180, 180)
	service = Service.new(); root.add_child(service)
	bridge = Bridge.new(); chat = FixtureChat.new(); bridge.window = weakref(chat)
	chat.native_bridge = bridge; chat.hover_override = 0
	root.add_child(chat); chat.setup(service); chat.set_process(false)
	chat.idle_closed.connect(func(): timeouts.append(true))
	await process_frame
	check(not root.gui_embed_subwindows and chat.get_window_id() != root.get_window_id(), "fixture uses a distinct native Window")
	check(not chat.borderless and not chat.transparent and not chat.transcript.bbcode_enabled, "full chat keeps its native frame and plain-text transcript")

	# Existing history is fully rendered; only the most recent reply affects time.
	for case in [
		{"text":"", "limit":30.0},
		{"text":"喵".repeat(119), "limit":30.0},
		{"text":"喵".repeat(120), "limit":60.0},
		{"text":"喵".repeat(121), "limit":60.0},
		{"text":"喵".repeat(119) + " \n\t".repeat(10), "limit":30.0},
		{"text":" \n\t".repeat(80), "limit":30.0}
	]:
		var text: String = case.text
		fresh([] if text.is_empty() else short_history(text))
		var history_before := service.history.duplicate(true)
		var transcript_before: String = chat.transcript.text
		check(chat.transcript.visible_characters == -1 and not chat.is_speech_revealing(), "opening old or empty history never starts a reveal")
		check(chat._idle_seconds() == float(case.limit), "reading interval counts non-whitespace Unicode characters")
		tick(float(case.limit) - 0.25)
		check(chat.visible and is_equal_approx(chat._opacity, 1.0), "history receives its entire reading interval")
		tick(1.25)
		check(chat.visible and chat._opacity > 0.0 and chat._opacity < 1.0, "full Window remains visible partway through idle fade")
		tick(3.0)
		check(not chat.visible and timeouts.size() == 1, "history timeout hides exactly once")
		check(service.history == history_before and chat.transcript.text == transcript_before, "idle timeout retains all history and displayed text")
		tick(180.0)
		check(not chat.visible and timeouts.size() == 1, "hidden Window never repeats its timeout")
		chat.open_panel()
		check(chat.visible and is_equal_approx(chat._opacity, 1.0) and is_zero_approx(chat._idle), "explicit reopen restores full opacity and a fresh interval")
		check(chat.transcript.text == transcript_before and chat.transcript.visible_characters == -1 and not chat.is_speech_revealing(), "reopen shows the same history without replaying it")
	fresh([{"role":"assistant", "text":"旧".repeat(200)}, {"role":"user", "text":"用户".repeat(200)}, {"role":"assistant", "text":"新的短回复"}])
	check(chat._idle_seconds() == 30.0, "old long replies and long user turns do not lengthen the latest short reply")

	# Whole-window opacity is sent to the bridge continuously until hiding at zero.
	fresh(short_history("观察淡出")); tick(30.0)
	var previous_opacity: float = chat._opacity
	var fade_steps := 0
	while chat.visible and fade_steps < 40:
		check(chat._opacity > 0.0, "native Window stays present until its fade reaches zero")
		tick(0.1, 0.1)
		check(chat._opacity <= previous_opacity + 0.000001 and previous_opacity - chat._opacity <= 0.1, "full-window fade changes opacity continuously")
		check(not bridge.calls.is_empty() and is_equal_approx(float(bridge.calls.back().opacity), chat._opacity), "native bridge receives each effective whole-window opacity")
		previous_opacity = chat._opacity; fade_steps += 1
	check(fade_steps >= 27 and fade_steps <= 31 and is_zero_approx(chat._opacity), "full-window fade lasts three seconds")
	check(timeouts.size() == 1, "one completed fade emits one idle close")
	bridge.calls.clear(); chat.open_panel()
	# Godot may recreate the HWND on show; every valid handle receives alpha 1.
	var reopen_opaque := not bridge.calls.is_empty()
	for call in bridge.calls: reopen_opaque = reopen_opaque and int(call.handle) > 0 and is_equal_approx(float(call.opacity), 1.0)
	check(reopen_opaque, "reopen applies full opacity as soon as a valid native Window exists")
	check(chat.transcript.visible_characters == -1 and not chat.is_speech_revealing(), "fade and reopen cannot restart old text animation")

	# Entry reverses the current phase; parked hover and focus can still time out.
	fresh(short_history("鼠标移入后继续计时")); tick(31.5)
	var faded: float = chat._opacity
	chat.hover_override = 1; tick(0.05, 0.05)
	check(chat._opacity > faded and chat._opacity < 1.0 and is_zero_approx(chat._idle), "mouse entry reverses an in-progress fade without a flash")
	tick(0.15, 0.05)
	check(is_equal_approx(chat._opacity, 1.0), "mouse entry restores opacity in 0.2 seconds")
	tick(29.5)
	check(chat.visible and chat._idle >= 29.5 and is_equal_approx(chat._opacity, 1.0), "stationary hover keeps consuming idle time")
	tick(4.0)
	check(not chat.visible and timeouts.size() == 1, "stationary hover eventually allows full chat to hide")
	fresh(); await process_frame
	check(chat.input.has_focus(), "fixture empty composer has real local focus")
	tick(29.75)
	check(chat.visible and is_equal_approx(chat._opacity, 1.0), "focused empty composer receives thirty seconds")
	tick(4.0)
	check(not chat.visible and timeouts.size() == 1, "focus alone does not keep the full Window open")

	# Local Window events exercise the connected activity and TextEdit paths.
	fresh(short_history("事件测试")); await process_frame
	tick(29.0)
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	click.position = chat.transcript.global_position + Vector2(12, 12)
	chat.push_input(click)
	check(is_zero_approx(chat._idle), "local click resets full-chat idle")
	click.pressed = false; chat.push_input(click)
	tick(29.0)
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true; wheel.position = click.position
	chat.push_input(wheel)
	check(is_zero_approx(chat._idle), "local scroll resets full-chat idle")
	tick(29.0)
	var motion := InputEventMouseMotion.new(); motion.position = click.position; motion.relative = Vector2(2, 1)
	chat.hover_override = 1; chat.pointer_position += Vector2i(2, 1)
	chat.push_input(motion)
	check(is_zero_approx(chat._idle), "local mouse movement resets full-chat idle")
	tick(10.0); chat.push_input(motion)
	check(chat._idle >= 10.0, "stationary screen pointer events caused by window movement do not reset idle")
	chat.hover_override = 0
	tick(19.0)
	chat.input.grab_focus(); chat.input.set_caret_column(chat.input.text.length())
	var typed := InputEventKey.new(); typed.keycode = KEY_A; typed.unicode = 97; typed.pressed = true
	chat.push_input(typed); await process_frame
	check(chat.input.text == "a" and is_zero_approx(chat._idle), "Window-local typing inserts into TextEdit and resets idle")
	tick(119.0)
	var navigation := InputEventKey.new(); navigation.keycode = KEY_LEFT; navigation.pressed = true
	chat.push_input(navigation)
	check(chat.input.text == "a" and is_zero_approx(chat._idle), "navigation key resets idle without modifying the draft")
	tick(119.75)
	check(chat.visible and is_equal_approx(chat._opacity, 1.0), "draft receives a full two minutes after its last key event")
	tick(4.0)
	check(not chat.visible and chat.input.text == "a" and timeouts.size() == 1, "draft timeout hides once and preserves unsent text")
	chat.open_panel()
	check(chat.input.text == "a" and is_equal_approx(chat._opacity, 1.0), "reopening restores the exact saved draft and opacity")
	tick(119.0); edit_draft("继续写这段草稿")
	check(is_zero_approx(chat._idle), "TextEdit text_changed resets the full draft clock")
	tick(119.75)
	check(chat.visible and is_equal_approx(chat._opacity, 1.0), "edited draft gets another complete two-minute interval")

	# An isolated IME boundary protects composition without a global input method.
	chat.composing_ime = true; tick(180.0)
	check(chat.visible and is_zero_approx(chat._idle), "IME composition pauses and resets idle")
	var confirm := InputEventKey.new(); confirm.keycode = KEY_ENTER; confirm.pressed = true
	var requests_before := service.request_count
	chat._input_key(confirm)
	check(service.request_count == requests_before and not chat.input.text.is_empty(), "plain Enter confirming IME never submits the draft")
	confirm.ctrl_pressed = true; chat._input_key(confirm)
	check(service.request_count == requests_before and not chat.input.text.is_empty(), "Ctrl+Enter cannot submit unfinished IME composition")
	chat.composing_ime = false; tick(119.75)
	check(chat.visible and is_equal_approx(chat._opacity, 1.0), "IME completion starts a fresh two-minute draft interval")
	tick(4.0)
	check(not chat.visible and chat.input.text == "继续写这段草稿", "completed IME draft may fold while retaining its text")

	# Waiting is protected even when no tokens arrive or a streamed prefix is done.
	for request_kind in ["chat", "proactive", "test"]:
		fresh(); service.busy = true; service.request_kind = request_kind; service.state_changed.emit()
		tick(180.0)
		check(chat.visible and is_zero_approx(chat._idle), request_kind + " waiting without a first token never expires")
		service.cancel(); tick(29.75)
		check(chat.visible and is_equal_approx(chat._opacity, 1.0), request_kind + " cancellation starts a fresh empty interval")
		tick(4.0)
		check(not chat.visible and timeouts.size() == 1, request_kind + " canceled empty Window eventually hides")
	fresh(); send_message("等待猫猫回复"); tick(180.0)
	check(chat.visible and service.busy and is_zero_approx(chat._idle), "a submitted full-chat turn is protected before its first token")
	service.delta.emit("我在这里"); tick(90.0)
	check(chat.visible and service.busy and chat._reveal.done() and is_zero_approx(chat._idle), "waiting remains protected after all received text has revealed")
	service.finish("慢慢聊。".repeat(30))
	check(not service.busy and chat.is_speech_revealing(), "completed reply continues revealing its unread suffix")
	for frame in 200:
		if chat._reveal.done(): break
		tick(0.25)
		check(chat.visible and is_zero_approx(chat._idle), "every reveal frame including the last is excluded from idle")
	check(chat._reveal.done(), "completed full-chat reply finishes its reveal")
	var completed_history := service.history.duplicate(true)
	tick(59.75)
	check(chat.visible and is_equal_approx(chat._opacity, 1.0), "long reply receives sixty seconds after its last revealed character")
	tick(4.0)
	check(not chat.visible and service.history == completed_history and timeouts.size() == 1, "completed long reply hides once without losing history")
	chat.open_panel()
	check(chat.transcript.visible_characters == -1 and not chat.is_speech_revealing(), "reopening the completed reply never reveals it again")

	# Failed/canceled requests release waiting protection and retain any new draft.
	for interruption in ["cancel", "error"]:
		for draft in ["", "等待期间写下的新草稿"]:
			fresh(); send_message("本次提交"); tick(90.0)
			if not draft.is_empty(): edit_draft(draft)
			service.call(interruption)
			check(not service.busy and chat.input.text == draft, interruption + " preserves the current unsent draft")
			var limit := 30.0 if draft.is_empty() else 120.0
			tick(limit - 0.25)
			check(chat.visible and is_equal_approx(chat._opacity, 1.0), interruption + " starts the appropriate fresh idle interval")
			tick(4.0)
			check(not chat.visible and chat.input.text == draft and timeouts.size() == 1, interruption + " folds once without changing unsent text")

	# Closing an in-flight request must never reopen when the hidden result arrives.
	fresh(); send_message("关闭后完成"); chat.hide()
	service.delta.emit("迟到片段"); service.finish("迟到的完整回复")
	tick(180.0)
	check(not chat.visible and timeouts.is_empty() and service.history.back().text == "迟到的完整回复", "late completion updates history while the manually closed Window stays hidden")
	chat.open_panel()
	check(chat.transcript.text.contains("迟到的完整回复") and chat.transcript.visible_characters == -1 and not chat.is_speech_revealing(), "hidden completion opens fully rendered with no replay")
	tick(34.0)
	check(not chat.visible and timeouts.size() == 1, "reopened late completion observes the normal short idle period")
	service.delta.emit("外部片段"); service.reply_completed.emit("外部完成", false); service.state_changed.emit(); tick(180.0)
	check(not chat.visible and timeouts.size() == 1, "post-timeout service events neither reopen nor emit another idle close")
	chat.queue_free(); service.queue_free(); await process_frame
	print("Full chat idle: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
