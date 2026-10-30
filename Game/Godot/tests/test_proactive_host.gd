extends SceneTree
## Actual pet/Windows integration with fake AI and coarse activity. No real input or files.
const Scheduler = preload("res://scripts/proactive_scheduler.gd")
class Responder extends Node:
	signal delta(text: String)
	signal completed(text: String)
	signal failed(message: String)
	signal canceled
	var busy := false
	var payload := {}
	var starts := 0
	func start(_key: String, body: Dictionary) -> bool:
		payload = body; busy = true; starts += 1; return true
	func cancel() -> void:
		busy = false; canceled.emit()
	func finish(text: String) -> void:
		busy = false; completed.emit(text)
	func error() -> void:
		busy = false; failed.emit("模拟网络不可用")
class Keys extends RefCounted:
	func setup(_model: Object, _root: String) -> void: pass
	func has_key() -> bool: return true
	func load_key() -> String: return "fixture-only-no-real-key"
	func save_key(_value: String) -> Error: return OK
	func clear_key() -> Error: return OK
class PassiveBridge extends RefCounted:
	var shown := 0
	var allow_show := true
	func show_companion_without_activation(_handle: int) -> bool:
		shown += 1; return allow_show

var failures: Array[String] = []
var checks := 0
var app
var responder: Responder
var bridge := PassiveBridge.new()
var fixture_path := ""
var activity := {"idle_seconds":0.0,"locked":false,"fullscreen":false}

func verify(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("PROACTIVE HOST: fixture timed out"); quit(1))
	call_deferred("run")

func make_host() -> void:
	app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = fixture_path.path_join("pet.cfg")
	responder = Responder.new()
	app.ai_service.configure_dependencies(responder, Keys.new())
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false)
	root.mouse_passthrough = true
	await process_frame
	app.ai_service._network_allowed = true # The only transport is the above in-memory responder.
	app.bubble.hide(); app.bowl_enabled = false; app.bowl_window.hide()
	app.bowl_summon.finish(); app.roaming.configure("off"); app.idle_sitting.enabled = false
	app.behavior.command("normal")
	app.proactive_companion.environment_enabled = true
	app.proactive_companion.activity_override = func(): return activity.duplicate()
	app.proactive_companion.native_bridge = bridge
	app.proactive_companion.card.native_bridge = bridge
	app.proactive_companion.card.hover_override = 0
	app.ai_service.apply_settings({"enabled":false,"proactive":true,"quiet_start":0,"quiet_end":0,"auth_method":"api_key"})
	app.proactive_companion.tick(1.0, true)

func reset_card() -> void:
	app.ai_service.cancel()
	app.proactive_companion._cancel_pending()
	app.proactive_companion.card.set_draft("")
	app.proactive_companion.card.reset_session()
	app._clear_ai_speech(); app.bubble.hide()
	app.proactive_companion.tick(0.01, true)

func fresh_invitation(reason: String = "rest") -> Dictionary:
	# Exercise the real trigger against a bounded, deterministic simulated history.
	var schedule = Scheduler.new()
	schedule.configure(app.ai_service.settings)
	schedule.random_source = func(): return 0.0
	var count := 3601 if reason == "rest" else 302
	var now := Time.get_unix_time_from_system()
	var date := Time.get_datetime_dict_from_system()
	var snapshot := {"idle_seconds":0.0,"locked":false,"fullscreen":false,"allowed":true,"dialog_open":false,
		"local_day":"%04d-%02d-%02d" % [date.year,date.month,date.day],"local_hour":int(date.hour)}
	var invitation := {}
	for index in count:
		snapshot.now_unix = now - count + index
		invitation = schedule.advance(1.0, snapshot)
	if reason == "game":
		schedule.note_game_finished("juggle", 49)
		snapshot.now_unix = now
		invitation = schedule.advance(1.0, snapshot)
	app.proactive_companion.scheduler = schedule
	return invitation

func begin(reason: String = "rest") -> void:
	var invitation := fresh_invitation(reason)
	verify(not invitation.is_empty(), "fixture produces a real " + reason + " invitation")
	app.proactive_companion._start(invitation)

