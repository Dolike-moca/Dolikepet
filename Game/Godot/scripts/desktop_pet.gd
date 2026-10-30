extends Node2D

const Behavior = preload("res://scripts/pet_behavior.gd")
const LivePet = preload("res://scripts/live2d_pet.gd")
const IdleSitting = preload("res://scripts/idle_sitting.gd")
const SleepCycle = preload("res://scripts/sleep_cycle.gd")
const PetSettings = preload("res://scripts/pet_settings.gd")
const Roaming = preload("res://scripts/roaming.gd")
const DragMotion = preload("res://scripts/drag_motion.gd")
const DesktopPhysics = preload("res://scripts/desktop_physics.gd")
const LandingMotion = preload("res://scripts/landing_motion.gd")
const PickupMotion = preload("res://scripts/meal_motion.gd")
const FoodItem = preload("res://scripts/food_item.gd")
const BowlCapacity = preload("res://scripts/bowl_capacity.gd")
const BowlFiles = preload("res://scripts/bowl_files.gd")
const BowlWindow = preload("res://scripts/bowl_window.gd")
const BowlJump = preload("res://scripts/bowl_jump.gd")
const BowlSummon = preload("res://scripts/bowl_summon.gd")
const BowlHit = preload("res://scripts/bowl_hit_reaction.gd")
const BowlFlight = preload("res://scripts/bowl_flight_window.gd")
const Satiety = preload("res://scripts/satiety.gd")
const Paths = preload("res://scripts/project_paths.gd")
const DesktopShell = preload("res://scripts/desktop_shell.gd")
const CatchChallenge = preload("res://scripts/catch_challenge.gd")
const CatchScoreWindow = preload("res://scripts/catch_score_window.gd")
const GameScores = preload("res://scripts/game_scores.gd")
const ScoreBoard = preload("res://scripts/score_board.gd")
const JuggleChallenge = preload("res://scripts/juggle_challenge.gd")
const JuggleMotion = preload("res://scripts/juggle_motion.gd")
const PetHitArea = preload("res://scripts/pet_hit_area.gd")
const DesktopDrag = preload("res://scripts/desktop_drag.gd")
const DizzyCarry = preload("res://scripts/dizzy_carry.gd")
const PetSize = preload("res://scripts/pet_size.gd")
const SizeChange = preload("res://scripts/size_change.gd")
const SizeFlash = preload("res://scripts/size_flash.gd")
const AICompanion = preload("res://scripts/ai_companion.gd")
const AIChatWindow = preload("res://scripts/ai_chat_window.gd")
const AIMemoryWindow = preload("res://scripts/ai_memory_window.gd")
const AISpeech = preload("res://scripts/ai_speech.gd")
const SpeechMouth = preload("res://scripts/speech_mouth.gd")
const SpeechSpeed = preload("res://scripts/speech_speed.gd")
const TextReveal = preload("res://scripts/text_reveal.gd")
const ChatGPTAuth = preload("res://scripts/chatgpt_auth.gd")
const ProactiveCompanion = preload("res://scripts/proactive_companion.gd")
const SETTINGS := "user://desktop-pet.cfg"
const ACTIONS := ["normal", "blink", "closed", "happy", "closedHappy", "talk", "chew"]
const LABELS := ["恢复正常", "眨一下眼", "闭眼", "张嘴笑", "闭眼笑", "说话口型演示（5 秒）", "咀嚼演示"]

var behavior = Behavior.new()
var pet = LivePet.new()
var idle_sitting = IdleSitting.new()
var sleep_cycle = SleepCycle.new()
var sleep_minute_override := -1 # Deterministic isolated host previews/tests.
var sleep_owns_seat := false
var roaming = Roaming.new()
var drag_motion = DragMotion.new()
var falling = DesktopPhysics.new()
var landing = LandingMotion.new()
var pickup = PickupMotion.new()
var settings_window = PetSettings.new()
var settings_path := SETTINGS
var config: Dictionary
var menu := PopupMenu.new()
var food_dialog := FileDialog.new()
var food_dialog_open := false
var bubble := PanelContainer.new()
var bubble_label := Label.new()
var bubble_until := 0.0
var gaze_enabled := true
var dragging := false
var drag_moved := false
var drag_pointer := Vector2i.ZERO
var drag_window := Vector2i.ZERO
var ready_for_input := false
var save_timer := 0.0
var last_pointer := Vector2i.ZERO
var motion_reset_pending := true
var manual_sit_pending := false
var menu_holding := false # A stationary grab point, not a frozen simulation.
var bowl_files = BowlFiles.new()
var bowl_window = BowlWindow.new()
var bowl_jump = BowlJump.new()
var bowl_summon = BowlSummon.new()
var bowl_hit = BowlHit.new()
var bowl_flight = BowlFlight.new()
var bowl_capacity := BowlCapacity.DEFAULT
var bowl_enabled := true
var bowl_saved_position := Vector2i(-99999,-99999)
var bowl_root_override := "" # Isolated test fixtures only; normal use always resolves the game root.
var bowl_poll := 0.0
var bowl_user_cooldown := 0.0
var satiety = Satiety.new()
var desktop_shell = DesktopShell.new()
var satiety_bar := ProgressBar.new()
var catch_game = CatchChallenge.new()
var catch_score = CatchScoreWindow.new()
var game_scores = GameScores.new()
var score_board = ScoreBoard.new()
var juggle_game = JuggleChallenge.new()
var juggle_motion = JuggleMotion.new()
var score_game := "catch"
var hit_area = PetHitArea.new()
var hit_viewport := SubViewport.new()
var native_hit_testing := false
var drag_input = DesktopDrag.new()
var dizzy_carry = DizzyCarry.new()
var update_notices: Array[Dictionary] = []
var size_change = SizeChange.new()
var size_flash = SizeFlash.new()
var size_anchor := Vector2(NAN,NAN)
var size_canvas_pixels := 0 # Visible extent while a larger transparent canvas is reserved.
var size_wheel_quiet := 0.0
var ai_service = AICompanion.new()
var ai_chat = AIChatWindow.new()
var ai_memory = AIMemoryWindow.new()
var ai_speech = AISpeech.new()
var speech_mouth = SpeechMouth.new()
var bubble_reveal = TextReveal.new()
var bubble_speed_factor := 1.0
var ai_bubble_owned := false
var ai_compact_speech := false
var ai_compact_speech_muted := false
var chatgpt_auth = ChatGPTAuth.new()
var proactive_companion = ProactiveCompanion.new()

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	if config.is_empty():
		push_error("无法读取 config/pet.json")
		return
	if settings_path == SETTINGS: desktop_shell.prepare_window(get_window(), true)
	get_window().title = "Dolike 桌宠 · Godot"
	get_window().min_size = Vector2i.ONE * int(config.minimumSize)
	get_window().max_size = Vector2i.ONE * int(config.maximumSize)
	get_window().always_on_top = config.alwaysOnTop
	get_viewport().transparent_bg = true
	Engine.max_fps = 60
	_setup_menu()
	_setup_bubble()
	food_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	food_dialog.access = FileDialog.ACCESS_FILESYSTEM
	food_dialog.filters = PackedStringArray(["*.png ; 食物 PNG 图片"])
	food_dialog.title = "选择食物（可多选，进食中选择可追加）"
	food_dialog.use_native_dialog = true
	add_child(food_dialog)
	food_dialog.files_selected.connect(_feed_pngs)
	food_dialog.canceled.connect(func(): food_dialog_open = false)
	add_child(falling)
	_load_settings()
	_update_size_menu()
	_setup_hit_viewport()
	add_child(size_flash)
	size_flash.setup(hit_viewport)
	add_child(ai_service)
	settings_window.ai_service = ai_service
	add_child(settings_window)
	settings_window.common_settings_saved.connect(_apply_common_settings)
	settings_window.settings_saved.connect(_apply_auto_sit_settings)
	settings_window.sleep_settings_saved.connect(_apply_sleep_settings)
	settings_window.visibility_changed.connect(func():
		if not settings_window.visible:
			idle_sitting.interact(false))
	add_child(pet)
	if not pet.load_pet(config):
		_say(pet.failure + "\n右键可退出。", 86400.0)
		push_error(pet.failure)
	else:
		pet.fit(Vector2(get_window().size))
		falling.set_geometry(Vector2(get_window().size), Rect2(DisplayServer.screen_get_usable_rect(get_window().current_screen)), pet.physics_anchor())
		_say("拖动移动 · 滚轮缩放 · 右键菜单", 4.0)
	_setup_bowl()
	drag_input.bridge = pet.model
	get_window().focus_exited.connect(_interrupt_drag)
	get_window().visibility_changed.connect(func():
		if not get_window().visible: _interrupt_drag())
	add_child(catch_score)
	catch_score.always_on_top = get_window().always_on_top
	game_scores.configure("user://game-scores.json" if settings_path==SETTINGS else settings_path+".scores.json",catch_game.best)
	catch_game.best = maxi(catch_game.best,int(game_scores.statistics("catch").best))
	catch_game.awarded.connect(game_scores.record_award)
	catch_game.awarded.connect(func(_event): score_game = "catch")
	catch_game.round_finished.connect(game_scores.finish_round)
	juggle_game.best = int(game_scores.statistics("juggle").best)
	juggle_game.awarded.connect(game_scores.record_award)
	juggle_game.round_finished.connect(game_scores.finish_round)
	add_child(score_board); score_board.bind(game_scores)
	_setup_ai()
	catch_score.board_requested.connect(func(): score_board.open_board(get_window().current_screen))
	add_child(desktop_shell)
	if settings_path==SETTINGS:
		_setup_desktop_shell()
	get_window().size_changed.connect(_resized)
	get_window().close_requested.connect(_exit)
	ready_for_input = true
	native_hit_testing = settings_path == SETTINGS
	RenderingServer.frame_post_draw.connect(_refresh_pointer_region)
	last_pointer = DisplayServer.mouse_get_position()
	settings_window.updater.notice_requested.connect(_queue_update_notice)
	if settings_path == SETTINGS: settings_window.updater.start_automatic()

