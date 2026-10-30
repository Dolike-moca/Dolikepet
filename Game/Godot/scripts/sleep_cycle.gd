extends RefCounted
## Local sleep schedule and animation clock. No files, system input or AI calls.

const DROWSY_SECONDS := 2.0
const SETTLING_SECONDS := 3.0
const WAKE_SECONDS := 2.0
const WAKE_COOLDOWN := 120.0
const DAY_IDLE_SECONDS := 180.0
const NIGHT_IDLE_SECONDS := 30.0
const DAY_CHECK_SECONDS := 60.0
const NIGHT_CHECK_SECONDS := 30.0
const DAY_CHANCES := [0.1, 0.2, 0.4]
const NIGHT_CHANCE := 0.6
const NAP_MIN_SECONDS := 180.0
const NAP_MAX_SECONDS := 480.0
const DEFAULT_START := 23 * 60
const DEFAULT_END := 8 * 60

var enabled := true
var start_minute := DEFAULT_START
var end_minute := DEFAULT_END
var frequency := 1
var state := "awake"
var age := 0.0
var idle_seconds := 0.0
var asleep_seconds := 0.0
var nap_seconds := 0.0
var cooldown := 0.0
var phase := 0.0
var checks := 0
var rng := RandomNumberGenerator.new()
var random_source: Callable
var _minute := 12 * 60
var _scheduled := false
var _manual := false
var _next_check := DAY_IDLE_SECONDS
var _wake_weight := 0.0
var _wake_eye := 1.0
var _events := {"started":false,"sit":false,"waking":false,"finished":false}

func _init() -> void:
	rng.randomize()

static func _integer(value: Variant, fallback: int, low: int, high: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)): return fallback
	return clampi(int(value),low,high)

static func sanitized(value: Dictionary) -> Dictionary:
	var enable: Variant = value.get("enabled",true)
	return {"enabled":enable if enable is bool else true,
		"start_minute":_integer(value.get("start_minute",DEFAULT_START),DEFAULT_START,0,1439),
		"end_minute":_integer(value.get("end_minute",DEFAULT_END),DEFAULT_END,0,1439),
		"frequency":_integer(value.get("frequency",1),1,0,2)}

func settings() -> Dictionary:
	return {"enabled":enabled,"start_minute":start_minute,"end_minute":end_minute,"frequency":frequency}

func configure(value: Dictionary) -> void:
	var clean := sanitized(value)
	if clean == settings(): return
	enabled = clean.enabled; start_minute = clean.start_minute
	end_minute = clean.end_minute; frequency = clean.frequency
	var scheduled := in_schedule(_minute)
	if _scheduled and not scheduled and active(): _begin_wake()
	_scheduled = scheduled
	if not enabled and active() and not _manual: _begin_wake()
	# Saving a changed frequency/time starts a fresh opportunity rather than
	# immediately spending a probability check accumulated under old settings.
	idle_seconds = 0.0
	_next_check = _idle_limit()

func in_schedule(minute: int) -> bool:
	if minute < 0 or minute >= 1440: return false
	if start_minute == end_minute: return true
	if start_minute < end_minute: return minute >= start_minute and minute < end_minute
	return minute >= start_minute or minute < end_minute

func active() -> bool:
	return state != "awake"

func request_sleep() -> bool:
	if active(): return false
	_begin_sleep(true)
	return true

func _begin_sleep(manual: bool) -> void:
	state = "drowsy"; age = 0.0; phase = 0.0; asleep_seconds = 0.0
	_manual = manual
	nap_seconds = rng.randf_range(NAP_MIN_SECONDS,NAP_MAX_SECONDS)
	_events.started = true

func _begin_wake() -> void:
	if state in ["awake","waking"]: return
	var current := pose()
	_wake_weight = float(current.sleepWeight); _wake_eye = float(current.sleepEye)
	state = "waking"; age = 0.0
	_events.started = false; _events.sit = false
	_events.waking = true

func interact(immediate: bool = false) -> void:
	idle_seconds = 0.0; _next_check = _idle_limit(); cooldown = WAKE_COOLDOWN
	if immediate and active():
		state = "awake"; age = 0.0; phase = 0.0; asleep_seconds = 0.0
		_events = {"started":false,"sit":false,"waking":false,"finished":true}
		_manual = false
	else:
		_begin_wake()

