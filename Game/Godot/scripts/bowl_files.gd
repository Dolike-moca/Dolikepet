extends Node
## One asynchronous worker at a time. The meal sees stable snapshots only.
signal changed
signal message(text: String)
const Food = preload("res://scripts/food_item.gd")
const Paths = preload("res://scripts/project_paths.gd")
var folder := ""
var cache := ""
var helper := ""
var total_bytes := 0
var stomach_folder := ""
var stomach_bytes := 0
var stomach_capacity := 1073741824
var digestion_hours := 6.0
var storage_ready := false
var entries: Array = []
var initialized := false
var jobs: Array[Dictionary] = []
var running := {}
var pid := -1
var elapsed := 0.0
var poll := 0.0
var next_scan := 0.0
var sequence := 0
var stable := {}
var pending := {}
var failed := {}
var textures := {}

static func game_root() -> String:
	return Paths.game_root()

func start(root_override := "", cache_override := "") -> void:
	folder = root_override if not root_override.is_empty() else game_root().path_join("猫的饭盆")
	stomach_folder = folder.get_base_dir().path_join("猫的胃袋")
	cache = cache_override if not cache_override.is_empty() else ProjectSettings.globalize_path("user://bowl-cache")
	DirAccess.make_dir_recursive_absolute(cache)
	# A versioned helper can be replaced by a new build without locking the old process.
	var bytes := FileAccess.get_file_as_bytes("res://native/BowlFiles.exe")
	helper = cache.path_join("BowlFiles-"+str(hash(bytes))+".exe")
	if not FileAccess.file_exists(helper):
		var file := FileAccess.open(helper,FileAccess.WRITE)
		if file == null: message.emit("饭盆缓存无法写入"); return
		file.store_buffer(bytes)
	var art := cache.path_join("cauldron.png")
	if not FileAccess.file_exists(art): preload("res://assets/bowl/cauldron.png").get_image().save_png(art)
	jobs.append({"action":"ensure","art":art})

func import_files(paths: PackedStringArray) -> void:
	if paths.is_empty(): return
	jobs.append({"action":"import","paths":Array(paths)})
	message.emit("正在把文件放进饭盆喵～")

func consume(item) -> void:
	if item == null or item.source.is_empty(): return
	var source: Dictionary = item.source
	if pending.has(source.token): return
	pending[source.token] = int(source.get("bytes",0))
	jobs.append({"action":"swallow","path":source.path,"token":source.token})

func reserved_bytes() -> int:
	var count := 0
	for value in pending.values(): count += int(value)
	return count

func available(item) -> bool:
	if item.source.is_empty(): return true
	var source: Dictionary = item.source
	if pending.has(source.token) or failed.has(source.token) or not FileAccess.file_exists(source.path): return false
	for entry in entries:
		if entry.path == source.path and entry.token == source.token: return true
	return false

func food_items(excluded: Array = []) -> Array:
	var result := []
	if not storage_ready: return result
	var room := maxi(0,stomach_capacity-stomach_bytes-reserved_bytes())
	for entry in entries:
		if entry.token in excluded and not pending.has(entry.token): room -= int(entry.get("bytes",0))
	for entry in entries:
		if result.size() >= 8: break
		if pending.has(entry.token) or entry.token in excluded: continue
		# A busy/unstable/oversized older file blocks later files too.
		if not entry.get("ready",true) or not stable.has(entry.token) or failed.has(entry.token): break
		var bytes := int(entry.get("bytes",0))
		if bytes>room: break
		room -= bytes
		if not textures.has(entry.token):
			var image := Image.new()
			var texture: Texture2D = Food.DEMO_TEXTURES[0]
			if image.load(entry.icon) == OK: texture = ImageTexture.create_from_image(image)
			textures[entry.token] = texture
		var food = Food.from_texture(textures[entry.token],entry.label)
		food.source = entry.duplicate()
		result.append(food)
	return result

func _process(dt: float) -> void:
	if helper.is_empty(): return
	next_scan -= dt
	if pid >= 0:
		elapsed += dt; poll += dt
		if poll < 0.12: return
		poll = 0.0
		if FileAccess.file_exists(running.reply):
			var response = JSON.parse_string(FileAccess.get_file_as_string(running.reply))
			DirAccess.remove_absolute(running.request); DirAccess.remove_absolute(running.reply)
			_finish(response if response is Dictionary else {"ok":false,"error":"饭盆响应无效"})
			pid = -1; running = {}
		elif not OS.is_process_running(pid):
			_finish({"ok":false,"error":"饭盆文件助手未完成操作，文件将保留"})
			pid = -1; running = {}
		return
	if jobs.is_empty() and initialized and next_scan <= 0.0:
		jobs.append({"action":"scan"}); next_scan = 1.6
	if jobs.is_empty(): return
	running = jobs.pop_front()
	sequence += 1
	var key := "%d-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec(),sequence]
	running.request = cache.path_join(key+".request.json")
	running.reply = cache.path_join(key+".reply.json")
	var data := running.duplicate()
	data.root = folder; data.cache = cache
	data.stomach_capacity = stomach_capacity; data.digestion_hours = digestion_hours
	var file := FileAccess.open(running.request,FileAccess.WRITE)
	if file == null: message.emit("饭盆任务无法写入"); running = {}; return
	file.store_string(JSON.stringify(data)); file.close()
	pid = OS.create_process(helper,PackedStringArray([running.request,running.reply]),false)
	elapsed = 0.0
	if pid < 0: message.emit("无法启动饭盆文件助手"); running = {}

func _finish(result: Dictionary) -> void:
	var action: String = running.action
	if not result.get("ok",false):
		if action == "swallow": failed[running.token] = Time.get_ticks_msec()+30000; pending.erase(running.token); next_scan = 0.0
		if action == "scan": storage_ready = false
		message.emit(str(result.get("error","文件操作未完成")))
		return
	match action:
		"ensure": initialized = true; next_scan = 0.0
		"scan":
			storage_ready = true
			stomach_bytes = int(result.get("stomach_bytes",0))
			var previous := {}
			for entry in entries: previous[entry.token] = true
			entries = result.entries
			stable.clear()
			var present := {}
			for entry in entries:
				present[entry.token] = true
				if previous.has(entry.token) and not str(entry.token).is_empty() and entry.get("ready",true): stable[entry.token] = true
			for token in pending.keys():
				if not present.has(token): pending.erase(token)
			for token in textures.keys():
				if not present.has(token): textures.erase(token)
			for token in failed.keys():
				if not present.has(token) or Time.get_ticks_msec()>=failed[token]: failed.erase(token)
			total_bytes = int(result.bytes)
			changed.emit()
		"import":
			next_scan = 0.0
			var count: int = result.accepted.size()
			message.emit("收到 %d 份食物喵～"%count if result.errors.is_empty() else "已放入 %d 份，%s"%[count,str(result.errors[0])])
		"swallow":
			stomach_bytes = int(result.stomach_bytes)
			pending.erase(running.token)
			entries = entries.filter(func(entry): return entry.token!=running.token)
			stable.erase(running.token); textures.erase(running.token)
			next_scan = 0.0
			changed.emit()

func open_folder() -> void:
	if initialized: OS.shell_open(folder)

func open_stomach() -> void:
	if initialized: OS.shell_open(stomach_folder)
