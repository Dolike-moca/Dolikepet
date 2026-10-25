extends RefCounted
signal awarded(event: Dictionary)
signal round_finished(result: Dictionary)
## Observes native contacts; never changes the pet's movement or animation.
const THROW_SECONDS := 3.0
var phase := "idle"
var streak := 0
var total := 0
var best := 0
var shown := false
var revision := 0
var delta := 0
var base_points := 0
var bonus := 0
var bounce_count := 0
var scored_bounces := 0
var deadline := 0.0
var wall_start := 0
var floor_start := 0
var bounced := false
var message := "撞边后接住，自动开始"
var fade_started_at := -1.0
var fade_duration := 2.0
var fade_from := 1.0
var ended_at := -1.0
var last_total := 0
var last_streak := 0

func active() -> bool:
	return streak > 0

func advance(now: float, walls: int, floors: int) -> void:
	if phase == "caught" and now >= deadline:
		finish("超过 3 秒 · 本轮结束",deadline)
	elif phase == "flight":
		# Floor wins even if a wall and a catch arrive in the same display frame.
		if floors != floor_start:
			finish("没接住 · 本轮结束",now)
		else:
			bounce_count = maxi(bounce_count,walls-wall_start)
			bounced = bounce_count > 0

func released(now: float, walls: int, floors: int, speed: float, extent: float) -> void:
	advance(now,walls,floors)
	if speed < maxf(1.0,extent)*0.12:
		finish("未抛出 · 本轮结束",now)
		return
	phase = "flight"
	wall_start = walls; floor_start = floors; bounced = false; bounce_count = 0; deadline = 0.0
	# A valid rethrow cancels the pending fade only while this round is alive.
	# Throwing after a timeout must not reopen the panel until another catch.
	if active(): fade_started_at = -1.0
	message = "撞边后接住！"

func caught(now: float, walls: int, floors: int, grounded: bool, airborne: bool) -> bool:
	advance(now,walls,floors)
	if phase != "flight": return false
	if grounded or not airborne or not bounced:
		finish("未撞边接住 · 本轮结束",now)
		return false
	streak += 1
	scored_bounces = bounce_count
	base_points = scored_bounces*scored_bounces
	bonus = streak if streak % 10 == 0 else 0
	delta = base_points+bonus
	total += delta
	best = maxi(best,total)
	shown = true; revision += 1; phase = "caught"
	deadline = now+THROW_SECONDS
	fade_started_at = -1.0; ended_at = -1.0
	message = "3 秒内再次抛出"
	awarded.emit({"game":"catch","at":now,"streak":streak,"base":base_points,"bonus":bonus,
		"walls":scored_bounces,"multiplier":1,"delta":delta,"total":total})
	return true

func finish(reason: String, now := -1.0) -> void:
	if now<0.0: now = Time.get_ticks_msec()/1000.0
	if active():
		revision += 1; message = reason
		last_total = total; last_streak = streak; ended_at = now
		fade_from = 1.0; fade_started_at = now+3.0; fade_duration = 2.0
		round_finished.emit({"game":"catch","at":now,"total":total,"streak":streak,"reason":reason})
	phase = "idle"; streak = 0; total = 0; delta = 0; bonus = 0; base_points = 0
	deadline = 0.0; bounced = false; bounce_count = 0; scored_bounces = 0

func opacity(now: float) -> float:
	if not shown: return 0.0
	if fade_started_at<0.0: return 1.0
	return fade_from*(1.0-smoothstep(fade_started_at,fade_started_at+fade_duration,now))

func snapshot(now: float) -> Dictionary:
	var alpha := opacity(now)
	return {"shown":shown and alpha>0.0,"panel_available":shown,"opacity":alpha,"now":now,"ended_at":ended_at,
		"game":"catch","active":active(),"phase":phase,"streak":streak if active() else last_streak,
		"total":total if active() else last_total,"best":best,"delta":delta,"bonus":bonus,"revision":revision,
		"base_points":base_points,"scored_bounces":scored_bounces,"bounce_count":bounce_count,
		"remaining":maxf(0.0,deadline-now) if phase=="caught" else 0.0,"message":message}
