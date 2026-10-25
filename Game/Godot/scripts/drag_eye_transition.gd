extends RefCounted
## Release sequence: squeezed artwork -> closed Live2D lids -> reopen.
const CLOSED_HOLD := 0.03
const REOPEN_SECONDS := 0.10
var was_held := false
var recovering := false
var elapsed := 0.0

func update(pose: Dictionary, dt: float) -> Dictionary:
	var result := pose.duplicate()
	var held: bool = pose.get("dragHeld", false)
	if held:
		recovering = false
		elapsed = 0.0
	elif was_held:
		recovering = true
		elapsed = 0.0
	was_held = held
	var openness := 1.0
	if held:
		# Hidden behind the squeezed-eye sprites, ready for a closed-lid handoff.
		openness = 0.0
	elif recovering:
		if pose.get("dragFace", 0.0) > 0.00001:
			elapsed = 0.0
		else:
			elapsed += 0.0 if pose.get("fallPaused", false) else clampf(dt, 0.0, 0.1)
		openness = smoothstep(CLOSED_HOLD, CLOSED_HOLD + REOPEN_SECONDS, elapsed)
		if elapsed >= CLOSED_HOLD + REOPEN_SECONDS: recovering = false
	result.eyeNear *= openness
	result.eyeFar *= openness
	result.dragEyeOpenness = openness
	return result
