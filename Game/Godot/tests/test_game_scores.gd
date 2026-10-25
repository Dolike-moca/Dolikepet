extends SceneTree
const Scores = preload("res://scripts/game_scores.gd")
const Visibility = preload("res://scripts/score_visibility.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("GAME SCORES: "+words)
func event(game: String, at: float, n: int, points: int, total: int, bonus := 0) -> Dictionary:
	return {"game":game,"at":at,"streak":n,"base":points,"bonus":bonus,"walls":2,"multiplier":7 if game=="juggle" else 1,"delta":points+bonus,"total":total}
func run() -> void:
	var path := "res://../../_work/tests/scores-%d/ledger.json"%Time.get_ticks_usec()
	var store = Scores.new(); store.configure(path,75)
	check(store.statistics("catch").best==75 and store.statistics("catch").legacy,"legacy record lost")
	store.record_award(event("catch",10,1,4,4))
	store.record_award(event("catch",11,2,1,5))
	store.finish_round({"at":15,"reason":"落地"})
	check(store.rounds.size()==1 and store.rounds[0].duration==5.0,"round duration/count")
	check(store.rounds[0].events[1].base==1 and store.rounds[0].total==5,"per-throw awards changed")
	store.finish_round({"at":20,"reason":"重复结束"})
	check(store.rounds.size()==1,"duplicate end added a round")
	store.record_award(event("juggle",30,1,28,28))
	store.record_award(event("juggle",31,20,7,55,20))
	store.finish_round({"at":32,"reason":"锅落地"})
	check(store.statistics("juggle").best==55 and store.statistics("catch").best==75,"game records mixed")
	check(store.query("juggle")[0].events[1].bonus==20,"bonus multiplied/merged")
	check(store.query("","score")[0].total==55,"score sorting")
	check(store.query("","streak")[0].streak==20,"streak sorting")
	var reloaded = Scores.new(); reloaded.configure(path)
	check(reloaded.rounds.size()==2 and reloaded.current.is_empty(),"restart lost or replayed finished round")
	check(reloaded.statistics("juggle").plays==1 and reloaded.statistics("juggle").average==55,"aggregate averages")
	reloaded.record_award(event("catch",40,1,9,9))
	reloaded.record_award(event("catch",43,2,1,10))
	var recovered = Scores.new(); recovered.configure(path)
	check(recovered.rounds.size()==3 and recovered.rounds[-1].duration==3,"interrupted round lost")
	var again = Scores.new(); again.configure(path)
	check(again.rounds.size()==3,"interrupted checkpoint replayed twice")
	check(again.statistics("catch").plays==2 and again.statistics("catch").average==7.5,"historical best counted as fictitious round")
	var life = Visibility.new()
	var data := {"panel_available":true,"revision":1,"game":"juggle","active":true,"ended_at":-1.0}
	check(life.update(data,100,false)==1.0 and life.update(data,1000,false)==1.0,"airborne juggle timed out")
	data.active = false; data.revision = 2; data.ended_at = 1000.0
	check(life.update(data,1004,false)>0.0 and life.update(data,1005,false)==0.0,"juggle end not five seconds")
	check(life.update(data,1006,true)==0.0,"expired juggle revived on hover")
	var corrupt := FileAccess.open(ProjectSettings.globalize_path(path),FileAccess.WRITE); corrupt.store_string("{"); corrupt.close()
	var backup = Scores.new(); backup.configure(path)
	check(backup.rounds.size()>=2,"backup recovery failed")
	print("GAME SCORES: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
