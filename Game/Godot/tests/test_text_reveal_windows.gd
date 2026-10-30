extends SceneTree
## Real text surfaces, in-memory service only. No credentials, network or input injection.
const Card = preload("res://scripts/proactive_card.gd")
const Chat = preload("res://scripts/ai_chat_window.gd")
class Bridge extends RefCounted:
	func show_companion_without_activation(_handle: int) -> bool: return true
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
	var status := "准备好了"
	var _request_serial := 0
	func billing_label() -> String: return "测试服务"
	func send_message(text: String, _context: Dictionary = {}) -> bool:
		if busy: return false
		_request_serial += 1; busy = true; request_kind = "chat"
		history.append({"role":"user","text":text}); state_changed.emit(); return true
	func finish(text: String) -> void:
		history.append({"role":"assistant","text":text}); busy = false
		reply_completed.emit(text, false); state_changed.emit()
	func cancel() -> void:
		busy = false; status = "已停止"; state_changed.emit()
	func clear_history() -> void:
		cancel(); history.clear(); history_cleared.emit(); state_changed.emit()
	func add_memory(_text: String) -> bool: return true
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var service := Service.new(); root.add_child(service)
	var card := Card.new(); card.native_bridge = Bridge.new(); root.add_child(card); card.setup(service)
	card.hover_override = 1
	var chat := Chat.new(); root.add_child(chat); chat.setup(service); chat.set_process(false)
	await process_frame
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	var anchor := Rect2i(area.position + Vector2i(100,250), Vector2i(300,300))
	var phrase := "大人，猫猫在这里陪着你，慢慢聊一会儿喵。"
	check(card.present(phrase, "rest", anchor, root.current_screen), "local invitation opens")
	check(card.transcript.text == phrase and card.transcript.visible_characters == 0, "local invitation is laid out but starts hidden")
	card.advance(0.25, true)
	check(card.transcript.visible_characters > 0 and card.transcript.visible_characters < phrase.length(), "local invitation reveals only a prefix")
	card.reset_session(); service.settings.speech_speed = 0; card.hover_override = 0
	card.present("喵".repeat(300), "rest", anchor, root.current_screen)
	for frame in 100: card.advance(0.25, true)
	check(card.visible and card._idle == 0.0 and not card._reveal.done(), "slow long invitation is not timed out before its text finishes")
	card.reset_session(); service.settings.speech_speed = 2; card.hover_override = 1
	card.present(phrase, "rest", anchor, root.current_screen, 5)
	check(card.transcript.visible_characters == 5, "expanded invitation continues the head bubble's revealed prefix")
	card._quick_action("accepted")
	check(card.transcript.visible_characters == 0, "local accepted response starts its own reveal")
	card.advance(0.25, true)
	check(card.transcript.visible_characters > 0, "accepted response advances without a model request")
	card.begin_reply(); card.input.text = "说句话"; card._send_message()
	var answer := "猫猫愿意陪大人聊聊天。".repeat(6)
	service.delta.emit(answer + " \n")
	check(card.transcript.visible_characters == 0 and card.transcript.text.contains(answer), "stream chunk is buffered without flashing full text")
	card.advance(0.25, true)
	var partial := card.transcript.visible_characters
	service.finish(answer)
	check(card.transcript.visible_characters == partial and not card._waiting, "completion does not jump past undisplayed letters")
	card.advance(0.25, true)
	check(card.transcript.visible_characters > partial and card.transcript.visible_characters < answer.length(), "completed answer continues revealing")
	check(card.is_speech_revealing() and not card.is_speech_complete(), "mouth lifecycle follows the incomplete rendered reply")
	card.begin_reply(); card.input.text = "再来一句"; card._send_message(); service.delta.emit("已取消的内容")
	service.cancel()
	check(card.is_composing() and card._reveal.full_text.is_empty(), "cancel clears reveal and restores composer")
	card.input.text = "关闭这轮"; card._send_message(); service.delta.emit("已收到的前缀"); card.advance(0.25, true); card._dismiss_user()
	service.delta.emit("隐藏时收到的内容"); card.reopen()
	check(card.transcript.visible_characters == -1, "explicitly reopening a pending reply does not replay its received prefix")
	var received: int = card._streamed.length()
	service.delta.emit("重新打开后逐渐出现")
	check(card.transcript.visible_characters == received, "only new chunks reveal after reopening")
	card._dismiss_user(); service.finish("迟到回复")
	check(not card.visible and not card.is_open(), "late completion cannot reopen a closed bubble")
	card.reset_session()
	chat.open_panel(); chat.set_process(false)
	check(chat.transcript.visible_characters == -1, "existing history opens fully without replay")
	chat.input.text = "开始一轮新聊天"; chat._send_message(); service.delta.emit(answer + " \n")
	var offset := chat._reveal_offset
	check(offset > 0 and chat.transcript.visible_characters == offset, "history stays visible while the current response starts hidden")
	chat._process(0.25)
	partial = chat.transcript.visible_characters
	check(partial > offset and partial < offset + answer.length(), "full window reveals a current response prefix")
	service.finish(answer)
	check(chat.transcript.visible_characters == partial, "history append preserves the unfinished reveal")
	chat._process(0.25)
	check(chat.transcript.visible_characters > partial and chat.transcript.visible_characters < offset + answer.length(), "completion continues without snapping to full text")
	chat.hide(); chat.open_panel(); chat.set_process(false)
	check(chat.transcript.visible_characters == -1, "closing and reopening history does not replay old text")
	chat.input.text = "取消这一轮"; chat._send_message(); service.delta.emit("不应残留的半句话")
	service.cancel(); service.delta.emit("取消后的迟到内容")
	check(chat.streamed_text.is_empty() and not chat.transcript.text.contains("迟到内容"), "cancel drops pending text and ignores late chunks")
	service.clear_history()
	check(chat._reveal.full_text.is_empty() and chat._reveal_offset == -1, "clearing history clears its reveal target")
	chat.input.text = "一次返回的回复"; chat._send_message(); service.finish(answer)
	check(chat.is_speech_revealing() and not chat.is_speech_complete() and chat.transcript.visible_characters == chat._reveal_offset, "completion-only reply still starts gradual text instead of flashing fully")
	chat.input.text = "切换账户"; chat._send_message(); service.delta.emit(answer); service.cancel(); service.account_changed.emit()
	check(chat._reveal.full_text.is_empty() and not chat._live_turn, "account change cannot retain a live reveal")
	chat.queue_free(); card.queue_free(); service.queue_free(); await process_frame
	for failure in failures: printerr("TEXT REVEAL WINDOWS: " + failure)
	print("Text reveal windows: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
