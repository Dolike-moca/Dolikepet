extends RefCounted
## A disposable presentation layer. It never owns a pet behaviour or input lock.
const Behavior = preload("res://scripts/pet_behavior.gd")
const SpeechSpeed = preload("res://scripts/speech_speed.gd")
const MAX_SEGMENT := 34
const MAX_BUBBLES := 256
const EXPIRES_AFTER := 30.0
var pending := ""
var queue: Array[String] = []
var current := ""
var remaining := 0.0
var elapsed := 0.0
var age := 0.0
var mouth := 0.0
var smile := 0.0
var finished := false
var segments := 0
var completed_characters := 0

func clear() -> void:
	pending = ""; queue.clear(); current = ""
	remaining = 0.0; elapsed = 0.0; age = 0.0
	mouth = 0.0; smile = 0.0; finished = false; segments = 0
	completed_characters = 0

func append(text: String) -> void:
	if segments >= MAX_BUBBLES: return
	# Bounded to the visible chat's maximum length, including long replies.
	pending += text.replace("\r", "").replace("\n", " ")
	while not pending.is_empty() and segments < MAX_BUBBLES:
		var cut := -1
		for i in mini(MAX_SEGMENT, pending.length()):
			if pending[i] in ["。", "！", "？", "!", "?", "；", ";"]:
				cut = i + 1; break
		if cut < 0 and pending.length() >= MAX_SEGMENT: cut = MAX_SEGMENT
		if cut < 0: break
		_enqueue(pending.left(cut))
		pending = pending.substr(cut)
	if segments >= MAX_BUBBLES: pending = ""

func finish() -> void:
	if not pending.strip_edges().is_empty() and segments < MAX_BUBBLES: _enqueue(pending)
	pending = ""; finished = true

func _enqueue(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty(): return
	queue.append(text); segments += 1

func advance(dt: float, allowed: bool, speed_factor: float = 1.0) -> Dictionary:
	dt = clampf(dt, 0.0, 0.25) if is_finite(dt) else 0.0
	var spoken_dt := dt * SpeechSpeed.safe_factor(speed_factor)
	# Expire abandoned/hidden replies, never cut off a visible long sentence.
	age = 0.0 if allowed else age + dt
	if age > EXPIRES_AFTER: clear(); return {"text":"", "speaking":false}
	if not allowed:
		mouth = 0.0; smile = 0.0
		return {"text":"", "speaking":false}
	remaining = maxf(0.0, remaining - spoken_dt)
	if remaining <= 0.0:
		completed_characters += current.length()
		current = ""
		if not queue.is_empty():
			current = queue.pop_front()
			remaining = SpeechSpeed.spoken_seconds(current)
			elapsed = 0.0
	elapsed += spoken_dt
	var speaking := not current.is_empty() and remaining > 0.35
	var target := Behavior.speaking_openness(elapsed) * 0.78 if speaking else 0.0
	mouth = lerpf(mouth, target, 1.0 - exp(-22.0 * spoken_dt))
	var happy := false
	for word in ["谢谢", "好开心", "太好了", "真棒", "很高兴"]:
		if current.contains(word): happy = true
	var smile_target := 1.0 if happy and elapsed > 0.25 and elapsed < 0.75 else 0.0
	smile = lerpf(smile, smile_target, 1.0 - exp(-16.0 * dt))
	return {"text":current, "speaking":speaking}

func apply(pose: Dictionary, allowed: bool) -> void:
	if not allowed: return
	if mouth > 0.001: pose.mouth = maxf(float(pose.get("mouth", 0.0)), mouth)
	if smile > 0.001:
		pose.eyeNear = minf(float(pose.get("eyeNear", 1.0)), 1.0 - smile)
		pose.eyeFar = minf(float(pose.get("eyeFar", 1.0)), 1.0 - smile)