func _setup_ai() -> void:
	# All non-default hosts stay offline and use their own fixture directory.
	var ai_root := "user://ai-companion" if settings_path == SETTINGS else settings_path + ".ai"
	add_child(chatgpt_auth)
	chatgpt_auth.setup(pet.model, ProjectSettings.globalize_path(ai_root), settings_path == SETTINGS)
	ai_service.bind_auth(chatgpt_auth)
	ai_service.external_proactive = true
	ai_service.setup(pet.model, ProjectSettings.globalize_path(ai_root), settings_path == SETTINGS)
	ai_chat.native_bridge = pet.model
	add_child(ai_chat); ai_chat.setup(ai_service)
	ai_chat.context_provider = _ai_context
	add_child(ai_memory); ai_memory.setup(ai_service)
	settings_window.ai_chat_requested.connect(_open_bubble_history)
	settings_window.ai_memory_requested.connect(ai_memory.open_panel)
	ai_chat.memory_requested.connect(ai_memory.open_panel)
	ai_chat.settings_requested.connect(func():
		_menu_action(14)
		settings_window._select_page(3))
	ai_service.request_started.connect(func(kind: String):
		if kind == "chat": _wake_sleep()
		if kind != "test":
			_clear_ai_speech()
			ai_compact_speech = kind == "chat" and proactive_companion.card.owns_reply())
	ai_service.delta.connect(func(text: String):
		if ai_service.request_kind != "proactive" and not ai_compact_speech_muted: ai_speech.append(text))
	ai_service.reply_completed.connect(func(text: String, proactive: bool):
		if not proactive and not ai_compact_speech_muted:
			# Some compatible responders return only a completed message.
			if ai_speech.segments == 0 and ai_speech.pending.is_empty(): ai_speech.append(text)
			ai_speech.finish())
	ai_service.failed.connect(func(_message: String): _clear_ai_speech())
	ai_service.request_canceled.connect(_clear_ai_speech)
	ai_service.account_changed.connect(_clear_ai_speech)
	ai_service.state_changed.connect(func():
		if not bool(ai_service.settings.get("enabled", false)): _clear_ai_speech())
	add_child(proactive_companion)
	proactive_companion.setup(self, ai_service, pet.model, ProjectSettings.globalize_path(ai_root), settings_path == SETTINGS)
	proactive_companion.card.context_provider = _ai_context
	ai_chat.input.text_changed.connect(func():
		if ai_chat.visible: _wake_sleep())
	proactive_companion.card.draft_changed.connect(func(_text: String):
		if proactive_companion.card.visible: _wake_sleep())
	proactive_companion.card.settings_requested.connect(_open_bubble_settings)
	proactive_companion.card.memory_requested.connect(_open_bubble_memory)
	proactive_companion.card.history_requested.connect(_open_bubble_history)
	proactive_companion.card.dismissed.connect(func(_reason: String):
		if ai_compact_speech:
			_clear_ai_speech()
			# Closing a live reply silences its remaining chunks. They still belong
			# to this compact conversation, never to the old head-bubble surface.
			ai_compact_speech = true
			ai_compact_speech_muted = true)
	proactive_companion.invitation_started.connect(func(text: String):
		_clear_ai_speech(); ai_speech.append(text); ai_speech.finish())
	proactive_companion.invitation_stopped.connect(_clear_ai_speech)
	proactive_companion.invitation_expanded.connect(func():
		if ai_bubble_owned: bubble.hide()
		ai_bubble_owned = false
		ai_compact_speech = true)
	proactive_companion.card.spoken.connect(func(text: String):
		_clear_ai_speech(); ai_compact_speech = true
		ai_speech.append(text); ai_speech.finish())
	proactive_companion.card.speech_stopped.connect(_clear_ai_speech)
	catch_game.round_finished.connect(func(event: Dictionary): _ai_game_finished("catch", event))
	juggle_game.round_finished.connect(func(event: Dictionary): _ai_game_finished("juggle", event))

func _open_bubble_settings() -> void:
	proactive_companion.card.suspend()
	_menu_action(14)
	settings_window._select_page(3)

func _open_bubble_memory() -> void:
	_wake_sleep()
	proactive_companion.card.suspend()
	ai_memory.open_panel()

func _open_bubble_history() -> void:
	if _chat_blocked_by_settings(): return
	_wake_sleep()
	proactive_companion.card.suspend()
	ai_chat.open_panel()

func _chat_blocked_by_settings() -> bool:
	if not settings_window.visible: return false
	_say("现在不行喵，先关掉设置再来找猫猫聊～", 4.0)
	return true

func _chat_pauses_roaming() -> bool:
	# A temporarily hidden live conversation still owns its place next to the
	# cat. A closed draft or an unfinished network request does not stop travel.
	return ai_chat.visible or proactive_companion.card.is_open()

func _ai_game_finished(game: String, event: Dictionary) -> void:
	var total: Variant = event.get("total", 0)
	var score := clampi(int(total), 0, 1000000000) if (total is int or total is float) and is_finite(float(total)) else 0
	proactive_companion.game_finished(game, score)

func _ai_context() -> Dictionary:
	var snapshot := {"satiety_percent": roundf(100.0 * satiety.used / maxi(1, satiety.capacity)),
		"size_percent": roundf(100.0 * _pet_size().x / float(PetSize.BASE)),
		"hungry": not satiety.resting, "bowl_open": bowl_window.visible,
		"dizzy": landing.state == "hard", "game": "juggle" if juggle_game.active() else ("catch" if catch_game.active() else "")}
	if not game_scores.rounds.is_empty():
		var recent: Dictionary = game_scores.rounds.back()
		snapshot.last_game = str(recent.get("game", ""))
		snapshot.last_game_score = int(recent.get("total", 0))
	return snapshot

func _clear_ai_speech() -> void:
	ai_speech.clear()
	ai_compact_speech = false
	ai_compact_speech_muted = false
	if ai_bubble_owned: bubble.hide()
	ai_bubble_owned = false

func _update_ai_presentation(dt: float, pose: Dictionary, idle: bool) -> void:
	var quiet_idle: bool = idle and get_window().visible and not settings_window.visible \
		and roaming.weight < 0.001 and behavior.mode == "normal"
	var allowed: bool = quiet_idle and not sleep_cycle.active()
	proactive_companion.tick(dt, allowed)
	# Memory maintenance is silent and may continue during sleep; invitations may not.
	ai_service.tick(dt, _ai_context(), quiet_idle and not bubble.visible and not ai_chat.visible and not ai_memory.visible \
		and not proactive_companion.card.is_open())
	# Already-visible replies can speak during other expressions/actions. Only
	# starting proactive invitations and a new head bubble require idle time.
	var visible_reply: bool = ai_chat.visible or proactive_companion.card.visible
	allowed = get_window().visible and get_window().mode != Window.MODE_MINIMIZED \
		and (allowed or visible_reply) and (not bubble.visible or ai_bubble_owned)
	if ai_compact_speech: allowed = allowed and visible_reply
	# A visible chat reveals one continuous answer; the head-bubble reader's
	# per-segment pauses must not leave the jaw talking after that answer ends.
	if ai_speech.finished and visible_reply:
		var surface = proactive_companion.card if proactive_companion.card.visible else ai_chat
		if surface.has_method("is_speech_complete") and surface.is_speech_complete(): ai_speech.clear()
	var speed_factor := SpeechSpeed.factor(_speech_speed_index())
	var speech: Dictionary = ai_speech.advance(dt, allowed, speed_factor)
	# A compact reply already has its text surface. Keep mouth movement without
	# replaying its queued sentences in a second bubble after the stream ends.
	if not allowed or str(speech.text).is_empty() or ai_compact_speech or proactive_companion.card.visible:
		if ai_bubble_owned: bubble.hide(); ai_bubble_owned = false
	else:
		if not ai_bubble_owned or not bubble.visible or bubble_label.text != speech.text:
			_say(str(speech.text), ai_speech.remaining + 0.05, false)
			ai_bubble_owned = true
	ai_speech.apply(pose, allowed)
	pose.speechSpeed = speed_factor
	speech_mouth.advance(dt, bubble.visible and not ai_bubble_owned,
		allowed and not str(speech.text).is_empty(), ai_speech.mouth, pose, speed_factor)

func _queue_update_notice(id: String, text: String) -> void:
	update_notices.append({"id":id,"text":text})

func _show_update_notice() -> void:
	if sleep_cycle.active(): return
	if update_notices.is_empty() or bubble.visible or dragging or menu.visible or proactive_companion.card.visible: return
	if not get_window().visible or get_window().mode == Window.MODE_MINIMIZED: return
	if catch_game.active() or juggle_game.active() or falling.active() or bowl_summon.active() or size_change.pending(): return
	var notice: Dictionary = update_notices.pop_front()
	_say(str(notice.text),7.0)
	settings_window.updater.acknowledge_notice(str(notice.id))

func _capture_hit_area() -> void:
	# The speech CanvasLayer must not erase the cat underneath it or enlarge
	# its hit area. Share the model canvas; do not clone/update a second rig.
	var frame: Image = hit_viewport.get_texture().get_image()
	hit_area.capture(frame,Vector2(get_window().size))

func _setup_hit_viewport() -> void:
	hit_viewport.disable_3d = true
	hit_viewport.transparent_bg = true
	hit_viewport.gui_disable_input = true
	hit_viewport.world_2d = get_window().world_2d
	add_child(hit_viewport)
	_sync_hit_viewport()

