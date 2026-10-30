extends RefCounted
## Local timing only. It receives coarse activity snapshots, never key content.
const ACTIVE_IDLE_SECONDS := 60.0
const BREAK_SECONDS := 300.0
const RESUME_GRACE := 300.0
const INTERACTION_GRACE := 120.0
const REST_SECONDS := 3600.0
const DEFAULT_RECONNECT_SECONDS := 3600.0
const GAME_TTL := 15.0
const SNOOZE_SECONDS := 600.0
const DEFAULTS := {
	"proactive":false, "proactive_interval_minutes":60,
	"proactive_rest":true, "proactive_games":true, "proactive_reconnect":true,
	"proactive_daily_limit":4, "quiet_enabled":true, "quiet_start":22, "quiet_end":8,
}
var rng := RandomNumberGenerator.new()
var random_source: Callable # Isolated deterministic tests may inject a roll.
var options: Dictionary = DEFAULTS.duplicate()
var active_seconds := 0.0
var active_since_interaction := 0.0
var _next_rest_at := REST_SECONDS
var _next_reconnect_at := DEFAULT_RECONNECT_SECONDS
var _now := 0.0
var _last_sample := 0.0
var _started := false
var _configured := false
var _day := ""
var _daily_count := 0
var _quiet_today := ""
var _ignore_streak := 0
var _last_offer := 0.0
var _warmup_until := 0.0
var _interaction_until := 0.0
var _was_locked := false
var _was_away := false
var _was_quiet := false
var _pending_game: Dictionary = {}
var _snooze: Dictionary = {}
var _last_offer_details: Dictionary = {}
var _awaiting_feedback := false

func _init() -> void:
	rng.randomize()

func configure(settings: Dictionary) -> void:
	var next := DEFAULTS.duplicate()
	for key in ["proactive", "proactive_rest", "proactive_games", "proactive_reconnect", "quiet_enabled"]:
		if settings.get(key) is bool: next[key] = settings[key]
	for key in ["proactive_interval_minutes", "proactive_daily_limit", "quiet_start", "quiet_end"]:
		if _number(settings.get(key)): next[key] = int(settings[key])
	next.proactive_interval_minutes = clampi(next.proactive_interval_minutes, 5, 240)
	# Zero removes only the daily count cap; timing and interruption gates stay on.
	next.proactive_daily_limit = clampi(next.proactive_daily_limit, 0, 8)
	next.quiet_start = clampi(next.quiet_start, 0, 23)
	next.quiet_end = clampi(next.quiet_end, 0, 23)
	if not settings.get("quiet_enabled") is bool:
		next.quiet_enabled = next.quiet_start != next.quiet_end
	var toggled: bool = next.proactive != options.proactive
	var cadence_changed: bool = next.proactive_interval_minutes != options.proactive_interval_minutes
	options = next
	if toggled:
		_started = false
		_reset_activity()
		_pending_game.clear(); _awaiting_feedback = false
		if _configured: _snooze.clear()
	elif cadence_changed:
		# A new frequency starts a new interval, rather than immediately spending
		# active time accumulated under a previous, slower setting.
		_next_reconnect_at = active_since_interaction + _reconnect_seconds()
	_configured = true
	if not options.proactive_games: _pending_game.clear()
	if not _snooze.is_empty() and not _reason_enabled(str(_snooze.get("reason", ""))): _snooze.clear()