func present() -> void:
	for index in 9: app._update_ai_presentation(0.25, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	await process_frame

func run() -> void:
	fixture_path = ProjectSettings.globalize_path("res://../../_work/tests/proactive-host/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(fixture_path)
	await make_host()
	verify(app.pet.available, "actual pet rig loads")
	verify(app.ai_service.external_proactive, "one coordinator owns proactive timing")
	app.ai_service.apply_settings({"proactive":false})
	app.proactive_companion._activity = {"idle_seconds":0.0,"locked":true,"fullscreen":true}
	app.proactive_companion._sample_age = 0.0
	app._menu_action(25)
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.proactive_companion.card.visible and app.proactive_companion.card.is_composing(), "manual small chat works when proactive reminders are off and refreshes stale initial activity")
	reset_card()
	app.ai_service.apply_settings({"proactive":true})
	app.proactive_companion.scheduler.random_source = func(): return 0.0
	app.catch_game.awarded.emit({"game":"catch","at":10.0,"streak":1,"base":9,"bonus":0,"walls":3,"multiplier":1,"delta":9,"total":9})
	app.catch_game.round_finished.emit({"game":"catch","at":12.0,"streak":1,"total":9,"reason":"fixture"})
	verify(app.proactive_companion.scheduler._pending_game.get("context", {}) == {"game":"catch","score":9}, "catch round sends its actual final score to invitation timing")
	app.juggle_game.awarded.emit({"game":"juggle","at":20.0,"streak":1,"base":28,"bonus":0,"walls":2,"multiplier":7,"delta":28,"total":28})
	app.juggle_game.round_finished.emit({"game":"juggle","at":22.0,"streak":1,"total":28,"reason":"fixture"})
	verify(app.proactive_companion.scheduler._pending_game.get("context", {}) == {"game":"juggle","score":28}, "juggle round does not reuse the catch score")
	var talk_before: float = app.behavior.talk_until
	begin()
	# Use a known multi-sentence utterance for the in-progress speech handoff;
	# short valid topic variants can finish before the two-second expansion.
	app.proactive_companion._prepare("要不要休息一小会儿？起来活动活动，我在这里陪你喵。")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.ai_bubble_owned and app.bubble_label.text.contains("休息"), "offline reminder first appears as a speaking bubble")
	verify(not app.proactive_companion.card.visible, "input card does not appear before lead-in")
	for index in 6: app._update_ai_presentation(0.25, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(not app.proactive_companion.card.visible, "card still waits before two seconds")
	for index in 2: app._update_ai_presentation(0.25, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	await process_frame
	var card = app.proactive_companion.card
	verify(card.visible and card.unfocusable and not card.exclusive, "two-second lead opens a passive nonmodal bubble")
	verify(not card.is_composing() and card.transcript.visible and card.reply_button.visible and not card.input.is_visible_in_tree(), "automatic invitation starts as one reply bubble until the user chooses reply")
	verify(not app.ai_bubble_owned and app.behavior.talk_until == talk_before, "lead ends without taking a behaviour lock")
	verify(app.ai_compact_speech and not app.ai_speech.current.is_empty(), "expanding the same invitation keeps its speech running on the compact surface")
	verify(responder.starts == 0, "disabled AI uses local fallback without a paid request")
	card._dismiss_user()
	verify(app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty(), "closing an expanded invitation stops its remaining spoken text")
	verify(app.proactive_companion.scheduler.dump_state().ignore_streak == 1, "closing an unanswered card counts one ignored invitation")
	reset_card(); begin(); bridge.allow_show = false
	await present()
	verify(not card.visible and app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty(), "a failed native expansion cancels speech instead of reading an invisible invitation")
	bridge.allow_show = true
	reset_card(); begin()
	app._menu_action(25)
	await process_frame
	verify(card.visible and card.is_composing() and card.input.is_visible_in_tree() and card.send.is_visible_in_tree(), "actual right-click menu action opens the shared bubble directly in compose mode")
	verify(not app.ai_chat.visible and not card.transcript.is_visible_in_tree(), "manual small-chat entry does not open the separate history window or a stale reply")
	verify(app.proactive_companion._pending.is_empty(), "manual opening cancels the unshown proactive invitation")
	for index in 10: app._update_ai_presentation(0.25, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(card.visible and card.is_composing() and not app.bubble.visible, "late proactive lead-in cannot overwrite a manually opened composer")
	reset_card(); begin("game"); await present()
	card._quick_action("snooze")
	var snooze: Dictionary = app.proactive_companion.scheduler.dump_state().snooze
	verify(not card.visible and not snooze.is_empty() and snooze.context.score == 49, "snooze preserves the actual game context")
	reset_card(); begin(); await present()
	card._quick_action("quiet_today")
	var state: Dictionary = app.proactive_companion.scheduler.dump_state()
	verify(not card.visible and state.quiet_today == state.day, "today quiet is delivered to persistent scheduler state")
	reset_card(); begin(); await present()
	card._quick_action("accepted")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.ai_compact_speech and app.ai_speech.current.contains("好呀"), "local accepted response drives speech without a duplicate head bubble")
	card._dismiss_user()
	verify(not card.visible and not card.engaged() and not card.has_draft(), "closing an acknowledged empty card does not block future invitations forever")
	reset_card(); begin(); await present()
	card.begin_reply()
	verify(app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty(), "choosing to type stops the old invitation speech")
	verify(card.is_composing() and card.input.is_visible_in_tree() and not card.transcript.is_visible_in_tree(), "reply button transitions the passive invitation to the compact composer")
	card.input.insert_text_at_caret("等我忙完这件事，再陪我聊聊。")
	await process_frame
	verify(card.has_draft(), "editing marks card as engaged")
	var saved_draft: String = card.input.text
	app.proactive_companion.tick(0.1, false)
	verify(not card.visible and card.input.text == saved_draft, "physical interaction hides card while preserving draft")
	app.dragging = true; app.drag_moved = true
	app.drag_pointer = root.position + Vector2i(150,150); app._begin_grab()
	verify(app.falling.body.held, "pet can still be picked up with an engaged conversation")
	app._update_drag_pointer(app.drag_pointer + Vector2i(35,-20), false)
	verify(not app.dragging and not app.falling.body.held, "release remains immediate")
	app.proactive_companion.tick(0.1, true)
	verify(card.visible and card.input.text == saved_draft and card.unfocusable, "engaged card returns passively with the same draft when safe")
	card._dismiss_user()
	app.proactive_companion._start({"reason":"game","context":{"game":"catch","score":1}})
	verify(not card.visible and card.input.text == saved_draft and app.proactive_companion._pending.is_empty(), "new reminder never overwrites a closed draft")
	app.proactive_companion.tick(0.7, true)
	app.proactive_companion._save()
	var path: String = app.settings_path + ".ai/invitations/companion.json"
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	verify(stored.get("draft") == saved_draft, "draft is saved in the isolated companion folder")
	app.queue_free(); await process_frame
	await make_host()
	card = app.proactive_companion.card
	verify(card.input.text == saved_draft and not card.visible, "restart restores draft without opening or sending it")
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = area.position + Vector2i(400,200)
	app._menu_action(25)
	await process_frame
	verify(card.visible and card.is_composing() and card.input.text == saved_draft, "right-click manual reopen restores the persisted draft in compose mode")
	verify(card._pet_rect == Rect2i(root.position, root.size), "reopened draft is anchored to the current pet after restart")
	card.history_requested.emit()
	await process_frame
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.ai_chat.visible and not card.visible and card.input.text == saved_draft, "history entry opens the existing conversation window while preserving and suspending the bubble draft")
	app.ai_chat.hide()
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(card.visible and card.unfocusable and card.input.text == saved_draft, "closing history passively restores the same bubble draft")
	app._menu_action(24)
	await process_frame
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.ai_chat.visible and not card.visible and card.input.text == saved_draft, "right-click history action opens the full record while the small-chat draft remains suspended")
	app.ai_chat.hide()
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	card.memory_requested.emit()
	await process_frame
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.ai_memory.visible and not card.visible and card.input.text == saved_draft, "memory entry is wired without discarding the bubble draft")
	app.ai_memory.hide()
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	card.settings_requested.emit()
	await process_frame
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(app.settings_window.visible and app.settings_window.current_page == 3 and not card.visible, "bubble settings entry opens the AI page and suspends the small conversation")
	app.settings_window.hide()
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(card.visible and card.unfocusable and card.input.text == saved_draft, "closing settings restores the draft without taking keyboard focus")
	reset_card()
	app.ai_service.apply_settings({"enabled":true,"proactive":true})
	app.proactive_companion.tick(0.01, true)
	app._menu_action(24)
	app.ai_chat.input.text = "完整窗口中已提交的问题"
	app.ai_chat._send_message()
	var full_request_count: int = responder.starts
	app.ai_chat.input.text = "完整窗口里尚未发送的草稿"
	app._menu_action(25)
	verify(not app.ai_chat.visible and app.ai_chat.input.text == "完整窗口里尚未发送的草稿" and app.ai_service.busy and responder.starts == full_request_count, "right-click small-chat action hides the full window without clearing its draft or canceling its in-flight request")
	card.set_draft("暂存在小气泡的新问题")
	card._send_message()
	verify(card.visible and card.is_composing() and card.send.disabled and not card._waiting and responder.starts == full_request_count, "small composer cannot replace or claim another chat window's in-flight request")
	responder.delta.emit("完整窗口的回复还在继续。")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(card.visible and card.is_composing() and not app.bubble.visible and card.input.text == "暂存在小气泡的新问题", "another window's stream cannot overlay or overwrite the compact composer")
	responder.finish("完整窗口的回复已保存。")
	verify(app.ai_service.history.back().text == "完整窗口的回复已保存。" and not card.send.disabled and not card._waiting, "background full-window reply is retained in history and releases the composer for its own request")
	card._send_message()
	verify(card._waiting and app.ai_compact_speech and responder.starts == full_request_count + 1, "the next accepted small-bubble request obtains compact presentation ownership")
	responder.finish("现在轮到小气泡啦。")
	verify(card.transcript.text.contains("现在轮到小气泡啦。") and not card.transcript.text.contains("完整窗口") and not card.is_composing(), "small-bubble response remains single-round after switching from the full chat")
	reset_card()
	begin()
	verify(app.ai_service.busy and app.ai_service.request_kind == "proactive", "connected reminder requests GPT wording")
	responder.delta.emit("先歇")
	verify(app.ai_speech.queue.is_empty() and not card.visible, "partial proactive text does not race the lead-in")
	responder.finish("先歇一小会儿吧，我在这里陪你。")
	await present()
	verify(card.visible and card.transcript.text.contains("先歇一小会儿"), "completed GPT wording goes through the same bubble-card transition")
	card.begin_reply()
	card.input.insert_text_at_caret("我先休息一下")
	await process_frame
	card._send_message()
	verify(not card.is_composing() and card._waiting and card.input.text.is_empty() and app.ai_service.busy, "send replaces the composer with a waiting reply in the same bubble")
	verify(card.size.x <= 360 and card.size.y < 350 and not card.input.is_visible_in_tree(), "sending keeps the compact single-round surface instead of expanding a history panel")
	responder.delta.emit("好呀。")
	var reply_pose := {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}
	app._update_ai_presentation(0.1, reply_pose, true)
	verify(card.transcript.text.contains("好呀") and not card.transcript.text.contains("先歇一小会儿") and not card.transcript.text.contains("我先休息一下"), "streamed reply replaces the previous turn rather than displaying stacked history")
	verify(card.visible and not app.bubble.visible and not app.ai_bubble_owned and reply_pose.mouth > 0.0, "streamed bubble reply keeps the talking mouth without creating a duplicate old-style speech bubble")
	responder.finish("好呀，慢慢来。")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(card.transcript.text.contains("好呀，慢慢来。") and not card._waiting and card.reply_button.visible and not card.is_composing(), "completed reply exposes Reply while releasing its waiting state")
	verify(not app.bubble.visible and not app.ai_bubble_owned, "completion never replays the same message in a second head bubble")
	card.begin_reply()
	card.input.insert_text_at_caret("失败后仍然保留的草稿")
	await process_frame
	card._send_message()
	responder.error()
	verify(card.is_composing() and card.has_draft() and card.input.text == "失败后仍然保留的草稿" and not card._waiting, "failed accepted request restores its exact submitted draft to the composer")
	card._dismiss_user()
	app._menu_action(25)
	verify(card.visible and card.is_composing() and card.input.text == "失败后仍然保留的草稿", "closing and reopening after an error retains the recoverable draft")
	card.set_draft("等待回复时收起气泡")
	card._send_message()
	card._dismiss_user()
	responder.delta.emit("猫猫会等你回来。")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(not card.visible and not app.bubble.visible, "closing an in-flight compact reply does not redirect later chunks to the old head bubble")
	responder.finish("猫猫会等你回来。")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(not card.visible and not app.bubble.visible and not card._waiting, "a hidden compact reply can finish without reopening either surface")
	app._menu_action(25)
	verify(card.visible and card.is_composing() and card.input.text.is_empty(), "manual reopen after a finished hidden request returns to a fresh compact composer")
	reset_card(); begin()
	responder.error()
	await present()
	verify(card.visible and card.transcript.text.contains("休息"), "network failure falls back to a local invitation")
	reset_card(); begin()
	app.proactive_companion.tick(0.1, false)
	verify(app.proactive_companion._pending.is_empty() and not app.ai_service.busy, "physical interruption cancels an unfinished proactive request")
	app.ai_service.apply_settings({"enabled":false})
	app.proactive_companion.tick(0.01, true)
	begin()
	app.proactive_companion.tick(10.0, true)
	verify(not card.visible and app.proactive_companion._pending.is_empty(), "resume or long frame drops an unexpanded invitation")
	reset_card(); begin(); await present()
	card.begin_reply()
	card.input.insert_text_at_caret("我的草稿")
	await process_frame
	app.ai_service.clear_history()
	verify(not card.visible and card.input.text == "我的草稿" and not card.transcript.text.contains("休息"), "clearing dialogue resets card transcript but preserves unsent draft")
	await verify_settings_chat_gate()
	await verify_chat_roaming_pause()
	await verify_idle_shutdown()
	await verify_topic_invites()
	await verify_full_chat_idle()
	app.queue_free(); await process_frame
	for failure in failures: printerr("PROACTIVE HOST: " + failure)
	print("Proactive host: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func compact_session_state(card: Window) -> Dictionary:
	return {"active":card._active,"waiting":card._waiting,"suspended":card._suspended,
		"draft":card.input.text,"submitted":card._submitted_text,"owner":card._owner_serial,
		"composing":card._composing,"entries":card._entries.duplicate(),"streamed":card._streamed}

func verify_settings_chat_gate() -> void:
	reset_card()
	app.settings_window.hide(); app.ai_chat.hide(); app.ai_memory.hide()
	app.ai_service.apply_settings({"enabled":true,"proactive":false})
	var card = app.proactive_companion.card
	app._menu_action(25)
	card.set_draft("等设置关掉后再发出的草稿")
	card._dismiss_user()
	app._menu_action(14)
	app.settings_window._select_page(3)
	app.settings_window.ai_panel.personality.text = "尚未保存的说话风格：猫猫保持轻松"
	var saved_style: String = app.ai_service.settings.personality
	var draft_style: String = app.settings_window.ai_panel.personality.text
	var compact_before := compact_session_state(card)
	var pending_before: Dictionary = app.proactive_companion._pending.duplicate(true)
	var request_count: int = responder.starts
	var visibility := {"compact":0,"history":0,"settings_hidden":0}
	var compact_changed := func():
		if card.visible: visibility.compact += 1
	var history_changed := func():
		if app.ai_chat.visible: visibility.history += 1
	var settings_changed := func():
		if not app.settings_window.visible: visibility.settings_hidden += 1
	card.visibility_changed.connect(compact_changed)
	app.ai_chat.visibility_changed.connect(history_changed)
	app.settings_window.visibility_changed.connect(settings_changed)
	app._menu_action(25)
	verify(visibility.compact == 0 and not card.visible, "settings guard prevents even a transient small-chat Window.show event")
	verify(app.bubble.visible and app.bubble_label.text.contains("现在不行喵") and app.bubble_label.text.contains("设置"), "blocked chat shows the promised short cat reply")
	app._menu_action(24)
	card.history_requested.emit()
	app.settings_window.ai_panel.chat.pressed.emit()
	await process_frame
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(visibility.compact == 0 and visibility.history == 0 and not card.visible and not app.ai_chat.visible, "menu, bubble history and settings-chat routes all refuse before displaying either window")
	verify(app.settings_window.visible and visibility.settings_hidden == 0 and app.settings_window.ai_panel.personality.text == draft_style and app.ai_service.settings.personality == saved_style, "blocked chat neither hides settings nor saves or replaces its unsaved draft")
	verify(compact_session_state(card) == compact_before and app.proactive_companion._pending == pending_before and responder.starts == request_count, "blocked chat preserves compact draft and pending session without new requests")
	app.settings_window.mode = Window.MODE_MINIMIZED
	app._menu_action(25)
	verify(visibility.compact == 0 and visibility.history == 0 and responder.starts == request_count, "minimizing settings does not bypass the chat-open guard")
	app.settings_window.mode = Window.MODE_WINDOWED
	app.settings_window.hide()
	app.bubble.hide()
	app._menu_action(25)
	await process_frame
	verify(card.visible and card.is_composing() and card.input.text == compact_before.draft, "closing settings restores normal manual chat with the original draft")
	reset_card()
	app._menu_action(25)
	card.set_draft("设置打开时仍在等待的消息")
	card._send_message()
	app._menu_action(14)
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	compact_before = compact_session_state(card)
	var serial: int = app.ai_service._request_serial
	request_count = responder.starts
	visibility.compact = 0; visibility.history = 0; visibility.settings_hidden = 0
	app.settings_window.ai_panel.personality.text = "第二份尚未保存的设置草稿"
	app._menu_action(25)
	app.settings_window.ai_panel.chat.pressed.emit()
	await process_frame
	verify(visibility.compact == 0 and visibility.history == 0 and not card.visible and app.settings_window.visible, "settings guard also prevents flashing while a compact reply is in flight")
	verify(compact_session_state(card) == compact_before and card.owns_reply() and app.ai_service.busy and app.ai_service._request_serial == serial and responder.starts == request_count, "blocked reopen leaves the submitted message, owner and in-flight reply unchanged")
	verify(app.settings_window.ai_panel.personality.text == "第二份尚未保存的设置草稿", "streaming-case guard preserves the settings draft")
	responder.finish("猫猫等大人关掉设置再聊。")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(not card.visible and visibility.compact == 0 and not card.owns_reply() and app.ai_service.history.back().text == "猫猫等大人关掉设置再聊。", "in-flight reply finishes and saves behind settings without opening a chat window")
	card.visibility_changed.disconnect(compact_changed)
	app.ai_chat.visibility_changed.disconnect(history_changed)
	app.settings_window.visibility_changed.disconnect(settings_changed)
	app.settings_window.hide()
	reset_card()

func advance_host(frames: int) -> bool:
	# Exercise the production frame coordinator, not just a reconstructed busy flag.
	var origin := root.position
	var stationary := true
	for index in frames:
		app._process(1.0 / 60.0)
		stationary = stationary and root.position == origin
		if index % 12 == 11: await process_frame
	return stationary

func verify_chat_roaming_pause() -> void:
	reset_card()
	app.settings_window.hide(); app.ai_chat.hide(); app.ai_memory.hide()
	app.ai_service.apply_settings({"enabled":true,"proactive":false})
	app.dragging = false; app.menu_holding = false; app.menu.hide()
	app.falling.cancel(); app.falling.configure(false)
	app.drag_motion.cancel(); app.landing.cancel(); app.bowl_hit.cancel()
	app.bowl_jump.cancel(); app.bowl_summon.finish()
	app.pickup.cancel(true); app.behavior.chewing.cancel(); app.behavior.command("normal")
	app.pet.set_seated(false); app.pet.sitting.amount = 0.0; app.pet.sitting.velocity = 0.0
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x + area.size.x / 2 - root.size.x / 2, area.end.y-root.size.y)
	app.falling.reposition(Vector2(root.position))
	app.roaming.configure("free"); app.roaming.rng.seed = 231
	app.roaming.state = "walking"; app.roaming.weight = 1.0; app.roaming.speed = root.size.x * 0.18
	app.roaming.cadence = 1.7; app.roaming.travel_position = Vector2(root.position)
	app.roaming.target_x = root.position.x + 150; app.roaming.direction = 1
	app._menu_action(25)
	var card = app.proactive_companion.card
	app.idle_sitting.configure(true,5.0,5.0)
	app.idle_sitting.needs_new_wait = false; app.idle_sitting.wait_seconds = 5.0; app.idle_sitting.elapsed = 4.99
	verify(await advance_host(48), "open manual bubble stops actual free-mode displacement, including leftover walking pose")
	verify(card.visible and card.is_open() and card.is_composing() and is_zero_approx(app.roaming.weight), "walking pose settles without permanently suspending its open composer")
	verify(not app.pet.sitting.seated and is_zero_approx(app.idle_sitting.elapsed), "open conversation prevents the expiring autonomous sit timer from interrupting it")
	verify(app.roaming.mode == "free", "conversation pause leaves the user's roaming preference unchanged")
	app.idle_sitting.enabled = false
	card.set_draft("收起后仍保留的草稿")
	card._dismiss_user()
	app.roaming.wait_remaining = 0.0
	verify(not await advance_host(50), "closing a bubble with an unsent draft allows the next free-mode trip")
	verify(card.has_draft() and not card.is_open() and app.roaming.mode == "free", "a saved hidden draft does not act as a permanent movement lock")
	reset_card(); app.roaming.interrupt(); app.roaming.weight = 0.0
	root.position.y = area.end.y-root.size.y; app.falling.reposition(Vector2(root.position))
	app.roaming.wait_remaining = 0.0
	verify(card.present("大人，猫猫陪你歇一会儿喵。", "rest", Rect2i(root.position,root.size),root.current_screen), "automatic bubble opens for the autonomous-motion regression")
	verify(await advance_host(36) and card.visible and not card.is_composing(), "passive automatic invitation also pauses real free-mode movement without hiding itself")
	card._dismiss_user()
	app._menu_action(24); app.roaming.wait_remaining = 0.0
	verify(await advance_host(36) and app.ai_chat.visible, "the full conversation window also pauses an expired walking deadline")
	app.ai_chat.hide(); app.roaming.wait_remaining = 0.0
	verify(not await advance_host(50), "closing the full conversation window releases the autonomous-motion pause")
	app._menu_action(25); card.set_draft("关闭后慢慢回复也可以")
	card._send_message(); card._dismiss_user(); app.roaming.wait_remaining = 0.0
	verify(card.owns_reply() and not card.is_open(), "a closed streaming turn remains owned but is no longer an open dialogue")
	verify(not await advance_host(50) and app.ai_service.busy, "an in-flight network reply behind a closed bubble does not freeze walking")
	responder.finish("猫猫收到啦。")
	app._menu_action(25); card.set_draft("拖动后接着聊")
	await advance_host(24)
	card.suspend()
	root.position += Vector2i(24,-12)
	app.falling.reposition(Vector2(root.position))
	verify(await advance_host(24) and card.visible and card.unfocusable and card.input.text == "拖动后接着聊", "an explicitly moved cat restores its open draft passively and stays in the new position")
	verify(card._pet_rect == Rect2i(root.position,root.size), "resumed stationary conversation uses the cat's latest anchor")
	reset_card(); app.roaming.configure("off")

