extends SceneTree
## Real pet coordinator; isolated config, no input injection or food worker.
const Scene = preload("res://scenes/pet.tscn")
const Sleep = preload("res://scripts/sleep_cycle.gd")
const Food = preload("res://scripts/food_item.gd")
class PassiveBridge extends RefCounted:
	func show_companion_without_activation(_handle: int) -> bool: return true

var checks := 0
var failures: Array[String] = []
var app
var base := ""
var settings_path := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("SLEEP HOST: fixture timeout"); quit(1))
	call_deferred("run")

func tick(frames: int) -> void:
	for frame in frames:
		app._process(1.0/30.0)
		if frame % 12 == 11: await process_frame

func reset_awake() -> void:
	app.settings_window.hide(); app.ai_chat.hide(); app.ai_memory.hide(); app.score_board.hide()
	app.menu.hide(); app.menu_holding = false; app.dragging = false; app.drag_moved = false
	app.proactive_companion._cancel_pending()
	app.proactive_companion.card.set_draft(""); app.proactive_companion.card.reset_session()
	app.ai_service.cancel(); app._clear_ai_speech(); app.bubble.hide()
	app.pickup.cancel(true); app.behavior.chewing.cancel(); app.behavior.command("normal")
	app.bowl_hit.cancel(); app.bowl_jump.cancel(); app.bowl_summon.finish()
	app.drag_motion.cancel(); app.falling.cancel(); app.landing.cancel()
	app.catch_game.finish("fixture reset"); app.juggle_game.finish("fixture reset")
	app.bowl_files.pending.clear(); app.bowl_files.entries.clear(); app.bowl_files.storage_ready = false
	app.bowl_enabled = false; app.bowl_window.hide()
	app.roaming.configure("off"); app.roaming.weight = 0.0
	app.idle_sitting.configure(false,60.0,180.0)
	app.pet.set_seated(false); app.pet.sitting.amount = 0.0; app.pet.sitting.velocity = 0.0
	app.sleep_cycle = Sleep.new(); app.sleep_cycle.rng.seed = 20261031
	app.sleep_cycle.random_source = func(): return 0.0
	app.sleep_owns_seat = false; app.sleep_minute_override = 0
	app.sleep_cycle.advance(0.0,{"minute":0})
	app.update_notices.clear()
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x+200,area.end.y-root.size.y)
	app.falling.reposition(Vector2(root.position))
	app.ai_service.apply_settings({"enabled":false,"proactive":false})

func make_sleep() -> void:
	app.sleep_cycle.idle_seconds = 29.75
	app._advance_sleep(0.25)
	await tick(210)
	app.bubble.hide()

func run() -> void:
	base = ProjectSettings.globalize_path("res://../../_work/tests/sleep-host/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(base)
	settings_path = base.path_join("pet.cfg")
	var config := ConfigFile.new()
	config.set_value("window","size",300)
	config.set_value("pet","auto_fall_enabled",false)
	config.set_value("pet","auto_sit_enabled",false)
	config.set_value("pet","roaming_mode","off")
	config.set_value("bowl","visible",false)
	config.save(settings_path)
	app = Scene.instantiate(); app.settings_path = settings_path
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false); app.bowl_files.set_process(false)
	app.ai_chat.set_process(false); root.mouse_passthrough = true
	app.settings_window.updater.cache_dir = base.path_join("updates")
	await process_frame
	check(app.pet.available,"pet model did not load")
	check(app.bowl_files.helper.is_empty() and app.bowl_files.jobs.is_empty(),"fixture activated a user-data food worker")
	check(not app.ai_service._network_allowed,"isolated host enabled real AI network")
	if not app.pet.available: finish(); return
	reset_awake()
	await verify_sleep_and_wake()
	await verify_interruptions()
	await verify_busy_states()
	await verify_settings()
	finish()

