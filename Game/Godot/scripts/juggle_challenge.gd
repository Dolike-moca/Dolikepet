extends RefCounted
signal awarded(event: Dictionary)
signal round_finished(result: Dictionary)
var playing := false
var shown := false
var total := 0
var streak := 0
var best := 0
var revision := 0
var base_points := 0
var bonus := 0
var scored_bounces := 0
var boosted := false
var ended_at := -1.0
var message := "锅落地前，用猫头接住！"
var blessing_revision := 0
var blessing_at := -10.0

func active() -> bool: return playing

func hit(now: float, walls: int, high_speed: bool) -> void:
	if not playing: total = 0; streak = 0
	playing = true; shown = true; ended_at = -1.0
	streak += 1; revision += 1
	scored_bounces = maxi(0,walls); boosted = high_speed
	base_points = maxi(1,scored_bounces*scored_bounces)*(7 if boosted else 1)
	bonus = streak if streak%10==0 else 0
	total += base_points+bonus; best = maxi(best,total)
	if boosted: blessing_revision += 1; blessing_at = now
	# A later score has visual priority; no backlog of delayed blessings.
	else: blessing_at = -10.0
	message = "高速锅 ×7" if boosted else "锅落地前，用猫头接住！"
	awarded.emit({"game":"juggle","at":now,"streak":streak,"base":base_points,"bonus":bonus,
		"walls":scored_bounces,"multiplier":7 if boosted else 1,"delta":base_points+bonus,"total":total,
		"blessing":"慈父的赐福" if boosted else ""})

func finish(reason: String, now := -1.0) -> void:
	if not playing: return
	if now<0.0: now = Time.get_ticks_msec()/1000.0
	playing = false; ended_at = now; revision += 1; message = reason
	round_finished.emit({"game":"juggle","at":now,"total":total,"streak":streak,"reason":reason})

func snapshot(now: float) -> Dictionary:
	var alpha := 1.0 if playing else 1.0-smoothstep(ended_at+3.0,ended_at+5.0,now)
	return {"game":"juggle","active":playing,"shown":shown and alpha>0.0,"panel_available":shown,
		"now":now,"ended_at":ended_at,"opacity":alpha,"revision":revision,"phase":"flight" if playing else "idle",
		"streak":streak,"total":total,"best":best,"base_points":base_points,"bonus":bonus,
		"delta":base_points+bonus if playing else 0,"scored_bounces":scored_bounces,"bounce_count":0,
		"remaining":0.0,"message":message,"blessing_age":now-blessing_at,"boosted":boosted}