func advance(dt: float, snapshot: Dictionary) -> Dictionary:
	if not _valid_snapshot(snapshot):
		# Missing native activity data must not be interpreted as active use.
		_started = false; _pending_game.clear(); _snooze.clear(); _reset_activity()
		return {}
	_now = float(snapshot.now_unix)
	var day := str(snapshot.local_day)
	if _day.is_empty() or day > _day:
		if not _day.is_empty() and _day == _quiet_today:
			_warmup_until = _now + RESUME_GRACE
			_pending_game.clear(); _snooze.clear()
		_daily_count = 0; _ignore_streak = 0
	_day = day
	var locked := bool(snapshot.get("locked", true))
	var away: bool = float(snapshot.idle_seconds) >= BREAK_SECONDS
	var quiet := _quiet(int(snapshot.local_hour))
	if not _started:
		_started = true; _last_sample = _now
		if _last_offer > _now: _last_offer = _now
		_warmup_until = _now + RESUME_GRACE
		_was_locked = locked; _was_away = away; _was_quiet = quiet
		_pending_game.clear()
		return {}
	var gap := _now - _last_sample
	_last_sample = _now
	var interrupted := not is_finite(dt) or dt < 0.0 or dt > 5.0 or gap > 10.0 or gap < -1.0
	if interrupted or locked or away:
		_reset_activity()
		_pending_game.clear(); _snooze.clear()
		_warmup_until = _now + RESUME_GRACE
		if gap < -1.0:
			# Rebase rather than allowing a rollback to repeatedly bypass cooldown.
			if _last_offer > _now: _last_offer = _now
			_interaction_until = _now + INTERACTION_GRACE
		_was_locked = locked; _was_away = away; _was_quiet = quiet
		return {}
	if _was_locked or _was_away or (_was_quiet and not quiet):
		_warmup_until = _now + RESUME_GRACE
		_pending_game.clear(); _snooze.clear()
	_was_locked = locked; _was_away = away; _was_quiet = quiet
	if not options.proactive:
		_reset_activity(); _pending_game.clear(); _snooze.clear()
		return {}
	if float(snapshot.idle_seconds) < ACTIVE_IDLE_SECONDS:
		# Count elapsed sampling time, never an OS clock leap or catch-up loop.
		var elapsed := clampf(minf(dt, maxf(0.0, gap)), 0.0, 5.0)
		active_seconds += elapsed
		active_since_interaction += elapsed
	var candidate := {}
	if not _pending_game.is_empty():
		if _now - float(_pending_game.at) > GAME_TTL: _pending_game.clear()
		else:
			candidate = {"reason":"game", "context":_pending_game.context}
	if active_seconds >= _next_rest_at:
		_next_rest_at = (floorf(active_seconds / REST_SECONDS) + 1.0) * REST_SECONDS
		if options.proactive_rest:
			candidate = {"reason":"rest", "context":{"continuous_minutes":int(active_seconds / 60.0)}}
	if active_since_interaction >= _next_reconnect_at:
		_next_reconnect_at = active_since_interaction + _reconnect_seconds()
		if options.proactive_reconnect and candidate.is_empty():
			candidate = {"reason":"reconnect", "context":{"minutes_without_interaction":int(active_since_interaction / 60.0)}}
	var explicitly_snoozed := false
	if not _snooze.is_empty() and _now >= float(_snooze.at):
		# A requested reminder expires too, instead of appearing after a long absence.
		if _now - float(_snooze.at) <= GAME_TTL and _reason_enabled(str(_snooze.reason)):
			candidate = {"reason":str(_snooze.reason), "context":_snooze.context.duplicate(true)}
			explicitly_snoozed = true
		_snooze.clear()
	if candidate.is_empty(): return {}
	if str(candidate.reason) == "game":
		# Give a short landing/release animation a chance to settle. Fullscreen,
		# an open conversation, quiet hours and cooldown still discard the event.
		if not bool(snapshot.get("allowed", false)) and not quiet and _now >= _warmup_until \
			and not bool(snapshot.get("fullscreen", true)) and not bool(snapshot.get("dialog_open", true)):
			return {}
		_pending_game.clear()
	# Due events are consumed even when the moment is unsuitable. Nothing piles up.
	var daily_limit := int(options.proactive_daily_limit)
	if quiet or _day == _quiet_today or (daily_limit > 0 and _daily_count >= daily_limit): return {}
	if _now < _warmup_until or bool(snapshot.get("fullscreen", true)) or bool(snapshot.get("dialog_open", true)) or not bool(snapshot.get("allowed", false)): return {}
	if not explicitly_snoozed:
		var multiplier := 1 + mini(2, _ignore_streak / 2)
		var cooldown := float(options.proactive_interval_minutes) * 60.0 * multiplier
		if _last_offer > 0.0 and _now - _last_offer < cooldown: return {}
		if str(candidate.reason) != "game" and _now < _interaction_until: return {}
	_last_offer = _now; _daily_count = mini(1000000000, _daily_count + 1)
	_pending_game.clear()
	_last_offer_details = candidate.duplicate(true)
	_awaiting_feedback = true
	return candidate

func note_pet_interaction() -> void:
	active_since_interaction = 0.0
	_next_reconnect_at = _reconnect_seconds()
	_interaction_until = _now + INTERACTION_GRACE

func note_game_finished(game: String, score: int) -> void:
	if not options.proactive or not options.proactive_games or game not in ["catch", "juggle"]: return
	var roll: Variant = random_source.call() if random_source.is_valid() else rng.randf()
	if not _number(roll) or float(roll) < 0.0 or float(roll) >= 0.25: return
	_pending_game = {"at":_now, "context":{"game":game, "score":clampi(score, 0, 1000000000)}}