func verify_idle_shutdown() -> void:
	reset_card()
	app.ai_chat.hide(); app.ai_memory.hide(); app.settings_window.hide()
	app.ai_service.apply_settings({"enabled":false,"proactive":true})
	begin(); await present()
	var card = app.proactive_companion.card
	var history_before: Array = app.ai_service.history.duplicate(true)
	var ignored_before: int = app.proactive_companion.scheduler.dump_state().ignore_streak
	for frame in 150: card.advance(0.25, true)
	verify(not card.visible and not card.is_open() and not app._chat_pauses_roaming(), "automatic invitation timeout releases the actual host's movement pause")
	verify(app.proactive_companion.scheduler.dump_state().ignore_streak == ignored_before and not app.proactive_companion.scheduler._awaiting_feedback, "idle shutdown closes invitation feedback without treating it as rejection")
	app._update_ai_presentation(0.1, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(not card.visible and not app.bubble.visible and app.ai_speech.current.is_empty(), "completed idle timeout cannot respawn the head bubble or old speech")
	verify(app.ai_service.history == history_before, "automatic shutdown keeps saved conversation history")
	app.ai_service.apply_settings({"proactive":false})
	app._menu_action(25)
	card.set_draft("暂时没发出的草稿，收起后继续聊。")
	var draft_before: String = card.input.text
	card.draft_changed.emit(draft_before)
	app.proactive_companion._save()
	for frame in 500: card.advance(0.25, true)
	verify(not card.visible and not card.is_open() and card.input.text == draft_before, "manual bubble times out after its draft grace period without clearing text")
	verify(app.proactive_companion._store.load_data().get("draft", "") == draft_before, "idle closure preserves the isolated persisted draft")
	app.roaming.configure("free"); app.roaming.wait_remaining = 0.0
	verify(not await advance_host(50), "automatic closure with a saved draft lets the cat walk again")
	app._menu_action(25)
	verify(card.visible and card.is_composing() and card.input.text == draft_before, "right-click reopens an automatically closed draft for continuing the conversation")
	reset_card(); app.roaming.configure("off")

func verify_topic_invites() -> void:
	reset_card()
	app.ai_chat.hide(); app.ai_memory.hide(); app.settings_window.hide()
	app.roaming.configure("off"); app.roaming.weight = 0.0; app.behavior.command("normal")
	app.ai_service.apply_settings({"enabled":false,"proactive":true,"include_pet_state":true})
	var original_size := root.size
	var original_canvas: int = app.size_canvas_pixels
	root.size = Vector2i.ONE * 600
	app.size_canvas_pixels = 300
	verify(app._ai_context().size_percent == 100.0, "topic context uses visible pet size instead of a reserved transparent canvas")
	app.size_canvas_pixels = 0
	verify(app._ai_context().size_percent == 200.0, "maximum pet size is represented as two hundred percent")
	app.ai_service._last_context = {"size_percent":100.0}
	app.proactive_companion._last_allowed = true
	var starts_before: int = responder.starts
	var size_target: int = app.size_change.target
	app.proactive_companion._start({"reason":"reconnect","context":{}})
	var topic: Dictionary = app.proactive_companion._pending.topic.duplicate(true)
	verify(topic.get("variant", "") != "grow" and app.ai_service._last_context.size_percent == 200.0, "coordinator chooses using current maximum size rather than its previous frame")
	verify(app.proactive_companion._pending.text == topic.fallback and responder.starts == starts_before, "disabled AI uses the selected local topic with no network request")
	await present()
	verify(app.proactive_companion.card.transcript.text == topic.fallback, "selected offline question reaches the actual shared bubble unchanged")
	verify(root.size == Vector2i.ONE * 600 and app.size_change.target == size_target and not app.size_change.pending(), "an interactive invitation does not resize or queue an action")
	reset_card()
	root.size = original_size; app.size_canvas_pixels = original_canvas
	app.ai_service.apply_settings({"enabled":true})
	app.proactive_companion._last_allowed = true
	starts_before = responder.starts
	app.proactive_companion._start({"reason":"reconnect","context":{}})
	topic = app.proactive_companion._pending.topic.duplicate(true)
	verify(responder.starts == starts_before + 1 and app.ai_service.request_kind == "proactive", "an eligible topic still uses exactly one existing proactive request")
	verify(str(responder.payload.input.back().content).contains(topic.prompt), "the model request carries the same selected topic as the pending invitation")
	responder.error()
	verify(app.proactive_companion._pending.text == topic.fallback and responder.starts == starts_before + 1, "failed model request retains its selected question without retry or another draw")
	await present()
	verify(app.proactive_companion.card.transcript.text == topic.fallback, "failed request fallback is presented through the same live bubble")
	reset_card(); app.ai_service.apply_settings({"enabled":false,"proactive":false})

func verify_full_chat_idle() -> void:
	reset_card()
	app.ai_chat.hide(); app.ai_memory.hide(); app.settings_window.hide()
	app.ai_service.apply_settings({"enabled":true,"proactive":false})
	app.dragging = false; app.menu_holding = false; app.menu.hide()
	app.behavior.command("normal"); app.idle_sitting.enabled = false
	var chat = app.ai_chat
	chat.set_process(false); chat.hover_override = 0
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x + area.size.x / 2 - root.size.x / 2, area.end.y - root.size.y)
	app.falling.reposition(Vector2(root.position))
	app.roaming.configure("free"); app.roaming.rng.seed = 347
	app.roaming.state = "walking"; app.roaming.weight = 1.0; app.roaming.speed = root.size.x * 0.18
	app.roaming.cadence = 1.7; app.roaming.travel_position = Vector2(root.position)
	app.roaming.target_x = root.position.x + 150; app.roaming.direction = 1
	app._menu_action(24)
	verify(chat.visible and app._chat_pauses_roaming() and await advance_host(36), "opening full chat pauses actual free-mode walking before its idle timeout")
	verify(chat.native_bridge == app.pet.model, "full-chat opacity uses the actual host's existing native bridge")
	chat.input.text = "完整窗口闲置收起前的一轮对话"
	chat._send_message()
	responder.finish("这轮回复已经保存，草稿也会等大人回来继续写。")
	for frame in 200:
		if chat._reveal.done(): break
		chat.advance(0.25)
		app._update_ai_presentation(0.25, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(chat.is_speech_complete() and app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty(), "full-window completed reveal releases its old speech before the idle reading period")
	chat.input.text = "完整窗口自动收起后仍可继续写的草稿"
	chat.input.text_changed.emit()
	var saved_draft: String = chat.input.text
	var saved_history: Array = app.ai_service.history.duplicate(true)
	var saved_transcript: String = chat.transcript.text
	var request_count: int = responder.starts
	var idle_closes := {"count":0}
	var closed := func(): idle_closes.count += 1
	chat.idle_closed.connect(closed)
	# Keep the production presentation coordinator running alongside the native
	# Window timer, just as both independent process callbacks run in the app.
	for frame in 500:
		chat.advance(0.25)
		app._update_ai_presentation(0.25, {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}, true)
	verify(not chat.visible and idle_closes.count == 1 and not app._chat_pauses_roaming(), "full-chat draft idle closure releases the host's movement pause exactly once")
	verify(chat.input.text == saved_draft and app.ai_service.history == saved_history and chat.transcript.text == saved_transcript, "full-chat automatic hide retains the exact draft and complete conversation")
	var after_hide_pose := {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0}
	app._update_ai_presentation(0.25, after_hide_pose, true)
	verify(not app.bubble.visible and not app.ai_bubble_owned and app.ai_speech.current.is_empty() and app.ai_speech.queue.is_empty() and is_zero_approx(float(after_hide_pose.mouth)), "full-chat idle hide cannot reopen the head bubble or restart the old talking mouth")
	app.roaming.wait_remaining = 0.0
	verify(not await advance_host(50) and app.roaming.mode == "free", "full-chat automatic hide with a saved draft allows the next actual free-mode trip")
	verify(not chat.visible and not app.bubble.visible and responder.starts == request_count and idle_closes.count == 1, "subsequent host frames neither reopen full chat nor request or replay the old answer")
	app._menu_action(24)
	verify(chat.visible and is_equal_approx(chat._opacity, 1.0) and chat.input.text == saved_draft and app.ai_service.history == saved_history, "explicit history entry restores the automatically hidden full window opaque with its original draft")
	verify(chat.transcript.visible_characters == -1 and not chat.is_speech_revealing(), "reopening an idle-closed full conversation never replays its old reply")
	verify(app._chat_pauses_roaming() and await advance_host(36), "reopened full chat immediately pauses the resumed free-mode trip")
	chat.idle_closed.disconnect(closed)
	chat.hide(); chat.set_process(true)
	reset_card(); app.roaming.configure("off")