func verify_sleep_and_wake() -> void:
	app.sleep_cycle.idle_seconds = 29.75
	app._advance_sleep(0.25)
	check(app.sleep_cycle.state=="drowsy" and app.sleep_owns_seat,"night idle opportunity did not start host-owned sleep")
	check(app.bubble.visible and app.bubble_label.text=="猫猫眯一会儿喵…","entry did not use the existing local speech bubble")
	check(app.menu.get_item_text(app.menu.get_item_index(33))=="叫醒猫猫","sleep menu did not become wake entry")
	await tick(210)
	check(app.sleep_cycle.state=="asleep" and app.pet.sitting.seated and app.pet.sitting.amount>=0.999,"real model never settled into ordinary seated sleep")
	check(not app.pet.pickup_pose.hold_rig.enabled and not app.pickup.active(),"sleep borrowed the feeding/held-prop arms")
	var saved_phase: float = app.sleep_cycle.phase
	var saved_idle: float = app.sleep_cycle.idle_seconds
	app._register_interaction(false)
	check(app.sleep_cycle.state=="asleep" and app.sleep_cycle.phase==saved_phase and app.sleep_cycle.idle_seconds==saved_idle,"hover-style interaction woke or reset sleep")
	var origin := root.position
	app.roaming.configure("free"); app.roaming.wait_remaining = 0.0; app.roaming.rest_remaining = 0.0
	app.idle_sitting.configure(true,5.0,5.0)
	app.idle_sitting.automatically_seated = true; app.idle_sitting.elapsed = 100.0
	app.sleep_cycle.nap_seconds = 1.0
	for frame in 7200: app._advance_sleep(0.25)
	await tick(90)
	check(app.sleep_cycle.state=="asleep" and app.pet.sitting.seated and root.position==origin,"night sleep was woken by nap/roaming/automatic-sit timers")
	check(is_zero_approx(app.roaming.weight) and app.roaming.state=="idle","sleep allowed autonomous walking to restart")
	app.bowl_files.initialized = true; app.bowl_files.storage_ready = true
	app.satiety.resting = false; app.satiety.auto_open = true; app.satiety.reminder_wait = 0.0
	app.bubble.hide()
	app._update_appetite(0.1,false)
	check(not app.bowl_summon.active() and not app.bubble.visible,"sleep allowed a hungry request or automatic pot summon")
	check(not app._bowl_in_reach() and not app._food_available(Food.from_texture(Food.DEMO_TEXTURES[0],"fixture")),"sleep allowed a bowl food pickup")
	app.proactive_companion.environment_enabled = true
	app.proactive_companion.activity_override = func(): return {"idle_seconds":0.0,"locked":false,"fullscreen":false}
	app.ai_service.apply_settings({"enabled":false,"proactive":true,"quiet_start":0,"quiet_end":0})
	var pose := {"mouth":0.0,"eyeNear":0.0,"eyeFar":0.0}
	app._update_ai_presentation(1.0,pose,true)
	check(not app.proactive_companion._last_allowed and app.proactive_companion._pending.is_empty() and not app.proactive_companion.card.visible,"sleep allowed a proactive conversation")
	app._queue_update_notice("isolated-sleep-notice","测试更新已准备好")
	app._show_update_notice()
	check(app.update_notices.size()==1 and not app.bubble.visible,"background update notice woke sleeping cat")
	app.bowl_files.storage_ready = false
	app._register_interaction(true)
	check(app.sleep_cycle.state=="waking" and app.pet.sitting.seated and app.sleep_cycle.pose().sleepEye==0.0,"click jumped straight from sleep to standing/open eyes")
	await tick(24)
	check(app.sleep_cycle.state=="waking" and app.sleep_cycle.pose().sleepEye>0.0 and app.sleep_cycle.pose().sleepEye<1.0,"click wake did not gradually reopen the eyes")
	await tick(60)
	check(app.sleep_cycle.state=="awake" and not app.sleep_owns_seat and not app.pet.sitting.seated,"wake completion did not release seated ownership")
	check(app.sleep_cycle.cooldown>115.0,"click wake omitted two-minute clear-awake protection")
	check(app.menu.get_item_text(app.menu.get_item_index(33))=="睡觉","wake did not restore menu label")
	app._show_update_notice()
	check(app.update_notices.is_empty() and app.bubble_label.text=="测试更新已准备好","queued update notice was lost after waking")

func verify_interruptions() -> void:
	reset_awake()
	app._menu_action(33)
	app._advance_sleep(1.0/30.0)
	check(app.sleep_cycle.state=="drowsy","manual menu did not start sleep immediately")
	app._menu_action(33)
	check(app.sleep_cycle.state=="waking","manual menu did not toggle to natural wake")
	await tick(90)
	reset_awake(); await make_sleep()
	app.drag_pointer = root.position+Vector2i(140,80)
	app._begin_grab()
	check(not app.sleep_cycle.active() and app.sleep_cycle.pose().sleepWeight==0.0,"physical grab left sleep pose active")
	check(app.falling.state=="held" and app.drag_motion.state=="held" and not app.pet.sitting.seated,"sleep blocked the existing held/drag posture")
	check(app.behavior.blink_was_closed and app.behavior.expression_eye==0.0,"grab did not pass closed lids into normal eye recovery")
	reset_awake(); await make_sleep()
	app._on_bowl_hit({"kind":"hard","dizzy_seconds":5.0})
	check(not app.sleep_cycle.active() and app.bowl_hit.active(),"pot impact failed to take over sleeping posture immediately")
	await tick(18)
	check(app.bowl_hit.active() or app.landing.active(),"existing impact/dizzy motion did not continue after sleep interruption")
	reset_awake(); await make_sleep()
	app._open_bubble_history()
	check(app.ai_chat.visible and app.sleep_cycle.state=="waking","manual conversation did not naturally wake sleeping cat")
	await tick(90)
	check(app.sleep_cycle.state=="awake" and app._sleep_blocked(),"opened full chat did not keep the cat awake")
	app.sleep_cycle.idle_seconds = 90.0
	app.ai_chat.input.text = "用户继续输入"; app.ai_chat.input.text_changed.emit()
	check(app.sleep_cycle.idle_seconds==0.0 and app.sleep_cycle.cooldown==120.0,"full-chat typing did not renew sleep activity")
	app.ai_chat.hide()

