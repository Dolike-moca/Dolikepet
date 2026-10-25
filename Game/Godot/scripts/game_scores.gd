extends RefCounted
## Both games share a versioned local ledger. An active checkpoint is small;
## completed history is rewritten only at round end, never on every frame.
signal changed
const NAMES := {"catch":"猫猫抛接","juggle":"猫猫颠锅"}
var path := ""
var rounds: Array = []
var current: Dictionary = {}
var legacy_best := {"catch":0,"juggle":0}
var last_error := ""
var start_tick := 0.0

func configure(file_path: String, old_best := 0) -> void:
	path = ProjectSettings.globalize_path(file_path)
	var saved := _read(path)
	rounds = saved.get("rounds",[]) if saved.get("rounds",[]) is Array else []
	rounds = rounds.filter(_valid_round)
	var legacy = saved.get("legacy",{})
	for game in NAMES:
		legacy_best[game] = maxi(0,int(legacy.get(game,0))) if legacy is Dictionary else 0
	legacy_best.catch = maxi(legacy_best.catch,old_best)
	current = _read(path+".active").get("current",{})
	if not _valid_round(current): current = {}
	if not current.is_empty():
		current.reason = "上次退出时未结束"
		current.ended = current.started+int(current.duration)
		_commit()
	elif old_best>0: _save_history()

func _valid_round(value) -> bool:
	if not value is Dictionary or not NAMES.has(value.get("game","")) or not value.get("events") is Array: return false
	if not value.get("id") is String: return false
	for key in ["started","ended","duration","total","streak"]:
		if not (value.get(key) is float or value.get(key) is int): return false
		if not is_finite(float(value[key])) or float(value[key])<0.0: return false
	for event in value.events:
		if not event is Dictionary: return false
		for key in ["elapsed","base","bonus","delta","total","streak","walls","multiplier"]:
			if not (event.get(key) is float or event.get(key) is int): return false
	return true

func record_award(event: Dictionary) -> void:
	if not NAMES.has(event.get("game","")) or int(event.get("delta",0))<=0: return
	var now := float(event.at)
	if not current.is_empty() and current.game!=event.game:
		finish_round({"at":now,"reason":"切换游戏"})
	if current.is_empty():
		start_tick = now
		var unix := int(Time.get_unix_time_from_system())
		current = {"id":"%d-%d-%d"%[unix,Time.get_ticks_usec(),OS.get_process_id()],"game":event.game,
			"started":unix,"ended":0,"duration":0.0,"total":0,"streak":0,"events":[],"reason":""}
	var entry := event.duplicate(true)
	entry.erase("at"); entry.elapsed = maxf(0.0,now-start_tick)
	current.events.append(entry)
	current.total = int(event.total); current.streak = int(event.streak); current.duration = entry.elapsed
	_write(path+".active",{"schema":1,"current":current})
	changed.emit()

func finish_round(result: Dictionary) -> void:
	if current.is_empty(): return
	current.duration = maxf(float(current.duration),float(result.get("at",start_tick))-start_tick)
	current.ended = int(Time.get_unix_time_from_system())
	current.reason = str(result.get("reason","本轮结束"))
	_commit()

func _commit() -> void:
	current.new_record = int(current.total)>int(statistics(current.game).best)
	var exists := false
	for item in rounds:
		if item.id==current.id: exists = true; break
	if not exists: rounds.append(current.duplicate(true))
	if _save_history():
		# An empty checkpoint prevents a stale .bak from replaying a finished game.
		_write(path+".active",{"schema":1,"current":{}})
	current = {}
	changed.emit()

func _save_history() -> bool:
	return _write(path,{"schema":1,"rounds":rounds,"legacy":legacy_best})

func _read(target: String) -> Dictionary:
	for candidate in [target,target+".bak"]:
		if not FileAccess.file_exists(candidate): continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(candidate))!=OK: continue
		var parsed = parser.data
		if parsed is Dictionary and int(parsed.get("schema",0))==1: return parsed
	return {}

func _write(target: String, value: Dictionary) -> bool:
	if path.is_empty(): return false
	var error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if error!=OK: return _failed(error)
	var file := FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file==null: return _failed(FileAccess.get_open_error())
	file.store_string(JSON.stringify(value)); file.flush()
	error = file.get_error(); file.close()
	if error!=OK: return _failed(error)
	if FileAccess.file_exists(target):
		error = DirAccess.copy_absolute(target,target+".bak")
		if error!=OK: return _failed(error)
	error = DirAccess.rename_absolute(target+".tmp",target)
	if error!=OK: return _failed(error)
	last_error = ""
	return true

func _failed(error: int) -> bool:
	last_error = "记录暂未保存："+error_string(error)
	return false

func query(game := "", order := "recent") -> Array:
	var result := rounds.filter(func(item): return game.is_empty() or item.game==game)
	result.sort_custom(func(a,b):
		if order=="score" and int(a.total)!=int(b.total): return int(a.total)>int(b.total)
		if order=="streak" and int(a.streak)!=int(b.streak): return int(a.streak)>int(b.streak)
		return int(a.ended)>int(b.ended) if int(a.ended)!=int(b.ended) else str(a.id)>str(b.id))
	return result

func statistics(game: String) -> Dictionary:
	var items := query(game,"score")
	var total := 0; var seconds := 0.0; var streak := 0
	for item in items:
		total += int(item.total); seconds += float(item.duration); streak = maxi(streak,int(item.streak))
	var recorded_best := int(items[0].total) if not items.is_empty() else 0
	return {"plays":items.size(),"average":float(total)/maxi(1,items.size()),"seconds":seconds,"streak":streak,
		"best":maxi(int(legacy_best.get(game,0)),recorded_best),"legacy":int(legacy_best.get(game,0))>recorded_best,
		"top":items.slice(0,10)}
