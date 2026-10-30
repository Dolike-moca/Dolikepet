extends SceneTree
const Speech = preload("res://scripts/ai_speech.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func _initialize() -> void:
	var speech = Speech.new()
	speech.append("谢谢你，今天也")
	check(speech.advance(0.05, true).text.is_empty(), "partial sentence waits")
	speech.append("很高兴见到你。还有一句话")
	speech.finish()
	var pose := {"mouth":0.0,"eyeNear":1.0,"eyeFar":1.0,"bodyX":0.1}
	var before := pose.duplicate()
	var spoke := false
	var smiled := false
	for frame in 55:
		speech.advance(1.0/60.0, true)
		pose = before.duplicate(); speech.apply(pose, true)
		spoke = spoke or pose.mouth > 0.1
		smiled = smiled or pose.eyeNear < 0.5
	check(spoke and smiled, "happy reply has syllables and a brief smile")
	check(pose.bodyX == before.bodyX, "reply does not change body or locomotion")
	var remaining: float = speech.remaining
	check(speech.advance(0.1, false).text.is_empty(), "busy interaction hides AI bubble")
	pose = before.duplicate(); speech.apply(pose, false)
	check(pose == before and speech.remaining == remaining, "physical pose takes priority; reading pauses")
	check(not speech.advance(0.01, true).text.is_empty(), "idle resumes interrupted reply")
	for frame in 700: speech.advance(1.0/60.0, true)
	pose = before.duplicate(); speech.apply(pose, true)
	check(speech.current.is_empty() and pose == before, "returns to original expression")
	speech.clear(); speech.append("喵".repeat(10000)); speech.finish()
	check(speech.segments == Speech.MAX_BUBBLES and speech.pending.is_empty(), "head bubble is bounded independently of full history")
	for frame in 140: speech.advance(0.25, true)
	check(not speech.current.is_empty() and not speech.queue.is_empty(), "visible long reply keeps speaking beyond thirty seconds")
	for frame in 130: speech.advance(0.25, false)
	check(speech.queue.is_empty() and speech.current.is_empty(), "stale replies expire during a long game")
	speech.clear(); speech.append("新的回答。"); speech.advance(0.1, true); speech.clear()
	check(speech.current.is_empty() and speech.mouth == 0.0, "cancel immediately releases presentation")
	for failure in failures: printerr("AI SPEECH: " + failure)
	print("AI speech: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