func verify_busy_states() -> void:
	reset_awake()
	app.ai_chat.open_panel(); app.sleep_cycle.idle_seconds = 300.0
	app._advance_sleep(0.25)
	check(not app.sleep_cycle.active() and app.sleep_cycle.checks==0,"full conversation failed to block automatic sleep")
	app.ai_chat.hide()
	app.settings_window.show_settings(false,60.0,180.0)
	app._advance_sleep(0.25)
	check(not app.sleep_cycle.active() and app.sleep_cycle.checks==0,"settings page failed to block automatic sleep")
	app.settings_window.hide()
	var card = app.proactive_companion.card
	card.native_bridge = PassiveBridge.new(); card.hover_override = 0
	card.update_anchor(Rect2i(root.position,root.size),root.current_screen)
	card.reopen(); app._advance_sleep(0.25)
	check(card.visible and not app.sleep_cycle.active() and app.sleep_cycle.checks==0,"compact composer failed to block automatic sleep")
	app.sleep_cycle.idle_seconds = 90.0
	card.set_draft("小气泡草稿"); card.draft_changed.emit(card.input.text)
	check(app.sleep_cycle.idle_seconds==0.0 and app.sleep_cycle.cooldown==120.0,"compact typing did not renew sleep activity")
	card.set_draft(""); card.reset_session()
	app.pickup.request_food([Food.from_texture(Food.DEMO_TEXTURES[0],"meal fixture")],0.0,root.size.y)
	app.sleep_cycle.idle_seconds = 300.0; app.sleep_cycle.cooldown = 0.0
	app._advance_sleep(0.25)
	check(app.pickup.active() and not app.sleep_cycle.active(),"active meal failed to block automatic sleep")
	app.pickup.cancel(true)
	app.bowl_files.pending["isolated-pending"] = 0
	app._advance_sleep(0.25)
	check(not app.sleep_cycle.active(),"pending food commit failed to block automatic sleep")
	app.bowl_files.pending.clear()
	app.sleep_cycle.idle_seconds = 300.0
	app._advance_sleep(0.25)
	check(app.sleep_cycle.active(),"idle opportunity never resumed after busy states cleared")

func verify_settings() -> void:
	reset_awake()
	app._menu_action(14)
	var window = app.settings_window
	window.sleep_enabled.button_pressed = true
	window.sleep_start_hour.value = 22; window.sleep_start_minute.value = 15
	window.sleep_end_hour.value = 7; window.sleep_end_minute.value = 45
	window.sleep_frequency.value = 2
	var before: Dictionary = app.sleep_cycle.settings()
	window.hide()
	check(app.sleep_cycle.settings()==before,"closing settings applied an unsaved sleep draft")
	app._menu_action(14)
	check(window.sleep_start_hour.value==23 and window.sleep_end_hour.value==8 and window.sleep_frequency.value==1,"reopening settings did not restore saved sleep values")
	window.sleep_start_hour.value = 22; window.sleep_start_minute.value = 15
	window.sleep_end_hour.value = 7; window.sleep_end_minute.value = 45
	window.sleep_frequency.value = 2
	window._save()
	var wanted := {"enabled":true,"start_minute":1335,"end_minute":465,"frequency":2}
	check(not window.visible and app.sleep_cycle.settings()==wanted,"save did not apply the complete sleep draft")
	var stored := ConfigFile.new(); var loaded := stored.load(settings_path)
	check(loaded==OK and stored.get_value("sleep","start_minute")==1335 and stored.get_value("sleep","end_minute")==465 and stored.get_value("sleep","frequency")==2,"sleep preferences did not persist to isolated config")
	app.sleep_cycle.configure({"enabled":false})
	app._load_settings()
	check(app.sleep_cycle.settings()==wanted,"host reload did not restore persisted sleep preferences")
	app._menu_action(14)
	check(window.sleep_start_hour.value==22 and window.sleep_start_minute.value==15 and window.sleep_end_hour.value==7 and window.sleep_end_minute.value==45 and window.sleep_frequency.value==2,"reopened settings did not display reloaded clock/frequency")
	window.hide()

func finish() -> void:
	if is_instance_valid(app): app.queue_free()
	for failure in failures: printerr("SLEEP HOST: "+failure)
	print("Sleep host: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
