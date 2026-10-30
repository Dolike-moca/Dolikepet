extends Node
## Local timing owns invitations. GPT only chooses their wording.
signal invitation_started(text: String)
signal invitation_stopped
signal invitation_expanded
const Scheduler = preload("res://scripts/proactive_scheduler.gd")
const Card = preload("res://scripts/proactive_card.gd")
const Store = preload("res://scripts/ai_store.gd")
var scheduler = Scheduler.new()
var card = Card.new()
var service: Node
var host: Node
var native_bridge: Object
var environment_enabled := false
var activity_override: Callable
var _store = Store.new()
var _sample_age := 0.0
var _save_age := -1.0
var _activity := {"idle_seconds":0.0,"locked":true,"fullscreen":false}
var _pending: Dictionary = {}
var _request_age := 0.0
var _lead_remaining := 0.0
var _draft := ""
var _settings: Dictionary = {}
var _last_allowed := false
var _showing_invitation := false

func setup(owner_host: Node, companion: Node, bridge: Object, directory: String, enabled: bool) -> void:
	host = owner_host; service = companion; native_bridge = bridge; environment_enabled = enabled
	_store.setup(directory.path_join("invitations"))
	var saved := _store.load_data()
	scheduler.load_state(saved.get("scheduler", {}) if saved.get("scheduler") is Dictionary else {})
	_draft = str(saved.get("draft", "")).left(2000)
	card.native_bridge = native_bridge
	add_child(card); card.setup(service); card.set_draft(_draft)
	card.draft_changed.connect(func(text: String): _draft = text.left(2000); _save_age = 0.6)
	card.answered.connect(func(_text: String): scheduler.feedback("replied"); _changed())
	card.action_requested.connect(func(action: String): scheduler.feedback(action); _changed())
	card.dismissed.connect(func(reason: String):
		if reason == "ignored": scheduler.feedback("ignored"); _changed()
		elif reason == "idle_timeout":
			# Finishing an automatic reading timeout is not a rejected invitation.
			# Close its feedback slot without increasing the ignore cooldown.
			scheduler.feedback("unavailable"); _changed())
	service.reply_completed.connect(_reply_completed)
	service.failed.connect(_failed)
	service.request_canceled.connect(_cancel_pending)
	service.history_cleared.connect(card.reset_session)
	service.account_changed.connect(card.reset_session)
	service.request_started.connect(func(kind: String):
		if kind == "chat": _cancel_pending(); note_interaction())
	service.state_changed.connect(_configure)
	_configure()

func _configure() -> void:
	if _settings == service.settings: return
	var was_enabled := bool(_settings.get("proactive", false))
	var route_changed: bool = not _settings.is_empty() and _settings.get("auth_method", "api_key") != service.settings.get("auth_method", "api_key")
	var sharing_changed: bool = not _settings.is_empty() and _settings.get("include_pet_state", true) != service.settings.get("include_pet_state", true)
	_settings = service.settings.duplicate(true)
	scheduler.configure(_settings)
	if route_changed: card.reset_session()
	if sharing_changed:
		_cancel_pending()
		if service.busy and service.request_kind == "proactive": service.cancel()
	if was_enabled and not bool(_settings.get("proactive", false)):
		_cancel_pending()
		card.suspend()

func note_interaction() -> void:
	scheduler.note_pet_interaction()

func game_finished(game: String, score: int) -> void:
	scheduler.note_game_finished(game, score)