func _sync_hit_viewport() -> void:
	if not hit_viewport.is_inside_tree(): return
	hit_viewport.size = get_window().size
	# Keep a completed UI-free frame available even on the exact frame speech
	# opens/closes. Switching render sources then could sample a blank/stale mask.
	hit_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _refresh_pointer_region() -> void:
	if not native_hit_testing or not ready_for_input or not pet.available: return
	var window := get_window()
	var pointer := Vector2(DisplayServer.mouse_get_position()-window.position)
	_apply_pointer_region(pointer)

func _apply_pointer_region(pointer: Vector2) -> bool:
	var window := get_window()
	var capture := dragging or menu_holding
	if not capture and Rect2(Vector2.ZERO,Vector2(window.size)).has_point(pointer):
		# Read only while the pointer is in this window. Animation's final alpha
		# includes sitting, mirror/zoom, moving hair, props and expression masks.
		_capture_hit_area()
		capture = hit_area.contains(pointer,Vector2(window.size))
	if OS.get_name()=="Windows" and pet.model.has_method("set_desktop_passthrough"):
		var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,window.get_window_id())
		pet.model.call("set_desktop_passthrough",handle,not capture)
	return capture

func _pointer_hits_pet(point: Vector2) -> bool:
	return hit_area.contains(point,Vector2(get_window().size))

func _setup_desktop_shell(cache_override := "") -> void:
	desktop_shell.action_requested.connect(_menu_action)
	var widgets: Array[Window] = [get_window(),bowl_window,bowl_flight,catch_score]
	# The native helper already removes taskbar/minimize/maximize styles.
	# Changing Godot window flags after a transparent window has been shown
	# rebuilds its Win32 style and leaves an opaque region until it is reopened.
	desktop_shell.start(widgets,preload("res://assets/app/icon.png"),cache_override,[settings_window])

func _setup_menu() -> void:
	add_child(menu)
	menu.title = "桌宠菜单"
	var development := Paths.development_mode()
	if development:
		for i in ACTIONS.size():
			menu.add_item(LABELS[i], i)
		menu.add_item("取食演示（饭盆）", 15)
		menu.add_item("喂食 PNG…（可多选 / 追加）", 16)
	menu.add_check_item("猫的饭盆", 17)
	menu.add_separator()
	if development:
		menu.add_item("坐下", 12)
		menu.add_item("站起来", 13)
		menu.add_separator()
	menu.add_check_item("视线跟随鼠标", 10)
	menu.add_check_item("始终置顶", 11)
	menu.add_item("桌宠设置…", 14)
	menu.add_item("聊天记录…", 24)
	menu.add_item("打开猫咪小对话框…", 25)
	menu.add_item("睡觉", 33)
	menu.add_item("计分板…", 23)
	menu.add_separator()
	menu.add_item("大小 100%", 32)
	menu.set_item_disabled(menu.get_item_index(32),true)
	menu.add_item("恢复默认大小与位置（100%）", 20)
	if development: menu.add_item("重新加载模型", 21)
	menu.add_item("退出桌宠", 22)
	menu.add_separator()
	menu.add_item("饱食度 0.0%",30)
	menu.add_theme_color_override("font_disabled_color",Color("ddd4e9"))
	menu.set_item_disabled(menu.get_item_index(30),true)
	menu.add_item(" ",31)
	menu.set_item_disabled(menu.get_item_index(31),true)
	satiety_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	satiety_bar.show_percentage = false
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color("a46ce6")
	fill_style.set_corner_radius_all(4)
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color("29232f")
	track_style.set_corner_radius_all(4)
	satiety_bar.add_theme_stylebox_override("fill",fill_style)
	satiety_bar.add_theme_stylebox_override("background",track_style)
	satiety_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	satiety_bar.offset_left = 12; satiety_bar.offset_right = -12
	satiety_bar.offset_top = -18; satiety_bar.offset_bottom = -8
	menu.add_child(satiety_bar)
	_update_satiety_menu()
	menu.id_pressed.connect(_menu_action)

func _update_size_menu() -> void:
	var percent := 100.0*_pet_size().x/float(config.windowSize)
	var text := "大小 %.0f%%" % percent
	if size_change.pending(): text += " → %d%%" % roundi(100.0*size_change.target/PetSize.BASE)
	menu.set_item_text(menu.get_item_index(32),text)

func _update_satiety_menu() -> void:
	var percent := clampf(100.0*satiety.used/maxi(1,satiety.capacity),0.0,100.0)
	menu.set_item_text(menu.get_item_index(30),"饱食度 %.1f%%" % percent)
	satiety_bar.value = percent
	menu.set_item_text(menu.get_item_index(33),"叫醒猫猫" if sleep_cycle.active() else "睡觉")

func _setup_bubble() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(bubble)
	bubble.visibility_changed.connect(_sync_hit_viewport)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.add_theme_font_size_override("font_size", 14)
	bubble_label.custom_minimum_size = Vector2(260, 0)
	bubble.add_child(bubble_label)
	_position_bubble()

func _say(text: String, seconds: float, spoken: bool = true) -> void:
	ai_bubble_owned = false
	# Keep the complete text for stable wrapping, revealing only its character
	# count. Reading time and jaw time share the same presentation speed.
	var duration := maxf(seconds, text.length() / SpeechSpeed.BASE_CHARACTERS_PER_SECOND + 0.55)
	if spoken:
		bubble_reveal.replace(text)
		speech_mouth.say(text, duration)
	else:
		bubble_reveal.set_text(text)
	bubble_label.text = text
	bubble_label.visible_characters = bubble_reveal.visible_text().length()
	bubble.show()
	bubble_speed_factor = SpeechSpeed.factor(_speech_speed_index())
	bubble_until = Time.get_ticks_msec() / 1000.0 + duration / bubble_speed_factor
	_position_bubble()

func _speech_speed_index() -> int:
	return int(ai_service.settings.get("speech_speed", SpeechSpeed.DEFAULT))

func _invitation_visible_characters() -> int:
	return ai_speech.completed_characters + (bubble_reveal.visible_text().length() if ai_bubble_owned else 0)

func _advance_bubble_text(dt: float) -> void:
	if not bubble.visible: return
	var now := Time.get_ticks_msec() / 1000.0
	var speed := SpeechSpeed.factor(_speech_speed_index())
	if not is_equal_approx(speed, bubble_speed_factor):
		# A saved speed change affects the remaining sentence without replaying
		# its prefix or altering any network request.
		bubble_until = now + maxf(0.0, bubble_until - now) * bubble_speed_factor / speed
		bubble_speed_factor = speed
	var shown: String = bubble_reveal.advance(dt, SpeechSpeed.chars_per_second(_speech_speed_index()))
	bubble_label.visible_characters = shown.length()
	if now >= bubble_until and bubble_reveal.done(): bubble.hide()

func _position_bubble() -> void:
	var width := minf(280.0, get_window().size.x - 16.0)
	bubble_label.custom_minimum_size.x = width
	bubble.position = Vector2((get_window().size.x - width) / 2.0, 6.0)
	bubble.size = Vector2(width, 0)

