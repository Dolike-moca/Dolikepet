extends SceneTree
## Native focus proof uses only this process's fixture windows; never sends input.
const Card = preload("res://scripts/proactive_card.gd")
var checks := 0
var failures: Array[String] = []
class Service extends Node:
	signal delta(text: String)
	signal reply_completed(text: String, proactive: bool)
	signal failed(message: String)
	signal state_changed
	var busy := false
	var request_kind := ""
	var settings := {"auth_method":"chatgpt"}
	var status := "准备好了"
	var received := ""
	var _request_serial := 0
	var reject := false
	var immediate_reply := false
	var during_send: Callable
	func billing_label() -> String: return "使用 ChatGPT 方案"
	func send_message(text: String, _context: Dictionary) -> bool:
		if busy and request_kind == "proactive": cancel()
		if busy: return false
		if reject:
			reject = false; status = "请先登录"; failed.emit(status); state_changed.emit(); return false
		received = text; busy = true; request_kind = "chat"; _request_serial += 1
		if during_send.is_valid(): during_send.call()
		state_changed.emit()
		if immediate_reply: immediate_reply = false; finish("立即完成的回复")
		return true
	func cancel() -> void:
		busy = false; request_kind = ""; status = "已停止"; state_changed.emit()
	func finish(text: String) -> void:
		busy = false; request_kind = ""; reply_completed.emit(text, false); state_changed.emit()
	func error() -> void:
		busy = false; request_kind = ""; status = "模拟断网"; failed.emit(status); state_changed.emit()
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("PROACTIVE CARD: " + message)
func run() -> void:
	var native = ClassDB.instantiate("GDCubismUserModel")
	check(native != null and native.has_method("show_companion_without_activation"), "native passive-show bridge exists")
	if not failures.is_empty(): quit(1); return
	var activity: Dictionary = native.companion_activity_snapshot()
	check(activity.keys().size() == 4 and activity.has("available") and activity.has("idle_seconds") and activity.has("locked") and activity.has("fullscreen"), "activity snapshot has no content or titles")
	check(float(activity.idle_seconds) >= 0 and activity.locked is bool and activity.fullscreen is bool, "coarse activity fields are valid")
	check(not native.show_companion_without_activation(0), "foreign/invalid native handles are rejected")
	root.title = "Dolike passive-card fixture"
	root.size = Vector2i(200,200)
	root.show(); root.grab_focus()
	await process_frame; await process_frame
	var previous: int = native.companion_foreground_handle()
	check(previous != 0, "focus proof starts with a real foreground HWND")
	var service := Service.new(); root.add_child(service)
	var card := Card.new(); card.native_bridge = native; card.hover_override = 0
	root.add_child(card); card.setup(service)
	var notices: Array[String] = []
	var drafts: Array[String] = []
	var answers: Array[String] = []
	var actions: Array[String] = []
	var spoken: Array[String] = []
	var speech_stops: Array[bool] = []
	card.dismissed.connect(func(reason: String): notices.append(reason))
	card.draft_changed.connect(func(text: String): drafts.append(text))
	card.answered.connect(func(text: String): answers.append(text))
	card.action_requested.connect(func(action: String): actions.append(action))
	card.spoken.connect(func(text: String): spoken.append(text))
	card.speech_stopped.connect(func(): speech_stops.append(true))
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	var pet_rect := Rect2i(area.position + Vector2i(30,30), Vector2i(300,300))
	check(card.present("要不要休息一小会儿？我在这里陪你。", "rest", pet_rect, root.current_screen), "passive invitation opens")
	await process_frame; await process_frame
	check(card.visible and card.unfocusable, "automatic card is visible but cannot take keyboard focus")
	check(spoken.is_empty() and speech_stops.is_empty(), "expanding an invitation neither restarts nor stops its existing speech")
	check(native.companion_foreground_handle() == previous, "Win32 foreground window is unchanged by automatic show")
	check(not card.is_composing() and card.reply_button.visible and not card.input.is_visible_in_tree(), "passive invitation starts in compact reply mode")
	check(not card._billing_row.visible and not card._menu.visible, "response bubble hides account chrome and menu until requested")
	check(card.borderless and card.transparent and not card.exclusive, "speech bubble has no native title bar and is nonmodal")
	check(not card.transcript.bbcode_enabled, "model text cannot inject formatted controls")
	check(card.size.x <= 360 and card.size.y < 250, "short invitation fits a compact bubble")
	check(not Geometry2D.is_point_in_polygon(Vector2(1,1),card.mouse_passthrough_polygon), "transparent corners pass through mouse hits")
	check(not card.present("覆盖旧内容", "game", pet_rect, root.current_screen), "an open invitation is never overwritten")
	for point in [area.position, Vector2i(area.end.x-300,area.position.y), Vector2i(area.position.x,area.end.y-300),area.end-Vector2i(300,300)]:
		card.update_anchor(Rect2i(point, Vector2i(300,300)), root.current_screen)
		check(area.encloses(Rect2i(card.position,card.size)), "card stays within each screen corner")
	card.update_anchor(Rect2i(area.position+Vector2i(300,300),Vector2i(300,300)),root.current_screen)
	check(card.position.y+card.size.y <= card._pet_rect.position.y and not card.tip_above, "bubble prefers above the pet with its tip pointing down")
	card.update_anchor(Rect2i(area.position+Vector2i(300,0),Vector2i(300,300)),root.current_screen)
	check(card.position.y >= card._pet_rect.end.y and card.tip_above, "top edge flips the entire bubble and tip below the pet")
	card.hover_override = 1
	for frame in 100: card.advance(0.25,true)
	check(card.visible and card._idle > 20.0, "mouse entry resets once and stationary hover continues idle after revealing")
	card.hover_override = 0
	for frame in int(ceil((Card.SHORT_IDLE_SECONDS - card._idle + 1.0) / 0.25)): card.advance(0.25,true)
	check(card.visible and card.panel.modulate.a < 1.0 and card.panel.modulate.a > 0.0, "idle card fades instead of abruptly disappearing")
	for frame in int(Card.FADE_SECONDS / 0.25): card.advance(0.25,true)
	check(not card.visible and notices.back() == "idle_timeout", "idle invitation closes after fade without rejection feedback")
	check(card.present("又见面啦。", "reconnect", pet_rect, root.current_screen), "next independent invitation can open")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	card._input(click)
	check(not card.unfocusable and card.engaged(), "explicit fixture click permits typing")
	card.begin_reply()
	check(speech_stops.size() == 1, "opening the composer stops the previous displayed utterance")
	check(card.is_composing() and card.input.is_visible_in_tree() and not card.transcript.visible, "reply action switches instead of stacking input and conversation")
	check(card.billing.text.contains("ChatGPT") and card.usage.is_visible_in_tree(), "composer identifies its active billing path and usage management")
	card.input.text = "我把这句话先留在这里"
	card._draft_edited()
	check(card.has_draft() and drafts.back() == card.input.text, "draft updates are emitted for host persistence")
	for frame in 200: card.advance(0.25,true)
	check(card.visible, "typing prevents automatic disappearance")
	card.advance(0.1,false)
	check(not card.visible and card.has_draft(), "busy interaction hides the card without losing draft")
	root.grab_focus(); await process_frame
	previous = native.companion_foreground_handle()
	card.advance(0.1,true); await process_frame
	check(card.visible and card.unfocusable and native.companion_foreground_handle() == previous, "automatic resume keeps keyboard focus elsewhere")
	card._dismiss_user()
	check(card.has_draft() and notices.back() == "closed", "closing a draft does not count as ignored")
	check(not card.present("不能覆盖草稿", "rest", pet_rect, root.current_screen), "new prompt cannot overwrite hidden draft")
	check(card.reopen() and card.has_draft() and card.is_composing(), "explicit reopen restores draft directly in the same input bubble")
	card.set_draft("好呀，我休息一下")
	service.busy = true; service.request_kind = "proactive"
	service.during_send = func(): check(card.owns_reply(), "ownership is visible synchronously at request start")
	card._send_message()
	service.during_send = Callable()
	check(service.received == "好呀，我休息一下" and answers.back() == service.received, "accepted send emits response feedback")
	await process_frame
	check(not card.has_draft() and card.size.x <= 360 and card.size.y < 250 and card.stop.visible and not card.is_composing(), "send changes to compact waiting mode without expanding a chat panel")
	check(card._waiting, "canceling a proactive request does not detach the new card reply")
	service.delta.emit("[b]给你留着位置[/b]")
	check(card.transcript.text.contains("[b]给你"), "streaming is plain text")
	service.finish("我在这里等你。")
	check(card.transcript.text == "我在这里等你。" and not card._waiting and card.reply_button.visible, "completed answer replaces all prior turns and offers a new reply")
	service.delta.emit("外部窗口的流"); service.reply_completed.emit("其他聊天回复",false)
	check(card.transcript.text == "我在这里等你。", "another chat cannot overwrite this completed single turn")
	card.begin_reply(); card.set_draft("同步完成"); service.immediate_reply = true; card._send_message()
	check(card.transcript.text == "立即完成的回复" and not card.owns_reply() and not card.has_draft(), "a synchronous completed turn is not erased after send returns")
	card.begin_reply(); card.set_draft("断网后还要重试的原话"); card._send_message(); service.error()
	check(card.is_composing() and card.input.text == "断网后还要重试的原话" and not card._waiting and card.status_label.visible, "network failure restores original draft and displays an inline error")
	service.reject = true; card._send_message()
	check(card.input.text == "断网后还要重试的原话" and card.is_composing() and not card._waiting, "synchronous rejection retains the draft")
	card._send_message(); service.cancel()
	check(card.input.text == "断网后还要重试的原话" and card.is_composing(), "stop restores original draft for an explicit retry")
	card._send_message(); card._dismiss_user()
	check(card.owns_reply() and not card.visible, "closing hides an in-flight turn without detaching it")
	check(card.reopen() and card.owns_reply() and not card.is_composing(), "reopening an in-flight turn preserves its waiting state")
	card._dismiss_user(); service.delta.emit("迟到"); service.finish("迟到的结果")
	check(not card.visible and not card._active and card.transcript.text == "迟到的结果", "late result stays hidden after close")
	card.reopen(); card.set_draft("长回复测试"); card._send_message(); service.finish("长回复文字。".repeat(240))
	await process_frame; await process_frame
	check(card.size.y <= 350 and card.transcript.scroll_active and card.transcript.text.length() > 1000, "long replies scroll inside a bounded bubble without truncation")
	check(Rect2(Vector2.ZERO,Vector2(card.size)).encloses(Rect2(card.panel.position,card.panel.size)), "content panel remains within its window")
	card.begin_reply(); card.set_draft("输入法确认不应发送")
	var enter := InputEventKey.new(); enter.pressed = true; enter.keycode = KEY_ENTER
	var sent_before := service.received; card._input_key(enter)
	check(service.received == sent_before and not service.busy, "plain Enter never submits while confirming IME or adding a line")
	var link_events: Array[String] = []
	card.history_requested.connect(func(): link_events.append("history"))
	card.memory_requested.connect(func(): link_events.append("memory"))
	card.settings_requested.connect(func(): link_events.append("settings"))
	for button in card._menu.get_child(1).get_children(): button.pressed.emit()
	check(link_events == ["history","memory","settings"], "more-menu actions keep their distinct destinations")
	card.set_draft("仍然保留")
	card.reset_session()
	check(card.has_draft() and not card.visible and card._entries.is_empty(), "account/session reset preserves unsent text")
	card.set_draft("")
	check(card.present("先歇一会儿吧。", "rest", pet_rect, root.current_screen), "fresh prompt after reset")
	card._quick_action("accepted")
	check(actions.back() == "accepted" and card.engaged() and card.transcript.text.contains("休息"), "positive quick reply acknowledges without another paid request")
	check(spoken.size() == 1 and spoken.back() == card.transcript.text, "local accepted reply emits its exact visible sentence once for mouth animation")
	card._quick_action("snooze")
	check(actions.back() == "snooze" and not card.visible, "snooze action closes and reaches host")
	card.present("今天聊聊？", "reconnect", pet_rect, root.current_screen)
	card._quick_action("quiet_today")
	check(actions.back() == "quiet_today" and not card.visible, "quiet-today action reaches host")
	card.present("玩得开心喵。", "game", pet_rect, root.current_screen)
	card.suspend()
	check(not card._active and notices.back() == "interrupted", "busy unengaged invitations are dropped, not queued")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review="):
			var output := arg.trim_prefix("--review=")
			DirAccess.make_dir_recursive_absolute(output)
			card.present("要不要休息一小会儿？起来伸个懒腰，我在这里等你喵。", "rest", pet_rect, root.current_screen)
			await screenshot(card, output.path_join("invitation.png"))
			card.reopen(); card.set_draft("刚刚忙完，陪我聊两句吧。")
			await screenshot(card, output.path_join("manual-input.png"))
			card._send_message(); service.delta.emit("辛苦啦，先放松一下。今天有什么想和我说的？")
			await screenshot(card, output.path_join("conversation.png"))
			service.finish("好呀，大人，猫猫陪你待一会儿喵。")
			card.more_button.pressed.emit()
			await screenshot(card,output.path_join("more-menu.png"))
	card.queue_free(); service.queue_free(); await process_frame
	native.free()
	print("Proactive card: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func screenshot(window: Window, path: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	window.get_texture().get_image().save_png(path)
