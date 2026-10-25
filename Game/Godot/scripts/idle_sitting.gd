extends RefCounted
## Decides when to request the already accepted sitting animation.
## Automatic and manually requested sitting have different wake-up behavior.

const DEFAULT_MIN_SECONDS := 60.0
const DEFAULT_MAX_SECONDS := 180.0
const MIN_SECONDS := 5.0
const MAX_SECONDS := 3600.0

var enabled := true
var minimum_seconds := DEFAULT_MIN_SECONDS
var maximum_seconds := DEFAULT_MAX_SECONDS
var wait_seconds := 0.0
var elapsed := 0.0
var automatically_seated := false
var rng := RandomNumberGenerator.new()
var needs_new_wait := true

func _init() -> void:
	rng.randomize()

func configure(value: bool, minimum: float, maximum: float) -> void:
	enabled = value
	var low := clampf(minimum, MIN_SECONDS, MAX_SECONDS) if is_finite(minimum) else DEFAULT_MIN_SECONDS
	var high := clampf(maximum, MIN_SECONDS, MAX_SECONDS) if is_finite(maximum) else DEFAULT_MAX_SECONDS
	minimum_seconds = minf(low, high)
	maximum_seconds = maxf(low, high)
	_restart_clock()

func _restart_clock() -> void:
	elapsed = 0.0
	wait_seconds = 0.0
	needs_new_wait = true

func interact(wake: bool = true) -> bool:
	_restart_clock()
	if wake and automatically_seated:
		automatically_seated = false
		return true
	return false

func manual_pose() -> void:
	automatically_seated = false
	_restart_clock()

func advance(dt: float, busy: bool, already_seated: bool) -> bool:
	if not enabled or busy or already_seated:
		_restart_clock()
		return false
	if not is_finite(dt) or dt <= 0.0:
		return false
	# Draw once at the start of an idle period, never again on subsequent frames.
	if needs_new_wait:
		wait_seconds = rng.randf_range(minimum_seconds, maximum_seconds)
		needs_new_wait = false
	elapsed += dt
	if elapsed >= wait_seconds:
		_restart_clock()
		automatically_seated = true
		return true
	return false