func _process(dt: float) -> void:
	size_wheel_quiet=maxf(0.0,size_wheel_quiet-dt)
	if not ready_for_input:
		return
	if menu.visible: _update_satiety_menu()
	_update_catch_game(dt)
	_advance_bubble_text(dt)
	_show_update_notice()
	if dragging:
		_poll_drag_pointer(dt)
	elif not menu_holding and (falling.body.held or falling.state=="held" or drag_motion.state=="held"):
		# An interrupted click must never leave an unowned mouse spring behind.
		_finish_drag(true)
	if pet.available:
		var window := get_window()
		var area := Rect2(DisplayServer.screen_get_usable_rect(window.current_screen))
		if menu_holding and not menu.visible and window.mode != Window.MODE_MINIMIZED:
			_release_menu_hold()
		var drag_paused: bool = food_dialog_open or window.mode == Window.MODE_MINIMIZED
		var bowl_blocked: bool = sleep_cycle.active() or catch_game.active() or juggle_game.active() or dragging or menu.visible or drag_paused or drag_motion.active() or falling.active() or landing.active() or bowl_hit.active() or size_change.pending()
		var bowl_step := _update_bowl(dt,bowl_blocked,area)
		if bowl_step.move: window.position = Vector2i(bowl_step.position.round())
		if not falling.active(): falling.physical_facing = 1.0 if pet.facing_scale >= 0.0 else -1.0
		falling.set_geometry(Vector2(_pet_size()), falling.area if falling.active() else area, pet.physics_anchor(falling.physical_facing if falling.active() else pet.facing_scale))
		var drag_at: Vector2 = falling.window_position() if falling.active() else Vector2(window.position)
		drag_motion.pointer_previous = drag_at + falling.body.spring_gap
		if drag_motion.update(dt, drag_at, Vector2(_pet_size()), drag_paused):
			idle_sitting.interact(false)
		var fall: Dictionary = falling.update(dt, Vector2(window.position), Vector2(_pet_size()), falling.area, dragging or menu_holding or bowl_jump.active() or bowl_step.move, drag_paused)
		if fall.started:
			_wake_sleep(true)
			if not bowl_hit.active():
				pickup.cancel(true)
				behavior.chewing.cancel()
			if landing.state!="hard": landing.cancel()
			roaming.facing = -1 if pet.facing_scale >= 0.0 else 1
			roaming.interrupt()
			idle_sitting.interact(false)
			bubble.hide()
			pet.set_seated(false)
		if fall.move:
			window.position = Vector2i(fall.position.round())
			save_timer = 0.6
		var hit_grounded: bool = fall.landed or window.position.y+_pet_size().y>=area.end.y-3.0
		if bowl_hit.update(dt,hit_grounded,landing.active(),drag_paused or menu.visible):
			bowl_jump.cancel()
			landing.cancel()
			landing.start({"height":LandingMotion.HIGH_HEIGHT,"speed":LandingMotion.HIGH_SPEED,"lateral_speed":0.0,"dizzy_seconds":bowl_hit.dizzy_seconds,"immediate_dizzy":bowl_hit.immediate_dizzy})
			idle_sitting.interact(false)
		elif not fall.impact.is_empty() and not juggle_game.active():
			landing.start(fall.impact)
			idle_sitting.interact(false)
			roaming.interrupt()
			if landing.state == "hard": behavior.command("normal")
		landing.set_suspended(falling.state=="held" or (falling.active() and not falling.body.grounded) or juggle_game.active())
		var landing_event: Dictionary = landing.update(dt, drag_paused)
		if landing_event.sit:
			pet.set_seated(true, landing_event.sit_speed)
			idle_sitting.automatically_seated = true
		if landing_event.finished: idle_sitting.interact(false)
		if fall.landed:
			idle_sitting.interact(false)
			if manual_sit_pending and not falling.active():
				manual_sit_pending = false
				idle_sitting.manual_pose()
				pet.set_seated(true)
		_advance_size_change(dt, sleep_cycle.active() or drag_paused or dragging or menu_holding or menu.visible or settings_window.visible \
			or catch_game.active() or juggle_game.active() or falling.active() or drag_motion.active() \
			or landing.active() or bowl_hit.active() or bowl_summon.active() or bowl_jump.active() \
			or pickup.active() or behavior.chewing.active() or roaming.weight > 0.001 \
			or (pet.sitting.amount > 0.001 and pet.sitting.amount < 0.999) \
			or behavior.time < behavior.talk_until or behavior.time < behavior.reaction_until)
		var busy: bool = size_change.pending() or catch_game.active() or juggle_game.active() or dragging or menu.visible or food_dialog_open \
			or drag_motion.active() or falling.active() or landing.active() or fall.landed \
			or get_window().mode == Window.MODE_MINIMIZED \
			or behavior.time < behavior.talk_until or behavior.time < behavior.reaction_until
		busy = busy or behavior.chewing.active() or pickup.active() or bowl_jump.active() or bowl_step.move or bowl_hit.active() or bowl_summon.active()
		var chat_pause := _chat_pauses_roaming()
		_advance_sleep(dt, busy and not menu.visible)
		var sleeping: bool = sleep_cycle.active()
		if idle_sitting.advance(dt, busy or sleeping or chat_pause or roaming.rest_requested or is_finite(bowl_step.goal), pet.sitting.seated):
			roaming.request_rest()
			bubble.hide()
		var movement: Dictionary = roaming.update(dt, Vector2(window.position), Vector2(_pet_size()),
			area, pet.sitting.amount, pet.sitting.seated, idle_sitting.automatically_seated,
			busy or sleeping or chat_pause, menu.visible and not drag_paused and not chat_pause and not sleeping, bowl_step.goal)
		if movement.move:
			window.position = Vector2i(movement.position.round())
			save_timer = 0.6
		if movement.sit >= 0:
			pet.set_seated(movement.sit == 1)
			if movement.sit == 0:
				idle_sitting.interact()
		var settled_pose: bool = pet.sitting.amount>=0.999 if pickup.meal_enabled else pet.sitting.amount<0.0001
		var pickup_pose: Dictionary = pickup.update(dt, settled_pose \
			and roaming.weight < 0.0001 and not falling.active() and not landing.active(), drag_paused or bowl_hit.active())
		pickup_pose.merge(size_change.pose(),true)
		for eaten in pickup.take_finished(): bowl_files.consume(eaten)
		var bowl_food: bool = pickup.current != null and not pickup.current.source.is_empty()
		if bowl_food:
			pickup_pose.desktopBowl = true
			pickup_pose.bowlSource = bowl_window.surface_point()-Vector2(window.position)
		if pickup.take_eat_request(): behavior.command("chew",pickup_pose.biteChewAge)
		var cursor := Vector2(DisplayServer.mouse_get_position() - get_window().position)
		var active: bool = gaze_enabled and not sleeping and not juggle_game.active() and not dragging and not menu.visible \
			and not drag_motion.active() and not falling.active() and not landing.active() and not bowl_hit.active() \
			and not settings_window.visible and get_window().mode != Window.MODE_MINIMIZED
		var anchor: Vector2 = pet.gaze_anchor()
		if pickup.active() or size_change.performing():
			cursor = cursor.lerp(pet.food_gaze(pickup_pose),pickup_pose.get("pickupLook",0.0))
			active = not drag_paused and not bowl_hit.active()
		cursor.x = anchor.x + (cursor.x - anchor.x) * signf(roaming.facing_scale)
		if roaming.weight > 0.0:
			cursor = cursor.lerp(anchor + Vector2(-_pet_size().x * 0.22, 0.0), roaming.weight)
			active = true
		var pose: Dictionary = behavior.update(dt, cursor, anchor,
			float(_pet_size().x), active, drag_paused or bowl_hit.active())
		# Keep animation metadata out of the persistent mouse-follow spring values.
		pose = pose.duplicate()
		pose.merge(pickup_pose,true)
		pose.merge(drag_motion.pose())
		pose.merge(falling.pose(drag_paused))
		pose.merge(landing.pose())
		pose.bowlReach = bowl_step.weight
		pose.bowlCalling = bowl_step.calling
		pose.bowlTime = bowl_step.time
		pose.bowlTilt = bowl_step.tilt
		pose.bowlPaused = bowl_step.paused
		pose.bowlSummoning = bowl_step.get("summoning",false)
		pose.landingKnee = maxf(pose.get("landingKnee",0.0),bowl_step.knee)
		if bowl_step.weight>0.0:
			pose.headX *= 1.0-bowl_step.weight
			pose.headY *= 1.0-bowl_step.weight
			pose.headZ = lerpf(pose.headZ,0.10*bowl_step.wave,bowl_step.weight)
			pose.bodyX = lerpf(pose.bodyX,0.04*bowl_step.wave,bowl_step.weight)
		pose.fallLanded = fall.landed
		# DragMotion releases its strain smoothly; FallingPose crossfades the
		# smaller speed-dependent elongation as the suspended pose fades.
		pose.dragStretch *= 1.0 - pose.fallNormalize
		pose.walkWeight = roaming.weight
		pose.walkPhase = roaming.phase
		pose.facingScale = drag_motion.facing if drag_motion.active() else roaming.facing_scale
		if falling.active():
			pose.facingScale = falling.physical_facing
			pose.dragTilt = pose.physicsAngle * pose.facingScale
			pose.dragSwingSpeed = pose.physicsSpin * pose.facingScale
		# Use the fractional travel position, avoiding integer-window jitter at
		# slow walking speeds. Dragging is sampled from the actual host window.
		pose.motionOrigin = movement.position if movement.move else Vector2(window.position)
		if falling.active() or fall.landed: pose.motionOrigin = fall.position
		pose = bowl_hit.prepare(pose)
		pose = dizzy_carry.prepare(pose,0.0 if drag_paused else dt,landing.suspended and landing.state=="hard",falling.state=="held",drag_motion.velocity.x)
		pose = juggle_motion.prepare(pose,0.0 if drag_paused else dt,juggle_game.active(),dragging,drag_motion.velocity.x,juggle_game.active() or landing.state!="hard")
		pose.merge(sleep_cycle.pose(),true)
		_update_ai_presentation(dt, pose, not busy and not menu_holding)
		pose.motionReset = motion_reset_pending or dt > 0.12 or window.mode == Window.MODE_MINIMIZED
		if not (drag_paused and landing.active()):
			pet.apply_pose(pose, minf(dt, 0.1))
		if bowl_food and pickup_pose.get("pickupFlight",1.0)<0.999 and pet.pickup_pose.food.visible:
			bowl_flight.follow(pet.pickup_pose.food,Vector2(window.position))
			pet.pickup_pose.food.hide()
		else: bowl_flight.hide()
		motion_reset_pending = false
	last_pointer = DisplayServer.mouse_get_position()
	if save_timer > 0.0:
		save_timer -= dt
		if save_timer <= 0.0:
			_save_settings()

func _input(event: InputEvent) -> void:
	if not ready_for_input:
		return
	# A captured drag always owns its release, even outside the silhouette.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		_update_drag_pointer(get_window().position+Vector2i(event.position),true)
		_finish_drag()
		return
	if event is InputEventMouseMotion and dragging:
		_update_drag_pointer(get_window().position+Vector2i(event.position),true)
		return
	if menu.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: menu.hide()
		return
	# Native down can arrive before the next pointer-region polling frame.
	if event is InputEventMouseButton and event.pressed and not dragging: _capture_hit_area()
	if event is InputEventMouse and not dragging and not _pointer_hits_pet(event.position):
		return
	if event is InputEventMouseMotion and event.relative.length_squared() > 0.0:
		var pointer := DisplayServer.mouse_get_position()
		# Moving the pet beneath a stationary pointer is not user interaction.
		if (not roaming.travelling() and not falling.active()) or pointer != last_pointer:
			_register_interaction(false)
		last_pointer = pointer
	if event is InputEventMouseButton:
		if event.pressed and event.button_index != MOUSE_BUTTON_RIGHT:
			_register_interaction()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open_menu(DisplayServer.mouse_get_position())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if dragging: return # Duplicate down must not reattach/reset a live grab.
				drag_input.begin(get_window())
				dragging = true
				drag_moved = false
				drag_pointer = get_window().position+Vector2i(event.position)
				drag_window = get_window().position
				# Catch immediately in midair, before the ordinary click threshold.
				if falling.active():
					drag_moved = true
					_begin_grab()
			elif dragging:
				_finish_drag()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom(24 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -24)