func feedback(action: String) -> void:
	if action == "quiet_today":
		_quiet_today = _day; _snooze.clear(); _pending_game.clear(); _awaiting_feedback = false
		return
	if action in ["replied", "accepted"]:
		_ignore_streak = 0; _snooze.clear(); note_pet_interaction()
		_awaiting_feedback = false
		return
	if not _awaiting_feedback: return
	_awaiting_feedback = false
	if action == "snooze" and not _last_offer_details.is_empty():
		_snooze = _last_offer_details.duplicate(true)
		_snooze.at = _now + SNOOZE_SECONDS
	elif action == "ignored":
		_ignore_streak = mini(4, _ignore_streak + 1)
	# "unavailable" consumes a failed/not-shown attempt without treating it as rejection.

func dump_state() -> Dictionary:
	return {"schema":1, "day":_day, "daily_count":_daily_count, "quiet_today":_quiet_today,
		"ignore_streak":_ignore_streak, "last_offer":_last_offer, "snooze":_snooze.duplicate(true)}

func load_state(data: Dictionary) -> void:
	if data.get("schema") != 1: return
	_day = _clean_day(data.get("day"))
	_quiet_today = _clean_day(data.get("quiet_today"))
	# Retain the actual count in unlimited mode, including when a finite cap is
	# restored later the same day. A restart must not reset those invitations.
	_daily_count = clampi(int(data.daily_count), 0, 1000000000) if _number(data.get("daily_count")) else 0
	_ignore_streak = clampi(int(data.ignore_streak), 0, 4) if _number(data.get("ignore_streak")) else 0
	_last_offer = maxf(0.0, float(data.last_offer)) if _number(data.get("last_offer")) else 0.0
	_snooze.clear()
	var saved: Variant = data.get("snooze", {})
	if saved is Dictionary and saved.get("reason") in ["rest", "game", "reconnect"] and _number(saved.get("at")) and saved.get("context") is Dictionary:
		var reason: String = saved.reason
		var context := {}
		if reason == "game" and saved.context.get("game") in ["catch", "juggle"] and _number(saved.context.get("score")):
			context = {"game":saved.context.game, "score":clampi(int(saved.context.score), 0, 1000000000)}
		elif reason == "rest" and _number(saved.context.get("continuous_minutes")):
			context = {"continuous_minutes":clampi(int(saved.context.continuous_minutes), 0, 1440)}
		elif reason == "reconnect" and _number(saved.context.get("minutes_without_interaction")):
			context = {"minutes_without_interaction":clampi(int(saved.context.minutes_without_interaction), 0, 1440)}
		if not context.is_empty(): _snooze = {"reason":reason, "at":maxf(0.0, float(saved.at)), "context":context}
	_started = false; _pending_game.clear(); _awaiting_feedback = false; _reset_activity()

func _reset_activity() -> void:
	active_seconds = 0.0; active_since_interaction = 0.0
	_next_rest_at = REST_SECONDS; _next_reconnect_at = _reconnect_seconds()

func _reconnect_seconds() -> float:
	return float(options.proactive_interval_minutes) * 60.0

func _reason_enabled(reason: String) -> bool:
	return bool(options.get("proactive_" + {"rest":"rest", "game":"games", "reconnect":"reconnect"}.get(reason, ""), false))

func _quiet(hour: int) -> bool:
	if not bool(options.quiet_enabled): return false
	var start := int(options.quiet_start)
	var end := int(options.quiet_end)
	if start == end: return false
	return (hour >= start or hour < end) if start > end else (hour >= start and hour < end)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _clean_day(value: Variant) -> String:
	if not value is String or value.length() != 10: return ""
	if value[4] != "-" or value[7] != "-": return ""
	return value if (value.left(4) + value.substr(5,2) + value.right(2)).is_valid_int() else ""

static func _valid_snapshot(snapshot: Dictionary) -> bool:
	return _number(snapshot.get("now_unix")) and float(snapshot.now_unix) > 0.0 \
		and _number(snapshot.get("idle_seconds")) and float(snapshot.idle_seconds) >= 0.0 \
		and not _clean_day(snapshot.get("local_day")).is_empty() \
		and _number(snapshot.get("local_hour")) and int(snapshot.local_hour) >= 0 and int(snapshot.local_hour) <= 23