func tick(dt: float, idle: bool) -> void:
	if not is_instance_valid(host) or service == null: return
	if _save_age >= 0.0:
		_save_age -= dt
		if _save_age <= 0.0: _save(); _save_age = -1.0
	var monitor: bool = bool(_settings.get("proactive", false)) or card.visible or card.engaged() or card.has_draft()
	_sample_age += maxf(dt, 0.0)
	if monitor and environment_enabled and _sample_age >= 1.0:
		if activity_override.is_valid(): _activity = activity_override.call()
		elif is_instance_valid(native_bridge) and native_bridge.has_method("companion_activity_snapshot"):
			_activity = native_bridge.call("companion_activity_snapshot")
	var safe: bool = environment_enabled and idle and not bool(_activity.get("locked", true)) and not bool(_activity.get("fullscreen", true)) \
		and not host.ai_chat.visible and not host.ai_memory.visible and not host.settings_window.visible
	# A delayed frame can be sleep/resume. Discard unshown invitations before
	# advancing the two-second lead, then let the scheduler apply its warmup.
	if dt > 5.0 or _sample_age > 5.0:
		safe = false
		_cancel_pending()
		if service.busy and service.request_kind == "proactive": service.cancel()
	# Keep the anchor current while suspended too, so a drag does not restore the
	# conversation at the cat's old screen position for even the first frame.
	card.update_anchor(Rect2i(host.get_window().position, host.get_window().size), host.get_window().current_screen)
	card.advance(dt, safe)
	_last_allowed = safe
	if not _pending.is_empty():
		_request_age += dt
		if not safe or _request_age > 30.0:
			_cancel_pending()
			if service.busy and service.request_kind == "proactive": service.cancel()
		elif _lead_remaining > 0.0:
			_lead_remaining -= dt
			if _lead_remaining <= 0.0:
				var text := str(_pending.get("text", ""))
				var reason := str(_pending.get("reason", "reconnect"))
				_pending = {}
				_showing_invitation = false
				var revealed := int(host.call("_invitation_visible_characters")) if host.has_method("_invitation_visible_characters") else 0
				if card.present(text, reason, Rect2i(host.get_window().position, host.get_window().size), host.get_window().current_screen, revealed):
					# This is the same utterance moving to its expanded surface,
					# not a cancellation or a second reading of the invitation.
					invitation_expanded.emit()
				else:
					invitation_stopped.emit()
					scheduler.feedback("unavailable")
				_changed()
	if _sample_age < 1.0: return
	var elapsed := _sample_age; _sample_age = 0.0
	var now := Time.get_datetime_dict_from_system()
	var snapshot := _activity.duplicate()
	snapshot.allowed = safe and not service.busy and _pending.is_empty() and not host.bubble.visible
	snapshot.dialog_open = card.visible or card.engaged() or card.has_draft()
	snapshot.now_unix = Time.get_unix_time_from_system()
	snapshot.local_hour = int(now.hour)
	snapshot.local_day = "%04d-%02d-%02d" % [now.year, now.month, now.day]
	if not environment_enabled: snapshot.allowed = false; snapshot.locked = true
	var invitation: Dictionary = scheduler.advance(elapsed, snapshot)
	if not invitation.is_empty(): _start(invitation)

func _start(invitation: Dictionary) -> void:
	if not _pending.is_empty() or card.engaged() or card.has_draft(): return
	_pending = invitation.duplicate(true)
	var context: Dictionary = host.call("_ai_context") if is_instance_valid(host) and host.has_method("_ai_context") else {}
	_pending.topic = service.prepare_proactive_topic(str(invitation.reason), invitation.get("context", {}), context)
	_request_age = 0.0
	_lead_remaining = 0.0
	_changed()
	if service.ready_to_chat() and service.send_proactive(str(invitation.reason), invitation.get("context", {}), _pending.topic): return
	if not _pending.is_empty() and _lead_remaining <= 0.0: _prepare(str(_pending.topic.fallback))

func _reply_completed(text: String, proactive: bool) -> void:
	if proactive and not _pending.is_empty(): _prepare(text)

func _failed(_message: String) -> void:
	if not _pending.is_empty() and _lead_remaining <= 0.0: _prepare(str(_pending.topic.fallback))

func _prepare(text: String) -> void:
	if not _last_allowed: _cancel_pending(); return
	_pending.text = text.strip_edges().left(180)
	_lead_remaining = 2.0
	_showing_invitation = true
	invitation_started.emit(str(_pending.text))

func _cancel_pending() -> void:
	if _pending.is_empty(): return
	_pending = {}; _lead_remaining = 0.0
	scheduler.feedback("unavailable")
	if _showing_invitation: invitation_stopped.emit()
	_showing_invitation = false
	_changed()

func reopen() -> void:
	# Explicit typing supersedes an invitation still waiting for wording/lead-in.
	_cancel_pending()
	if service.busy and service.request_kind == "proactive": service.cancel()
	# A manual first-open must not inherit the fail-closed startup snapshot for
	# one second and immediately lose its input focus while the sampler catches up.
	if environment_enabled:
		if activity_override.is_valid(): _activity = activity_override.call()
		elif is_instance_valid(native_bridge) and native_bridge.has_method("companion_activity_snapshot"):
			_activity = native_bridge.call("companion_activity_snapshot")
		_sample_age = 0.0
	card.update_anchor(Rect2i(host.get_window().position, host.get_window().size), host.get_window().current_screen)
	card.reopen()

func _changed() -> void:
	_save_age = 0.0

func _save() -> void:
	var error: Error = _store.save_data({"schema":1,"scheduler":scheduler.dump_state(),"draft":_draft})
	if error != OK: push_warning("主动对话偏好保存失败；未发送草稿仍保留在本次运行中。")

func _exit_tree() -> void:
	if service != null: _save()