func _open_menu(pointer: Vector2i) -> void:
	_finish_size_canvas()
	bowl_window.end_juggle("打开菜单 · 本轮结束")
	catch_game.finish("打开菜单 · 本轮结束")
	_update_size_menu()
	_update_satiety_menu()
	# A menu stops activity without waking a seated pet or cancelling a landing.
	var area := Rect2(DisplayServer.screen_get_usable_rect(get_window().current_screen))
	var at := falling.window_position() if falling.active() else Vector2(get_window().position)
	var airborne: bool = not landing.active() and (falling.state == "held" \
		or (not falling.body.floor_locked and not falling.body.grounded and at.y + get_window().size.y < area.end.y - 2.0))
	if not falling.active():
		airborne = not landing.active() and at.y + get_window().size.y < area.end.y - 2.0
	dragging = false
	drag_moved = false
	idle_sitting.interact(false)
	if airborne:
		if falling.state != "held":
			drag_pointer = pointer
			_begin_grab(false)
		# Reuse an existing grab attachment so the current spring gap and
		# momentum are continuous. Mouse travel inside the menu never moves it.
		falling.set_pointer(Vector2(pointer))
		menu_holding = true
	else:
		if roaming.state == "turning": roaming.facing = -1 if pet.facing_scale >= 0.0 else 1
		roaming.stop_for_menu(at)
	bubble.hide()
	menu.set_item_checked(menu.get_item_index(10), gaze_enabled)
	menu.set_item_checked(menu.get_item_index(11), get_window().always_on_top)
	menu.set_item_checked(menu.get_item_index(17), bowl_window.visible or bowl_summon.active())
	_release_drag_capture()
	menu.position = pointer
	menu.popup()

func _release_menu_hold() -> void:
	menu_holding = false
	drag_motion.release()
	falling.release()
	idle_sitting.interact(false)
	roaming.interrupt()
	save_timer = 0.3

func _primary_button_pressed() -> bool:
	return drag_input.primary_pressed()

func _release_drag_capture() -> void:
	drag_input.release_capture(get_window())

func _interrupt_drag() -> void:
	if dragging: _finish_drag(true)

func _poll_drag_pointer(dt: float) -> void:
	if not dragging: return
	var pointer := DisplayServer.mouse_get_position()
	var pressed: bool = drag_input.held(get_window())
	if not pressed and drag_input.primary_pressed():
		# Capture transferred to another window: cancellation is never a tap.
		_finish_drag(true)
	else:
		_update_drag_pointer(pointer,pressed,dt)
	if not pressed: drag_input.repair_cache(get_window())

func _update_drag_pointer(cursor: Vector2i, pressed: bool, _dt: float = 1.0 / 60.0) -> void:
	if not dragging:
		return
	if not drag_moved and cursor.distance_to(drag_pointer) > 5.0:
		drag_moved = true
		_begin_grab()
	if drag_moved:
		falling.set_pointer(Vector2(cursor))
	if not pressed: _finish_drag()

func _begin_grab(user_grab := true) -> void:
	_finish_size_canvas()
	if not pet.available:
		return
	_wake_sleep(true)
	if user_grab and not juggle_game.active():
		var old_best: int = catch_game.best
		catch_game.caught(Time.get_ticks_msec()/1000.0,falling.body.wall_sequence,
			falling.body.floor_sequence,falling.body.grounded,falling.state=="falling")
		if catch_game.best>old_best: _save_settings()
	elif not user_grab: catch_game.finish("打开菜单 · 本轮结束")
	if user_grab: bowl_summon.grabbed_cat()
	pickup.cancel(true)
	bowl_jump.cancel()
	if bowl_hit.waiting_for_floor() and landing.state!="hard":
		landing.cancel()
		landing.start({"height":1.0,"speed":LandingMotion.HIGH_SPEED,"dizzy_seconds":bowl_hit.dizzy_seconds,"immediate_dizzy":true})
	bowl_hit.cancel()
	bowl_user_cooldown = 3.0
	menu_holding = false # A real left grab takes ownership from the menu pin.
	manual_sit_pending = false
	if landing.state!="hard": landing.cancel()
	landing.set_suspended(true)
	# Catch the visible direction even when grabbing halfway through a mirror turn.
	roaming.facing = -1 if pet.facing_scale >= 0.0 else 1
	roaming.interrupt()
	idle_sitting.manual_pose()
	pet.set_seated(false)
	behavior.command("normal")
	bubble.hide()
	drag_motion.begin(Vector2(get_window().position), pet.facing_scale)
	falling.begin(Vector2(get_window().position), Vector2(drag_pointer), pet.facing_scale)

func _finish_drag(cancel_click := false) -> void:
	var held: bool = falling.body.held or falling.state=="held" or drag_motion.state=="held"
	if not dragging and (menu_holding or not held): return
	var moved := drag_moved or held
	dragging = false
	drag_moved = false
	_release_drag_capture()
	_register_interaction()
	if moved:
		if falling.state=="held" and not juggle_game.active():
			catch_game.released(Time.get_ticks_msec()/1000.0,falling.body.wall_sequence,
				falling.body.floor_sequence,falling.body.linear_velocity.length(),get_window().size.y)
		drag_motion.release()
		falling.release()
		save_timer = 0.3
	elif not cancel_click:
		pickup.cancel()
		behavior.command("pet")
		_say("喵～", 1.8)
	drag_input.repair_cache(get_window())

func _menu_action(id: int) -> void:
	bowl_window.end_juggle("打开菜单 · 本轮结束")
	if id == 33:
		if sleep_cycle.active(): _wake_sleep()
		else: _request_sleep()
		return
	_register_interaction()
	if id < ACTIONS.size() or id in [12,13,15,16,20,21,22]: _wake_sleep(true)
	if id < ACTIONS.size() or id in [12, 13, 20, 21, 22]: pickup.cancel()
	if id < ACTIONS.size() or id == 13: landing.cancel()
	if id < ACTIONS.size():
		behavior.command(ACTIONS[id])
		if ACTIONS[id] == "talk":
			_say("喵～这是 5 秒口型演示", 5.0)
		else:
			bubble.hide()
	match id:
		10:
			gaze_enabled = not gaze_enabled
		11:
			_apply_topmost(not get_window().always_on_top)
		12:
			idle_sitting.manual_pose()
			manual_sit_pending = falling.active()
			if not manual_sit_pending: pet.set_seated(true)
			bubble.hide()
		13:
			manual_sit_pending = false
			idle_sitting.manual_pose()
			pet.set_seated(false)
			bubble.hide()
		14:
			settings_window.show_settings(idle_sitting.enabled,
				idle_sitting.minimum_seconds, idle_sitting.maximum_seconds, roaming.mode, falling.enabled,bowl_capacity,
				satiety.capacity,satiety.digestion_hours,satiety.auto_open,satiety.used,satiety.resting,
				{"size": size_change.target if size_change.pending() else get_window().size.x, "default_size": int(config.windowSize),
				"minimum_size": int(config.minimumSize), "maximum_size": int(config.maximumSize),
				"gaze": gaze_enabled, "topmost": get_window().always_on_top, "sleep":sleep_cycle.settings()})
		15:
			_start_pickup_demo()
		16:
			food_dialog_open = true
			food_dialog.popup_centered_ratio(0.7)
		17:
			_set_bowl_visible(not (bowl_window.visible or bowl_summon.active()))
		20:
			catch_game.finish("位置已重置 · 本轮结束")
			_cancel_summon()
			bowl_hit.cancel()
			menu_holding = false
			landing.cancel()
			manual_sit_pending = false
			dragging = false
			drag_motion.cancel()
			falling.cancel()
			motion_reset_pending = true
			_request_size(PetSize.BASE)
			var area := DisplayServer.screen_get_usable_rect(get_window().current_screen)
			get_window().position = area.end - get_window().size - Vector2i(32, 32)
			falling.reposition(Vector2(get_window().position))
		21:
			_save_settings()
			get_tree().reload_current_scene()
		22:
			_exit()
		23:
			score_board.open_board(get_window().current_screen)
		24:
			_open_bubble_history()
		25:
			if not _chat_blocked_by_settings():
				ai_chat.hide()
				proactive_companion.reopen()
	save_timer = 0.3

func _start_pickup_demo() -> void:
	if not pet.available: return
	_wake_sleep(true)
	if falling.active() or dragging or menu_holding or landing.active():
		_say("等站稳后再取食喵～", 2.0)
		return
	pickup.cancel(true)
	behavior.command("normal")
	manual_sit_pending = false
	idle_sitting.manual_pose()
	pet.set_seated(true)
	roaming.facing = -1 if pet.facing_scale >= 0.0 else 1
	roaming.interrupt()
	# A nearby bowl for the first-stage demonstration. Both position and reach
	# scale with the pet; a later desktop-folder bowl can use request() directly.
	var distance: float = absf(pet.pivot.x - LivePet.PickupPose.BOWL_CENTER.x) * pet.pixel_scale
	var demo: Array = []
	for i in FoodItem.DEMO_TEXTURES.size():
		demo.append(FoodItem.from_texture(FoodItem.DEMO_TEXTURES[i],["文档图标","相册图标","音乐图标"][i]))
	pickup.request_food(demo,distance,pet.bounds.size.y*pet.pixel_scale)
	bubble.hide()

