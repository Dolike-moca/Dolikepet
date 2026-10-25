extends SceneTree
const Transition = preload("res://scripts/drag_eye_transition.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("EYE HANDOFF: " + message)
func _initialize() -> void:
	for fps in [30, 60, 120]:
		for target in [0.0, 1.0]:
			var eyes = Transition.new()
			var pose := {"eyeNear": target, "eyeFar": target, "dragHeld": true, "dragFace": 1.0}
			check(eyes.update(pose, 1.0 / fps).dragEyeOpenness == 0.0, "held lids not prepared")
			pose.dragHeld = false
			var closed_frames := 0
			var last := 0.0
			for frame in fps:
				pose.dragFace = maxf(0.0, 1.0 - (frame + 1.0) / fps / 0.1)
				var out: Dictionary = eyes.update(pose, 1.0 / fps)
				check(out.eyeNear == out.eyeFar, "eyes not synchronized")
				if pose.dragFace > 0.0: check(out.dragEyeOpenness == 0.0, "open eyes during squeezed-eye fade")
				elif out.dragEyeOpenness < 0.01: closed_frames += 1
				check(out.dragEyeOpenness >= last and out.dragEyeOpenness <= 1.0, "non-monotonic reopening")
				last = out.dragEyeOpenness
			check(closed_frames > 0 and not eyes.recovering, "missing closed pose / stuck closed")
			check(eyes.update(pose, 1.0 / fps).eyeNear == target, "user expression not restored")
	# Catching again during reopening must return to held, without a second reopen.
	var eyes = Transition.new()
	var pose := {"eyeNear": 1.0, "eyeFar": 1.0, "dragHeld": true, "dragFace": 1.0}
	eyes.update(pose, 1.0 / 60)
	pose.dragHeld = false
	pose.dragFace = 0.0
	eyes.update(pose, 0.08)
	pose.dragHeld = true
	check(eyes.update(pose, 1.0 / 60).eyeNear == 0.0 and not eyes.recovering, "regrab failed")
	print("EYE HANDOFF: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
