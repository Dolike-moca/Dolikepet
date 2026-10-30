extends SceneTree
## Local Window events and in-memory fixtures only: no global input, user data or network.
const Card = preload("res://scripts/proactive_card.gd")
class FixtureCard extends Card:
	var composing_ime := false
	var pointer_position := Vector2i(100, 100)
	func _ime_composing() -> bool: return composing_ime
	func _pointer_position() -> Vector2i: return pointer_position
class Bridge extends RefCounted:
	func show_companion_without_activation(_handle: int) -> bool: return true
class Service extends Node:
	signal delta(text: String)
	signal reply_completed(text: String, proactive: bool)
	signal failed(message: String)
	signal state_changed
	var settings := {"auth_method":"api_key", "speech_speed":2}
	var history: Array = []
	var busy := false
	var request_kind := ""
	var status := "准备好了"
	var _request_serial := 0
	func billing_label() -> String: return "测试服务"
	func send_message(text: String, _context: Dictionary = {}) -> bool:
		if busy: return false
		_request_serial += 1; busy = true; request_kind = "chat"
		history.append({"role":"user","text":text}); state_changed.emit(); return true
	func finish(text: String) -> void:
		history.append({"role":"assistant","text":text}); busy = false; request_kind = ""
		reply_completed.emit(text, false); state_changed.emit()
	func cancel() -> void:
		busy = false; request_kind = ""; status = "已停止"; state_changed.emit()
	func error() -> void:
		busy = false; request_kind = ""; status = "模拟断网"; failed.emit(status); state_changed.emit()
var checks := 0
var failures: Array[String] = []
var card: FixtureCard
var service: Service
var notices: Array[String] = []
var spoken: Array[String] = []
var anchor := Rect2i()
var output_path := ""
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("CHAT IDLE: " + message)
func tick(seconds: float, step: float = 0.25) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var dt := minf(remaining, minf(step, 0.25))
		card.advance(dt, true); remaining -= dt
func fresh(text: String = "猫猫在这里。", revealed: bool = true) -> void:
	service.busy = false; service.request_kind = ""
	card.set_draft(""); card.reset_session(); card.hover_override = 0; card.composing_ime = false
	check(card.present(text, "rest", anchor, root.current_screen, text.length() if revealed else 0), "fixture invitation opens")
	notices.clear()