func _feed_pngs(paths: PackedStringArray) -> void:
	food_dialog_open = false
	_wake_sleep(true)
	var items: Array = []
	var skipped := 0
	for path in paths:
		var food = FoodItem.from_png(path)
		if food.valid(): items.append(food)
		else: skipped += 1
	if items.is_empty():
		_say("没有可吃的图片，请选择有可见内容的 PNG 喵～",3.0)
		return
	if falling.active() or dragging or menu_holding or landing.active():
		_say("等站稳后再喂食喵～",2.0)
		return
	if not pickup.active():
		behavior.command("normal")
		idle_sitting.manual_pose()
		manual_sit_pending = false
		pet.set_seated(true)
		roaming.interrupt()
		roaming.facing = -1 if pet.facing_scale >= 0.0 else 1
	var distance: float = absf(pet.pivot.x-LivePet.PickupPose.BOWL_CENTER.x)*pet.pixel_scale
	pickup.request_food(items,distance,pet.bounds.size.y*pet.pixel_scale)
	_say("收到 %d 份食物喵～%s" % [items.size(),"（跳过 %d 张空白或无法读取的图片）" % skipped if skipped else ""],2.5)

func _fit_position(pos: Vector2i, size: Vector2i) -> Vector2i:
	var screen := DisplayServer.get_screen_from_rect(Rect2i(pos, size))
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	return Vector2i(
		clampi(pos.x, area.position.x, maxi(area.position.x, area.end.x - size.x)),
		clampi(pos.y, area.position.y, maxi(area.position.y, area.end.y - size.y)))

func _zoom(amount: int) -> void:
	# Either wheel direction owns one preset until it finishes, including time
	# spent waiting for another action. A continuing wheel gesture also stays
	# locked after a short shrink finishes; ignored ticks never queue a resize.
	if amount==0: return
	var continuing:=size_wheel_quiet>0.0
	size_wheel_quiet=0.35
	if continuing or size_change.pending(): return
	_request_size(PetSize.step(get_window().size.x,signi(amount)))

func _request_size(pixels: int) -> void:
	_register_interaction()
	size_change.request(pixels,_pet_size().x)
	# Finish a currently held file, without queueing more food ahead of the prop.
	if size_change.pending() and pickup.meal_enabled: pickup.foods.clear()
	_update_size_menu()
	save_timer = 0.3

func _advance_size_change(dt: float, blocked: bool) -> void:
	var old_state: String = size_change.state
	if blocked: _finish_size_canvas()
	size_change.update(dt,_pet_size().x,blocked)
	if blocked: size_anchor = Vector2(NAN,NAN)
	elif old_state == "waiting" and size_change.performing():
		size_anchor = Vector2(get_window().position)+Vector2(get_window().size)*Vector2(0.5,1.0)
	if old_state == "waiting" and size_change.state == "summon":
		behavior.command("normal")
		bubble.hide()
	if size_change.performing() or size_change.finished:
		_resize_now(roundi(size_change.value))
	if size_change.finished:
		_finish_size_canvas()
		size_anchor = Vector2(NAN,NAN)
		_update_size_menu()
		idle_sitting.interact(false)
		_save_settings()
	size_flash.apply(size_change.flash(),Vector2(get_window().size))

func _pet_size() -> Vector2i:
	return Vector2i.ONE*size_canvas_pixels if size_canvas_pixels>0 else get_window().size

func _finish_size_canvas() -> void:
	if size_canvas_pixels<=0: return
	var pixels:=size_canvas_pixels
	size_canvas_pixels=0
	# The completed model already occupies the top-left of the canvas, so this
	# removes only transparent pixels. Native clipping cannot cut off its feet.
	get_window().size=Vector2i.ONE*pixels
	pet.fit(Vector2.ONE*pixels)

func _resize_now(pixels: int) -> void:
	var old_size := _pet_size()
	var size := clampi(pixels, int(config.minimumSize), int(config.maximumSize))
	if size == old_size.x: return
	var new_size := Vector2i.ONE * size
	if not size_anchor.is_finite(): size_anchor = Vector2(get_window().position)+Vector2(old_size)*Vector2(0.5,1.0)
	var pos := Vector2i((size_anchor-Vector2(new_size)*Vector2(0.5,1.0)).round())
	# Keep a stable alpha surface while the model scales. Reallocating the native
	# window each frame lets DWM show the old, oversized body in a smaller client
	# area. The model stays at canvas origin and the window follows its foot anchor.
	size_canvas_pixels=size
	motion_reset_pending=true
	get_window().size=Vector2i.ONE*maxi(get_window().size.x,maxi(size,size_change.target))
	get_window().position = _fit_position(pos, new_size)
	pet.fit(Vector2(new_size))
	if bowl_window.is_inside_tree(): bowl_window.fit_pet(size)
	drag_motion.reposition(Vector2(get_window().position))
	falling.set_geometry(Vector2(new_size), Rect2(DisplayServer.screen_get_usable_rect(get_window().current_screen)), pet.physics_anchor(falling.physical_facing if falling.active() else pet.facing_scale))
	falling.reposition(Vector2(get_window().position))
	if dragging:
		drag_window = get_window().position
		drag_pointer = DisplayServer.mouse_get_position()
		if drag_moved: falling.begin(Vector2(get_window().position), Vector2(drag_pointer), pet.facing_scale)

func _resized() -> void:
	motion_reset_pending = true
	_update_size_menu()
	_sync_hit_viewport()
	pet.fit(Vector2(_pet_size()))
	_position_bubble()
	if bowl_window.is_inside_tree(): bowl_window.fit_pet(_pet_size().y)

func _load_settings() -> void:
	size_canvas_pixels=0
	var settings := ConfigFile.new()
	var has_saved := settings.load(settings_path) == OK
	# Per-throw scoring has a separate record; preserve the old preview's
	# incompatible streak-square record in its original config key.
	var saved_best = settings.get_value("catch_game","best_per_throw",0)
	catch_game.best = clampi(int(saved_best),0,9000000000000000) if saved_best is int or saved_best is float else 0
	var size := int(settings.get_value("window", "size", config.windowSize))
	size = PetSize.nearest(size)
	size_change.initialize(size)
	get_window().size = Vector2i.ONE * size
	var area := DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	var default_pos := area.end - get_window().size - Vector2i(32, 32)
	var pos = settings.get_value("window", "position", default_pos) if has_saved else default_pos
	if not pos is Vector2i:
		pos = default_pos
	get_window().position = _fit_position(pos, get_window().size)
	gaze_enabled = bool(settings.get_value("pet", "gaze_enabled", true))
	get_window().always_on_top = bool(settings.get_value("window", "always_on_top", true))
	var minimum = settings.get_value("pet", "auto_sit_min_seconds",
		settings.get_value("pet", "auto_sit_seconds", IdleSitting.DEFAULT_MIN_SECONDS))
	var maximum = settings.get_value("pet", "auto_sit_max_seconds",
		settings.get_value("pet", "auto_sit_seconds", IdleSitting.DEFAULT_MAX_SECONDS))
	if not (minimum is int or minimum is float):
		minimum = IdleSitting.DEFAULT_MIN_SECONDS
	if not (maximum is int or maximum is float):
		maximum = IdleSitting.DEFAULT_MAX_SECONDS
	idle_sitting.configure(bool(settings.get_value("pet", "auto_sit_enabled", true)),
		float(minimum), float(maximum))
	var sleep_settings := {}
	for key in ["enabled","start_minute","end_minute","frequency"]:
		if settings.has_section_key("sleep",key): sleep_settings[key] = settings.get_value("sleep",key)
	sleep_cycle.configure(sleep_settings)
	roaming.configure(str(settings.get_value("pet", "roaming_mode", "calm")))
	falling.configure(bool(settings.get_value("pet", "auto_fall_enabled", true)))
	bowl_capacity = BowlCapacity.sanitize(settings.get_value("bowl","capacity_bytes",BowlCapacity.DEFAULT))
	satiety.capacity = BowlCapacity.sanitize(settings.get_value("stomach","capacity_bytes",BowlCapacity.DEFAULT))
	satiety.digestion_hours = Satiety.sanitize_hours(settings.get_value("stomach","digestion_hours",Satiety.DEFAULT_HOURS))
	satiety.auto_open = bool(settings.get_value("stomach","auto_open",false))
	satiety.resting = bool(settings.get_value("stomach","resting",false))
	bowl_enabled = bool(settings.get_value("bowl","visible",true))
	var bowl_at = settings.get_value("bowl","position",bowl_saved_position)
	if bowl_at is Vector2i: bowl_saved_position = bowl_at

func _register_interaction(wake: bool = true) -> void:
	var was_sleeping: bool = sleep_cycle.active()
	if wake: _wake_sleep()
	proactive_companion.note_interaction()
	roaming.interrupt()
	if idle_sitting.interact(wake and not was_sleeping and not landing.active()) and pet.available:
		pet.set_seated(false)

func _sleep_minute() -> int:
	if sleep_minute_override >= 0: return sleep_minute_override
	var clock := Time.get_time_dict_from_system()
	return int(clock.hour)*60+int(clock.minute)

func _sleep_blocked(other_busy: bool = false, manual: bool = false) -> bool:
	return other_busy or dragging or menu_holding or food_dialog_open or settings_window.visible or ai_memory.visible or score_board.visible \
		or _chat_pauses_roaming() or catch_game.active() or juggle_game.active() or falling.active() or drag_motion.active() \
		or landing.active() or bowl_hit.active() or bowl_summon.active() or bowl_jump.active() or size_change.pending() \
		or pickup.active() or behavior.chewing.active() or not bowl_files.pending.is_empty() \
		or behavior.time < behavior.talk_until or behavior.time < behavior.reaction_until \
		or get_window().mode == Window.MODE_MINIMIZED or not get_window().visible \
		or (ai_service.busy and str(ai_service.request_kind) in ["chat","proactive","test"]) \
		or (not sleep_cycle.active() and not manual and (bubble.visible or menu.visible or behavior.mode != "normal"))

func _request_sleep() -> void:
	# Menu selection is a deliberate request; the popup may close next frame.
	var popup_open := menu.visible
	if popup_open: menu.hide()
	if _sleep_blocked(false,true) or roaming.travelling() or roaming.weight > 0.001:
		_say("等猫猫忙完、站稳再睡喵～",2.5)
		return
	proactive_companion.note_interaction()
	sleep_cycle.request_sleep()
	_update_satiety_menu()