func _idle_limit() -> float:
	return NIGHT_IDLE_SECONDS if _scheduled else DAY_IDLE_SECONDS

func _check_interval() -> float:
	return NIGHT_CHECK_SECONDS if _scheduled else DAY_CHECK_SECONDS

func _chance() -> float:
	return NIGHT_CHANCE if _scheduled else DAY_CHANCES[frequency]

func _roll() -> float:
	var value: Variant = random_source.call() if random_source.is_valid() else rng.randf()
	return clampf(float(value),0.0,1.0) if (value is int or value is float) and is_finite(float(value)) else 1.0

func _drain_events() -> Dictionary:
	var result := _events.duplicate()
	for key in _events: _events[key] = false
	return result

func advance(dt: float, context: Dictionary) -> Dictionary:
	var minute: Variant = context.get("minute",_minute)
	if (minute is int or minute is float) and is_finite(float(minute)) and float(minute)>=0.0 and float(minute)<1440.0:
		_minute = int(minute)
	var scheduled := in_schedule(_minute)
	if scheduled != _scheduled:
		if _scheduled and not scheduled and active(): _begin_wake()
		_scheduled = scheduled
		_next_check = _idle_limit()
	# OS sleep/resume or a stalled frame must not replay hours of missed dice.
	if not is_finite(dt) or dt <= 0.0 or dt > 1.0: return _drain_events()
	var blocked := bool(context.get("blocked",false))
	var settled := bool(context.get("settled",true))
	cooldown = maxf(0.0,cooldown-dt)
	if cooldown < 0.000001: cooldown = 0.0
	if blocked and active(): _begin_wake()
	if state == "awake":
		idle_seconds += dt
		if enabled and not blocked and settled and cooldown<=0.0 and idle_seconds+0.000001>=_next_check:
			_next_check = idle_seconds+_check_interval()
			checks += 1
			if _roll() < _chance(): _begin_sleep(false)
		return _drain_events()
	phase += dt
	age += dt
	if state == "drowsy" and age+0.000001>=DROWSY_SECONDS:
		state = "settling"; age = maxf(0.0,age-DROWSY_SECONDS); _events.sit = true
	elif state == "settling" and age+0.000001>=SETTLING_SECONDS and settled:
		state = "asleep"; age = 0.0; asleep_seconds = 0.0
	elif state == "asleep":
		asleep_seconds += dt
		if not _scheduled and asleep_seconds+0.000001>=nap_seconds: _begin_wake()
	elif state == "waking" and age+0.000001>=WAKE_SECONDS:
		state = "awake"; age = 0.0; phase = 0.0; asleep_seconds = 0.0; _manual = false
		idle_seconds = 0.0; _next_check = _idle_limit()
		cooldown = maxf(cooldown,WAKE_COOLDOWN)
		_events.finished = true
	return _drain_events()

func pose() -> Dictionary:
	var weight := 0.0
	var eye := 1.0
	var stretch := 0.0
	match state:
		"drowsy":
			var progress := smoothstep(0.0,DROWSY_SECONDS,age)
			weight = 0.4*progress
			var blink := sin(clampf((age-0.3)/1.1,0.0,1.0)*PI)
			eye = lerpf(1.0,0.45,progress)*(1.0-0.85*blink*blink)
		"settling":
			weight = lerpf(0.4,1.0,smoothstep(0.0,SETTLING_SECONDS,age))
			eye = 0.45*(1.0-smoothstep(0.0,1.8,age))
		"asleep":
			weight = 1.0; eye = 0.0
		"waking":
			weight = _wake_weight*(1.0-smoothstep(0.0,WAKE_SECONDS,age))
			eye = lerpf(_wake_eye,1.0,smoothstep(0.15,1.45,age))
			stretch = sin(clampf((age-0.55)/1.3,0.0,1.0)*PI)
	return {"sleepWeight":clampf(weight,0.0,1.0),"sleepEye":clampf(eye,0.0,1.0),
		"sleepPhase":phase,"sleepWakeStretch":maxf(0.0,stretch)}