func begin_draft(text: String) -> void:
	card.begin_reply(); card.set_draft(text); card._draft_edited()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_path = arg.trim_prefix("--out=")
	root.title = "Dolike idle fixture"
	root.size = Vector2i(200, 200)
	service = Service.new(); root.add_child(service)
	card = FixtureCard.new(); card.native_bridge = Bridge.new(); root.add_child(card); card.setup(service)
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	anchor = Rect2i(area.position + Vector2i(100,250), Vector2i(300,300))
	card.dismissed.connect(func(reason: String): notices.append(reason))
	card.spoken.connect(func(text: String): spoken.append(text))
	await process_frame
	check(Card.SHORT_IDLE_SECONDS == 30.0 and Card.LONG_IDLE_SECONDS == 60.0 and Card.DRAFT_IDLE_SECONDS == 120.0, "idle periods follow the selected 30/60/120 second policy")
	check(Card.LONG_REPLY_CHARACTERS == 120 and Card.FADE_SECONDS == 3.0 and Card.RESTORE_SECONDS == 0.2, "long threshold and visual transition durations are explicit")

	# The boundary uses characters, including Chinese, rather than UTF-8 bytes.
	for length in [1, 119, 120, 121]:
		fresh("喵".repeat(length))
		var deadline := 30.0 if length < 120 else 60.0
		tick(deadline - 0.25)
		check(card.visible and is_equal_approx(card._opacity, 1.0), "%d characters stay opaque until their full idle interval" % length)
		tick(1.25)
		check(card.visible and card._opacity > 0.0 and card._opacity < 1.0, "%d characters begin a gradual fade after the deadline" % length)
		tick(3.0)
		check(not card.visible and not card._active and notices == ["idle_timeout"], "%d characters finish once with neutral idle_timeout" % length)
		check(card._entries == ["喵".repeat(length)], "idle timeout retains the displayed text")

	# Fade samples must be continuous and the native window must remain until zero.
	fresh(); tick(30.0)
	var previous_opacity: float = card._opacity
	var fade_steps := 0
	while card._active and fade_steps < 40:
		check(card.visible and card._opacity > 0.0, "partially faded content remains visible")
		check(is_equal_approx(card.panel.modulate.a, card._tip.modulate.a) and is_equal_approx(card.panel.modulate.a, card._opacity), "bubble panel and pointer share identical opacity")
		tick(0.1, 0.1)
		check(card._opacity <= previous_opacity + 0.000001 and previous_opacity-card._opacity <= 0.1, "fade opacity decreases continuously")
		previous_opacity = card._opacity; fade_steps += 1
	check(fade_steps >= 27 and fade_steps <= 31 and is_zero_approx(card._opacity), "fade lasts approximately three seconds before hiding")
	tick(180.0); card.advance(0.25, false); card.advance(0.25, true)
	service.delta.emit("迟到片段"); service.reply_completed.emit("外部迟到回复", false)
	check(not card.visible and not card._active and notices == ["idle_timeout"], "hidden timeout never reopens or emits twice when time/host state/foreign replies change")

	# Entering can reverse a fade; leaving a mouse parked there is not activity.
	fresh(); tick(31.5)
	var faded: float = card._opacity
	if not output_path.is_empty():
		DirAccess.make_dir_recursive_absolute(output_path)
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		check(card.get_texture().get_image().save_png(output_path.path_join("chat-idle-midfade.png")) == OK, "half-faded bubble screenshot is written to the isolated review directory")
	card.hover_override = 1; tick(0.05, 0.05)
	check(card.visible and card._opacity > faded and card._opacity < 1.0 and is_zero_approx(card._idle), "mouse entry reverses fade continuously and clears elapsed idle")
	check(is_equal_approx(card.panel.modulate.a, card._tip.modulate.a), "mouse entry restore keeps pointer and body opacity synchronized")
	tick(0.15, 0.05)
	check(is_equal_approx(card._opacity, 1.0), "mouse entry restores full opacity within 0.2 seconds")
	tick(20.0)
	check(card.visible and card._idle >= 20.0 and notices.is_empty(), "stationary hover continues the idle clock")
	card.hover_override = 0; tick(9.5)
	check(is_equal_approx(card._opacity, 1.0) and card._idle >= 29.5, "mouse exit neither resets nor extends the current idle interval")
	tick(4.0)
	check(not card.visible and notices == ["idle_timeout"], "mouse entry receives one interval before fading normally")
	fresh(); card.hover_override = 1; tick(0.25); tick(34.0)
	check(not card.visible and notices == ["idle_timeout"], "stationary hovered bubble eventually hides without requiring mouse exit")

	# Whitespace does not inflate the reading interval into a long reply.
	for text in ["喵".repeat(60) + " \n\t".repeat(8) + "喵".repeat(59), " \n\t".repeat(40) + "喵" + " \n\t".repeat(40)]:
		fresh(text); tick(29.75)
		check(card.visible and is_equal_approx(card._opacity, 1.0), "whitespace-heavy short content stays opaque for thirty seconds")
		tick(4.0)
		check(not card.visible and notices == ["idle_timeout"], "only non-whitespace characters qualify as a long reply")

	# User focus is not activity forever, but input/click/scroll are activity.
	fresh(); card.begin_reply(); await process_frame
	check(card.input.has_focus() and card.engaged(), "fixture composer has actual local control focus")
	tick(29.75)
	check(is_equal_approx(card._opacity, 1.0), "focused empty composer receives the normal reading interval")
	tick(4.0)
	check(not card.visible and not card._active and notices == ["idle_timeout"], "focus and engaged state alone cannot make the bubble permanent")
	fresh(); tick(29.0)
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	card._input(click)
	check(is_zero_approx(card._idle), "click resets idle")
	tick(29.0)
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
	card._input(wheel)
	check(is_zero_approx(card._idle), "scroll resets idle")
	tick(29.0)
	var motion := InputEventMouseMotion.new(); motion.relative = Vector2(2, 1)
	card.hover_override = 1; card.pointer_position += Vector2i(2, 1)
	card.push_input(motion); tick(0.05, 0.05)
	check(is_zero_approx(card._idle), "local mouse movement resets idle")
	tick(10.0); card.push_input(motion); tick(0.05, 0.05)
	check(card._idle >= 10.0, "stationary screen pointer events do not repeatedly reset idle")
	card.hover_override = 0
	tick(19.0)
	check(is_equal_approx(card._opacity, 1.0) and notices.is_empty(), "click, scroll and movement each grant a fresh reading interval")

	# Waiting pauses before and after an empty stream; revealing also starts a new clock.
	fresh(); begin_draft("等猫猫回复"); card._send_message(); tick(180.0)
	check(card.visible and card._waiting and is_zero_approx(card._idle), "waiting without a first token never consumes idle")
	service.delta.emit("我在这里"); tick(90.0)
	check(card.visible and card._waiting and card._reveal.done() and is_zero_approx(card._idle), "waiting after the received prefix finishes still pauses idle")
	service.finish("猫猫会一直陪着大人慢慢聊。".repeat(8))
	check(not card._waiting and not card._reveal.done(), "completion with unread letters still reveals normally")
	for frame in 200:
		if card._reveal.done(): break
		tick(0.25)
		check(card.visible and is_zero_approx(card._idle), "reveal time including its last frame is excluded from idle")
	check(card._reveal.done(), "completed reply finishes revealing within its text duration")
	var history_before := service.history.duplicate(true)
	var answer_before: String = card.transcript.text
	tick(29.75)
	check(is_equal_approx(card._opacity, 1.0), "short completed reply gets thirty seconds after its final character")
	tick(4.0)
	check(not card.visible and service.history == history_before and card._entries.back() == answer_before, "completed idle dismissal keeps history and last answer")
	check(card.reopen() and card.visible and card.is_composing() and card._entries.back() == answer_before, "explicit reopen restores the same conversation and accepts a new reply")
	check(not card.is_speech_revealing() and spoken.is_empty(), "reopening old conversation neither replays text nor restarts speech")

	# A long local utterance may reveal for longer than the short timeout.
	fresh("慢".repeat(300), false); service.settings.speech_speed = 0; tick(25.0)
	check(card.visible and not card._reveal.done() and is_zero_approx(card._idle), "slow long text is protected for its whole reveal")
	for frame in 200:
		if card._reveal.done(): break
		tick(0.25)
	check(card._reveal.done(), "slow long text finishes revealing")
	tick(59.75)
	check(is_equal_approx(card._opacity, 1.0), "long text gets sixty seconds after reveal completes")
	tick(4.0)
	check(not card.visible, "long text eventually folds after its reading interval")
	service.settings.speech_speed = 2

	# Drafts last two minutes and remain available after folding.
	fresh(); begin_draft("这段草稿稍后继续写"); tick(119.75)
	check(card.visible and is_equal_approx(card._opacity, 1.0), "unsent draft is opaque for the full two minutes")
	tick(4.0)
	check(not card.visible and card.has_draft() and card.input.text == "这段草稿稍后继续写" and notices == ["idle_timeout"], "draft timeout hides without deleting unsent text")
	check(not card.present("不能覆盖草稿", "rest", anchor, root.current_screen), "new proactive invitation cannot replace a folded draft")
	check(card.reopen() and card.is_composing() and card.input.text == "这段草稿稍后继续写", "reopen continues the saved draft")
	tick(119.0); card.input.text += "。"; card._draft_edited()
	check(is_zero_approx(card._idle), "editing draft resets the full two minute clock")
	tick(119.75)
	check(is_equal_approx(card._opacity, 1.0), "edited draft gets a complete new interval")

	# Route real key events through this Window only, never the global keyboard.
	await process_frame
	card.input.grab_focus(); card.input.set_caret_column(card.input.text.length())
	var typed := InputEventKey.new(); typed.keycode = KEY_A; typed.unicode = 97; typed.pressed = true
	var before_key: String = card.input.text
	card.push_input(typed)
	await process_frame
	check(card.input.text == before_key + "a" and is_zero_approx(card._idle), "local key dispatch edits TextEdit and resets idle through connected signals")
	var navigation := InputEventKey.new(); navigation.keycode = KEY_LEFT; navigation.pressed = true
	tick(15.0); card.push_input(navigation)
	check(is_zero_approx(card._idle), "navigation key resets idle even when draft text is unchanged")

	# IME uses the production pause boundary with an isolated composition fixture.
	card.composing_ime = true; tick(180.0)
	check(card.visible and is_zero_approx(card._idle), "ongoing IME composition pauses and resets timeout")
	var confirm := InputEventKey.new(); confirm.keycode = KEY_ENTER; confirm.pressed = true
	var sent_before := service._request_serial
	card._input_key(confirm)
	check(service._request_serial == sent_before and card.has_draft(), "plain Enter during IME confirmation never sends the draft")
	card.composing_ime = false; tick(119.75)
	check(is_equal_approx(card._opacity, 1.0), "IME completion restarts a full draft interval")
	tick(4.0)
	check(not card.visible and card.has_draft(), "completed IME draft can eventually fold while retaining text")

	# Cancellation and errors restore the submitted draft, then follow draft timing.
	for interrupted_by in ["cancel", "error"]:
		fresh(); begin_draft("重试时保留这句原话"); card._send_message(); tick(50.0)
		service.call(interrupted_by)
		check(not card._waiting and card.is_composing() and card.input.text == "重试时保留这句原话", interrupted_by + " restores the original submitted draft")
		tick(119.75)
		check(card.visible and is_equal_approx(card._opacity, 1.0), interrupted_by + " starts a fresh two minute retry period")
		tick(4.0)
		check(not card.visible and card.input.text == "重试时保留这句原话" and notices == ["idle_timeout"], interrupted_by + " folds once without discarding the retry draft")
	card.queue_free(); service.queue_free(); await process_frame
	print("Chat idle: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