func _wake_sleep(immediate: bool = false) -> void:
	var had_sleep: bool = sleep_cycle.active()
	if had_sleep and immediate:
		# Carry the last lid aperture into the ordinary expression controller.
		behavior.expression_eye = float(sleep_cycle.pose().get("sleepEye",1.0))
		behavior.blink_was_closed = true
	sleep_cycle.interact(immediate)
	if had_sleep and immediate and sleep_owns_seat:
		sleep_owns_seat = false
		idle_sitting.interact(false)
		if pet.available: pet.set_seated(false)

func _advance_sleep(dt: float, other_busy: bool = false) -> void:
	var settled: bool = not roaming.travelling() and roaming.weight < 0.001 \
		and (pet.sitting.amount < 0.001 or pet.sitting.amount >= 0.999)
	var event: Dictionary = sleep_cycle.advance(dt,{"minute":_sleep_minute(),"blocked":_sleep_blocked(other_busy),"settled":settled})
	if event.started:
		sleep_owns_seat = true
		manual_sit_pending = false
		idle_sitting.manual_pose(); roaming.interrupt()
		behavior.command("normal"); _clear_ai_speech()
		_say("猫猫眯一会儿喵…",2.0)
	if event.sit: pet.set_seated(true,0.65)
	if event.finished and sleep_owns_seat:
		sleep_owns_seat = false
		idle_sitting.interact(false); roaming.interrupt()
		pet.set_seated(false)
	if event.started or event.waking or event.finished: _update_satiety_menu()

func _apply_sleep_settings(value: Dictionary) -> void:
	sleep_cycle.configure(value)
	_save_settings()

func _apply_topmost(value: bool) -> void:
	for window in [get_window(), bowl_window, catch_score]:
		# Even an unchanged Godot flag rebuilds the native window style. Saving
		# only a size/gaze change must leave the cauldron's visible surface alone.
		if window.always_on_top == value: continue
		window.always_on_top = value
		# A real toggle can drop WS_VISIBLE from an unfocusable Win32 widget.
		# Restore only an already-visible window, preserving its handle, alpha,
		# physics and focus. Hidden bowls/score panels must remain hidden.
		if OS.get_name() == "Windows" and window.visible and is_instance_valid(pet.model) \
			and pet.model.has_method("restore_desktop_visibility"):
			var id: int = window.get_window_id()
			if id != DisplayServer.INVALID_WINDOW_ID:
				pet.model.restore_desktop_visibility(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,id))

func _apply_common_settings(pixels: int, gaze: bool, topmost: bool) -> void:
	_request_size(pixels)
	gaze_enabled = gaze
	_apply_topmost(topmost)
	_save_settings()

func _apply_auto_sit_settings(enabled: bool, minimum: float, maximum: float, roaming_mode: String = "", auto_fall_enabled: Variant = null) -> void:
	idle_sitting.configure(enabled, minimum, maximum)
	if not roaming_mode.is_empty():
		roaming.configure(roaming_mode)
	if auto_fall_enabled != null: falling.configure(bool(auto_fall_enabled))
	_save_settings()

func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.load(settings_path)
	settings.set_value("catch_game","best_per_throw",catch_game.best)
	settings.set_value("window", "size", size_change.target if size_change.pending() else PetSize.nearest(get_window().size.x))
	settings.set_value("window", "position", get_window().position)
	settings.set_value("window", "always_on_top", get_window().always_on_top)
	settings.set_value("pet", "gaze_enabled", gaze_enabled)
	settings.set_value("pet", "auto_sit_enabled", idle_sitting.enabled)
	settings.set_value("pet", "auto_sit_min_seconds", idle_sitting.minimum_seconds)
	settings.set_value("pet", "auto_sit_max_seconds", idle_sitting.maximum_seconds)
	var sleep_settings: Dictionary = sleep_cycle.settings()
	for key in sleep_settings: settings.set_value("sleep",key,sleep_settings[key])
	settings.set_value("pet", "roaming_mode", roaming.mode)
	settings.set_value("pet", "auto_fall_enabled", falling.enabled)
	settings.set_value("bowl","capacity_bytes",bowl_capacity)
	settings.set_value("bowl","visible",bowl_enabled)
	settings.set_value("stomach","capacity_bytes",satiety.capacity)
	settings.set_value("stomach","digestion_hours",satiety.digestion_hours)
	settings.set_value("stomach","auto_open",satiety.auto_open)
	settings.set_value("stomach","resting",satiety.resting)
	if bowl_window.is_inside_tree(): settings.set_value("bowl","position",bowl_window.position)
	if settings.has_section_key("pet", "auto_sit_seconds"):
		settings.erase_section_key("pet", "auto_sit_seconds")
	var result := settings.save(settings_path)
	if result != OK:
		push_warning("桌宠设置保存失败：" + error_string(result))

func _exit() -> void:
	ai_service.shutdown()
	bowl_window.end_juggle("退出桌宠 · 本轮结束")
	catch_game.finish("退出桌宠 · 本轮结束")
	_save_settings()
	get_tree().quit()

func _update_catch_game(dt: float) -> void:
	var now := Time.get_ticks_msec()/1000.0
	catch_game.advance(now,falling.body.wall_sequence,falling.body.floor_sequence)
	catch_score.refresh(juggle_game.snapshot(now) if score_game=="juggle" else catch_game.snapshot(now),dt,get_window().current_screen)

func _setup_bowl() -> void:
	add_child(bowl_files); add_child(bowl_window); add_child(bowl_flight)
	bowl_window.drag_input.bridge = pet.model
	bowl_window.fit_pet(get_window().size.y)
	bowl_window.always_on_top = get_window().always_on_top
	bowl_window.full_bytes = bowl_capacity
	bowl_files.stomach_capacity = satiety.capacity
	bowl_files.digestion_hours = satiety.digestion_hours
	var area := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	var default_at := Vector2i(get_window().position.x-bowl_window.size.x+40,area.end.y-bowl_window.size.y)
	bowl_window.place(default_at if bowl_saved_position.x==-99999 else bowl_saved_position)
	bowl_files.message.connect(func(words): _say(words,4.5))
	bowl_files.changed.connect(_observe_stomach)
	bowl_window.files_received.connect(bowl_files.import_files)
	get_window().files_dropped.connect(_on_pet_files_dropped)
	bowl_window.opened.connect(bowl_files.open_folder)
	bowl_window.moved.connect(func(): save_timer = 0.6)
	bowl_window.impact_target = _bowl_hit_target
	bowl_window.struck_pet.connect(_on_bowl_hit)
	bowl_window.juggled.connect(_on_juggled)
	bowl_window.juggling_ended.connect(func(reason): juggle_game.finish(reason))
	bowl_window.intercepted.connect(_cancel_summon)
	bowl_window.hidden_by_user.connect(func(): _set_bowl_visible(false))
	settings_window.bowl_settings_saved.connect(func(value):
		bowl_capacity = value; bowl_window.full_bytes = value; _save_settings())
	settings_window.stomach_settings_saved.connect(_apply_stomach_settings)
	settings_window.open_stomach.connect(bowl_files.open_stomach)
	settings_window.open_bowl.connect(bowl_files.open_folder)
	pickup.serve_allowed = _bowl_in_reach
	pickup.source_available = _food_available
	# Existing host regression tests use isolated settings and must never touch real food.
	if settings_path!=SETTINGS and bowl_root_override.is_empty(): return
	bowl_files.start(bowl_root_override,
		bowl_root_override.get_base_dir().path_join("cache") if not bowl_root_override.is_empty() else "")
	if bowl_enabled: _set_bowl_visible(true)

func _on_pet_files_dropped(paths: PackedStringArray) -> void:
	_register_interaction()
	bowl_window.receive_covered_drop(paths,Vector2(DisplayServer.mouse_get_position()))

func _bowl_hit_target() -> Dictionary:
	if not pet.available or menu.visible or food_dialog_open \
		or get_window().mode==Window.MODE_MINIMIZED: return {}
	var can_juggle: bool = juggle_game.active() or (dragging and drag_moved and not menu_holding)
	if dragging and not can_juggle: return {}
	var cap: PackedVector2Array = pet.crown_cap()
	if cap.size()<2: return {}
	for i in cap.size(): cap[i] += Vector2(get_window().position)
	var head_speed := Vector2.ZERO
	if falling.active() and not falling.paused:
		var head := Vector2.ZERO
		for point in cap: head += point/float(cap.size())
		var arm: Vector2 = head-falling.body.to_global(falling.body.center_of_mass)
		head_speed = falling.body.linear_velocity+Vector2(-arm.y,arm.x)*falling.body.angular_velocity
	return {"cap":cap,"extent":float(_pet_size().y),"juggle":can_juggle,"velocity":head_speed}

func _on_juggled(event: Dictionary) -> void:
	_wake_sleep(true)
	if not juggle_game.active():
		catch_game.finish("开始颠锅 · 本轮结束")
		pickup.cancel(true); behavior.chewing.cancel()
		if landing.state!="hard": landing.cancel()
		bowl_hit.cancel(); bowl_jump.cancel()
		if bowl_summon.active(): bowl_summon.finish()
		roaming.interrupt(); idle_sitting.manual_pose(); pet.set_seated(false)
		bubble.hide()
	score_game = "juggle"
	juggle_game.hit(Time.get_ticks_msec()/1000.0,int(event.walls),bool(event.boosted))
	juggle_motion.struck()

