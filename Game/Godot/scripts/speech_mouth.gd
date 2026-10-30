extends RefCounted
## Text presentation only: never owns an action, timer lock or mouse capture.
const Behavior = preload("res://scripts/pet_behavior.gd")
const SpeechSpeed = preload("res://scripts/speech_speed.gd")
var remaining := 0.0
var elapsed := 0.0
var mouth := 0.0
var weight := 0.0

func clear() -> void:
	remaining = 0.0; elapsed = 0.0; mouth = 0.0; weight = 0.0

func say(text: String, seconds: float) -> void:
	elapsed = 0.0
	# Persistent status text must not make the cat talk forever.
	remaining = minf(maxf(seconds, 0.0), minf(SpeechSpeed.spoken_seconds(text), 12.0)) \
		if not text.strip_edges().is_empty() and is_finite(seconds) else 0.0

func advance(dt: float, local_visible: bool, ai_active: bool, ai_mouth: float, pose: Dictionary, speed_factor: float = 1.0) -> void:
	dt = clampf(dt, 0.0, 0.25) if is_finite(dt) else 0.0
	var spoken_dt := dt * SpeechSpeed.safe_factor(speed_factor)
	if not local_visible: remaining = 0.0
	remaining = maxf(0.0, remaining - spoken_dt)
	elapsed += spoken_dt
	var local_active := local_visible and remaining > 0.0
	var active := local_active or ai_active
	var target := Behavior.speaking_openness(elapsed) * 0.78 if local_active and remaining > 0.2 else 0.0
	if not local_active and ai_active: target = ai_mouth
	mouth = lerpf(mouth, target, 1.0 - exp(-22.0 * spoken_dt))
	weight = lerpf(weight, 1.0 if active else 0.0, 1.0 - exp(-18.0 * dt))
	if weight < 0.001: weight = 0.0
	if weight > 0.0:
		pose.speechWeight = weight
		pose.speechMouth = mouth