func _on_bowl_hit(impact: Dictionary) -> void:
	_wake_sleep(true)
	var summoning: bool = bowl_summon.state=="calling"
	if bowl_summon.active(): bowl_summon.finish(); bubble.hide()
	var duration := clampf(float(impact.get("dizzy_seconds",3.0)),3.0,6.0)
	# Each armed fall emits exactly once. Any actual hit prolongs existing dizziness,
	# including a low knock or dizziness started by the cat's own high fall.
	if landing.extend_dizziness(duration): return
	if bowl_hit.extend_pending(duration): return
	if not bowl_hit.start("hard" if summoning else impact.kind,duration,summoning): return
	bowl_jump.stop_for_impact()
	bowl_user_cooldown = 1.2
	idle_sitting.interact(false)
	roaming.stop_for_menu(Vector2(get_window().position))
	bubble.hide()

func _bowl_in_reach() -> bool:
	if sleep_cycle.active() or satiety.resting or not bowl_files.storage_ready: return false
	if juggle_game.active() or not bowl_window.visible or bowl_summon.active() or bowl_jump.active() or dragging or falling.active() or landing.active() or bowl_hit.active(): return false
	var window := get_window()
	if window.current_screen != bowl_window.current_screen: return false
	var hand := Vector2(window.position)+Vector2(window.size)*Vector2(0.48,0.76)
	return hand.distance_to(bowl_window.surface_point()) <= window.size.y*0.335

func _update_bowl(dt: float, blocked: bool, area: Rect2) -> Dictionary:
	_update_appetite(dt,blocked)
	bowl_user_cooldown = maxf(0.0,bowl_user_cooldown-dt)
	bowl_poll -= dt
	bowl_window.paused = get_window().mode==Window.MODE_MINIMIZED
	var window := get_window()
	var at := Vector2(window.position)
	var size := Vector2(window.size)
	if bowl_summon.active(): return _update_summon(dt,blocked,area)
	var target := bowl_window.surface_point()
	var present: bool = bowl_window.visible and bowl_files.initialized and window.current_screen==bowl_window.current_screen
	# The invitation is measured from the standing position, so a hop cannot
	# accidentally cancel itself as the window rises toward the bowl.
	var reference: Vector2 = bowl_jump.base_position if bowl_jump.active() else at
	var dx := target.x-(reference.x+size.x*0.48)
	var high: bool = target.y<reference.y+size.y*0.45
	var on_floor: bool = at.y+size.y>=area.end.y-3.0 or bowl_jump.active()
	var invite: bool = not satiety.resting and bowl_files.storage_ready and present and bowl_window.dragging and high and absf(dx)<size.x*0.50 \
		and not pickup.active() and not blocked and on_floor and pet.sitting.amount<0.001 and roaming.weight<0.001
	# A hit stops the invitation but lets an already airborne hop return to earth.
	var other_block: bool = dragging or menu.visible or food_dialog_open \
		or window.mode==Window.MODE_MINIMIZED or drag_motion.active() or falling.active() or landing.active()
	var result := bowl_jump.update(dt,at,size,area,invite,blocked and (not bowl_hit.active() or other_block))
	result.goal = NAN
	if result.say: _say("我的饭盆，我的饭盆",2.2)
	if satiety.resting or blocked or not present or bowl_jump.active() or bowl_user_cooldown>0.0 or behavior.chewing.active(): return result
	var want_food: bool = not bowl_files.entries.is_empty()
	if not want_food and not bowl_window.dragging: return result
	if pickup.active():
		if pickup.current != null and not pickup.current.source.is_empty() and bowl_poll<=0.0 and _bowl_in_reach():
			bowl_poll = 1.0
			var excluded := [pickup.current.source.token]
			for item in pickup.foods: excluded.append(item.source.get("token",""))
			var extra: Array = bowl_files.food_items(excluded)
			if not extra.is_empty(): pickup.request_food(extra,0.0,size.y)
		return result
	if not on_floor: return result
	var facing := -1 if dx<0.0 else 1
	if _bowl_in_reach() and want_food and roaming.facing==facing and roaming.state=="idle" and roaming.weight<0.001:
		if bowl_poll<=0.0:
			bowl_poll = 1.0
			var items: Array = bowl_files.food_items()
			if not items.is_empty():
				behavior.command("normal"); idle_sitting.manual_pose(); pet.set_seated(true)
				# Promote within the topmost band without activating the pet. Its
				# arms/held icon must cover the nearby cauldron where they overlap.
				if window.always_on_top:
					window.always_on_top = false; window.always_on_top = true
				pickup.request_food(items,0.0,size.y)
		return result
	# B3: turn toward food already in reach; never seek a distant bowl.
	if _bowl_in_reach() and want_food and roaming.facing!=facing and roaming.state=="idle":
		if pet.sitting.seated: pet.set_seated(false)
		elif pet.sitting.amount<0.001: roaming.turn_in_place(at,facing)
	return result

func _set_bowl_visible(value: bool) -> void:
	bowl_enabled = value
	if value:
		if not bowl_window.visible and not bowl_summon.active(): bowl_summon.request()
	else:
		bowl_window.end_juggle("关闭饭盆 · 本轮结束")
		_cancel_summon(); bowl_window.hide(); satiety.manual_close()
	save_timer = 0.3

func _cancel_summon() -> void:
	if bowl_summon.active():
		bowl_summon.cancel(); bubble.hide()
	bowl_window.cancel_arrival()

func _crown_bounds() -> Rect2:
	var cap: PackedVector2Array = pet.crown_cap()
	if cap.is_empty(): return Rect2(Vector2(get_window().position),Vector2(get_window().size)*0.5)
	var bounds := Rect2(cap[0]+Vector2(get_window().position),Vector2.ZERO)
	for point in cap: bounds = bounds.expand(point+Vector2(get_window().position))
	return bounds

func _update_summon(dt: float, blocked: bool, area: Rect2) -> Dictionary:
	var result := {"position":Vector2(get_window().position),"move":false,"goal":NAN,
		"weight":0.0,"calling":false,"time":0.0,"wave":0.0,"tilt":0.0,"knee":0.0,"paused":false,"summoning":true}
	if bowl_summon.state=="pending":
		if bowl_jump.active():
			result.merge(bowl_jump.update(dt,Vector2(get_window().position),Vector2(get_window().size),area,false,blocked),true)
			result.summoning = false
			return result
		if blocked or pickup.active() or behavior.chewing.active(): return result
		roaming.stop_for_menu(Vector2(get_window().position))
		idle_sitting.manual_pose(); pet.set_seated(false)
		if pet.sitting.amount>0.001 or roaming.weight>0.001: return result
		bowl_jump.cancel(); behavior.command("normal")
		var cap := _crown_bounds()
		bowl_summon.begin(cap)
		bowl_window.begin_arrival(cap.get_center().x,area)
	var stable: bool = not blocked and not pickup.active() and not behavior.chewing.active()
	var pot := Rect2(bowl_window.at,Vector2(bowl_window.rest_size))
	var step: Dictionary = bowl_summon.update(dt,_crown_bounds(),pot,
		not bowl_window.arrival.active(),pot.end.y>=area.end.y-2.0,
		dragging or menu_holding or falling.active() or drag_motion.active(),stable)
	result.merge(step,true)
	if step.say: _say("出来吧，我的锅锅",2.6)
	if step.thanks:
		behavior.command("satisfied"); _say("谢谢喵",2.4)
		bowl_user_cooldown = 3.0
	return result

func _observe_stomach() -> void:
	bowl_window.total_bytes = bowl_files.total_bytes
	if not bowl_files.storage_ready: return
	var next_bytes := -1
	for entry in bowl_files.entries:
		if not bowl_files.pending.has(entry.token):
			next_bytes = int(entry.get("bytes",0)); break
	# Complete the held icon before entering the resting state.
	if satiety.observe(bowl_files.stomach_bytes,next_bytes,not pickup.active() and bowl_files.pending.is_empty(),bowl_files.all_food_oversized()):
		_save_settings()
	settings_window.update_stomach_usage(satiety.used,satiety.capacity,satiety.resting)

func _apply_stomach_settings(capacity: int, hours: float, auto_open: bool) -> void:
	satiety.capacity = capacity; satiety.digestion_hours = hours; satiety.auto_open = auto_open
	bowl_files.stomach_capacity = capacity; bowl_files.digestion_hours = hours
	bowl_files.next_scan = 0.0
	_observe_stomach()
	_save_settings()

func _food_available(item) -> bool:
	if sleep_cycle.active(): return false
	if not bowl_files.available(item): return false
	var reserved: int = bowl_files.reserved_bytes()
	var other_held: bool = pickup.current!=null and pickup.current!=item and not pickup.current.source.is_empty()
	# During handoff the completed icon has not yet reached the worker queue.
	if other_held:
		var old: Dictionary = pickup.current.source
		if not bowl_files.pending.has(old.token): reserved += int(old.get("bytes",0))
	# A sum of several reservations must never masquerade as one oversized file.
	var allow_oversized: bool = not item.source.is_empty() and not other_held and reserved==0 and bowl_files.pending.is_empty() and bowl_files.all_food_oversized()
	return satiety.can_take(int(item.source.get("bytes",0))+reserved,allow_oversized)

func _update_appetite(dt: float, blocked: bool) -> void:
	if not bowl_files.storage_ready: return
	var occupied: bool = sleep_cycle.active() or blocked or pickup.active() or behavior.chewing.active() or bowl_jump.active() or bowl_summon.active() \
		or roaming.travelling() or behavior.time<behavior.reaction_until
	if satiety.full_pending and not occupied:
		satiety.full_pending = false
		behavior.command("satisfied")
		_say("吃饱了",2.4)
	var request: String = satiety.request_bowl(dt,bowl_window.visible,occupied)
	if request=="open": _set_bowl_visible(true)
	elif request=="ask": _say("肚子饿啦，帮我打开饭盆好不好？",4.0)
