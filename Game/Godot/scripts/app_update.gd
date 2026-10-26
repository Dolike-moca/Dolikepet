extends Node
## Downloads only: never installs, executes, extracts or touches player files.
signal changed
signal notice_requested(id: String, text: String)
const VERSION := "0.3.0"
const RELEASE_NAME := "色孽的赐福"
const REPOSITORY := "https://github.com/Dolike-moca/Dolikepet"
const FEED_URL := "https://raw.githubusercontent.com/Dolike-moca/Dolikepet/main/updates/latest.json"
const CHECK_INTERVAL := 21600.0
const RETRY_INTERVAL := 60.0
var state := "idle"
var message := "启动后自动检查更新，联网时下载；完成后猫咪会提醒你。"
var release_url := ""
var latest_version := ""
var package_path := ""
var verified_path := ""
var manifest: Dictionary = {}
var request := HTTPRequest.new()
var download := HTTPRequest.new()
var automatic := false
var auto_download := true
var next_check := 5.0
var cache_dir := "user://updates"
var feed_url := FEED_URL # Isolated tests may supply a loopback feed.
var downloaded_bytes := 0
var progress := 0.0
var _part_path := ""
var _verification := Thread.new()
var _verifying_cache := false
var _progress_age := 0.0
var _stalled_age := 0.0
var _failures := 0
var _announced: Dictionary = {}
var _queued: Dictionary = {}
var _journal_loaded := false

func _ready() -> void:
	request.timeout = 20.0
	request.body_size_limit = 65536
	request.max_redirects = 3
	request.use_threads = true
	add_child(request)
	request.request_completed.connect(_completed)
	download.timeout = 1800.0
	download.max_redirects = 5
	download.use_threads = true
	download.accept_gzip = false
	add_child(download)
	download.request_completed.connect(_download_completed)

func start_automatic(delay := 5.0) -> void:
	if automatic: return
	automatic = true
	next_check = maxf(0.0,delay)
	_load_journal()

func busy() -> bool:
	return state in ["checking","downloading","verifying"]

func has_download() -> bool:
	return not verified_path.is_empty() and FileAccess.file_exists(verified_path)

func _process(dt: float) -> void:
	if _verification.is_started() and not _verification.is_alive():
		_verified(bool(_verification.wait_to_finish()))
	if state == "downloading":
		var bytes := download.get_downloaded_bytes()
		_stalled_age = 0.0 if bytes != downloaded_bytes else _stalled_age+dt
		downloaded_bytes = bytes
		progress = clampf(float(bytes)/maxi(1,int(manifest.size_bytes)),0.0,1.0)
		_progress_age += dt
		if _progress_age >= 0.25:
			_progress_age = 0.0
			message = "正在下载 %s：%s / %s（%.0f%%）" % [latest_version,String.humanize_size(bytes),String.humanize_size(int(manifest.size_bytes)),progress*100.0]
			changed.emit()
		if _stalled_age >= 60.0:
			download.cancel_request()
			_download_fail("下载连接中断，联网后会自动重试。")
	if automatic and not busy():
		next_check -= dt
		if next_check <= 0.0: check()

func check() -> void:
	if busy(): return
	state = "checking"
	message = "正在检查更新…"
	changed.emit()
	var error := request.request(feed_url,["Accept: application/json","Cache-Control: no-cache","User-Agent: Dolikepet/"+VERSION])
	if error != OK: _fail("暂时无法连接更新服务，联网后会自动重试。")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("暂时无法检查更新，联网后会自动重试。")
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not valid_manifest(parser.data):
		_fail("更新信息校验失败，稍后会自动重试。")
		return
	manifest = parser.data.duplicate(true)
	latest_version = manifest.version
	_failures = 0
	next_check = CHECK_INTERVAL
	if not newer(latest_version,VERSION):
		state = "current"
		release_url = ""
		package_path = ""
		verified_path = ""
		message = "当前已是最新版本（%s），会继续自动检查。" % VERSION
		changed.emit()
		return
	release_url = manifest.release_url
	state = "available"
	message = "发现新版本 %s，正在准备下载。" % latest_version
	_notify("available","发现新版本 %s 喵！\n有网时我会帮你下载。" % latest_version)
	changed.emit()
	if auto_download: download_update()

func download_update() -> void:
	if busy() or not valid_manifest(manifest) or not newer(str(manifest.version),VERSION): return
	verified_path = ""
	var root_path := ProjectSettings.globalize_path(cache_dir)
	if FileAccess.file_exists(root_path):
		_download_fail("更新缓存位置被文件占用，请检查后重试。")
		return
	var directory := root_path.path_join(str(manifest.version)+"-"+str(manifest.sha256))
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_download_fail("无法写入更新缓存，请检查磁盘空间或权限后重试。")
		return
	package_path = directory.path_join("Dolikepet-%s-windows-x64.zip" % latest_version)
	if FileAccess.file_exists(package_path): _verify(package_path,true)
	else: _begin_download()

func _begin_download() -> void:
	_remove_partial()
	_part_path = package_path+".%d-%d.part" % [OS.get_process_id(),get_instance_id()]
	download.download_file = _part_path
	download.body_size_limit = int(manifest.size_bytes)
	state = "downloading"
	downloaded_bytes = 0
	progress = 0.0
	_stalled_age = 0.0
	message = "正在下载新版本 %s…" % latest_version
	changed.emit()
	if _request_package(str(manifest.download_url)) != OK:
		_download_fail("暂时无法下载，联网后会自动重试。")

func _request_package(url: String) -> Error:
	return download.request(url,["Accept: application/octet-stream","User-Agent: Dolikepet/"+VERSION])

func _download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if state != "downloading": return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_download_fail("下载未完成，联网后会自动重试；也可在设置中重试。")
		return
	_verify(_part_path,false)

func _verify(path: String, cached: bool) -> void:
	state = "verifying"
	_verifying_cache = cached
	progress = 1.0
	message = "正在校验 %s 的更新包…" % latest_version
	changed.emit()
	if _verification.start(_verify_file.bind(path,int(manifest.size_bytes),str(manifest.sha256)),Thread.PRIORITY_LOW) != OK:
		_download_fail("暂时无法校验更新包，请稍后重试。")

static func _verify_file(path: String, expected_size: int, expected_sha: String) -> bool:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() != expected_size: return false
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var remaining := expected_size
	while remaining > 0:
		var bytes := file.get_buffer(mini(524288,remaining))
		if bytes.is_empty(): return false
		hash.update(bytes)
		remaining -= bytes.size()
	return hash.finish().hex_encode() == expected_sha

func _verified(valid: bool) -> void:
	if not valid:
		if _verifying_cache: _begin_download()
		else: _download_fail("更新包不完整或校验不符，稍后会重新下载。")
		return
	if not _verifying_cache:
		if DirAccess.rename_absolute(_part_path,package_path) != OK:
			_download_fail("保存更新包失败，请关闭占用文件的程序后重试。")
			return
		_part_path = ""
	state = "ready"
	verified_path = package_path
	_failures = 0
	next_check = CHECK_INTERVAL
	progress = 1.0
	downloaded_bytes = int(manifest.size_bytes)
	message = "%s 已下载并校验完成。打开下载文件夹，退出桌宠后再解压更新。" % latest_version
	_notify("ready","新版本 %s 下载完成啦！\n在设置里打开下载文件夹喵。" % latest_version)
	changed.emit()

func _retry_later() -> void:
	_failures = mini(_failures+1,5)
	next_check = minf(900.0,RETRY_INTERVAL*pow(2.0,_failures-1))

func _fail(text: String) -> void:
	state = "error"
	message = text
	_retry_later()
	changed.emit()

func _download_fail(text: String) -> void:
	_remove_partial()
	state = "download_error"
	message = text
	progress = 0.0
	_retry_later()
	changed.emit()

func _remove_partial() -> void:
	if not _part_path.is_empty() and FileAccess.file_exists(_part_path):
		DirAccess.remove_absolute(_part_path)
	_part_path = ""

func _notify(kind: String, text: String) -> void:
	_load_journal()
	var id := latest_version+"|"+str(manifest.sha256)+"|"+kind
	if _announced.has(id) or _queued.has(id): return
	_queued[id] = true
	notice_requested.emit(id,text)

func acknowledge_notice(id: String) -> void:
	if not _queued.has(id): return
	_announced[id] = true
	_queued.erase(id)
	while _announced.size() > 32: _announced.erase(_announced.keys()[0])
	var directory := ProjectSettings.globalize_path(cache_dir)
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return
	var temporary := directory.path_join("notices-%d.tmp" % OS.get_process_id())
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(_announced))
	file.close()
	DirAccess.rename_absolute(temporary,directory.path_join("notices.json"))

func _load_journal() -> void:
	if _journal_loaded: return
	_journal_loaded = true
	var path := ProjectSettings.globalize_path(cache_dir).path_join("notices.json")
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 32768: return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		for key in data:
			if key is String and key.length() < 128 and data[key] == true: _announced[key] = true

func _exit_tree() -> void:
	request.cancel_request()
	download.cancel_request()
	if _verification.is_started(): _verification.wait_to_finish()
	_remove_partial()

static func version_parts(value: String) -> PackedStringArray:
	var pattern := RegEx.new()
	pattern.compile("^(?:beta)?(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})$")
	var found := pattern.search(value)
	if found == null: return []
	return [found.get_string(1),found.get_string(2),found.get_string(3)]

static func newer(candidate: String, current: String) -> bool:
	var a := version_parts(candidate)
	var b := version_parts(current)
	if a.is_empty() or b.is_empty(): return false
	for i in 3:
		if int(a[i]) != int(b[i]): return int(a[i]) > int(b[i])
	return false

static func valid_manifest(data: Variant) -> bool:
	if not data is Dictionary: return false
	var schema = data.get("schema")
	if not (schema is int or schema is float) or schema != 1: return false
	for pair in [["channel","stable"],["platform","windows-x86_64"]]:
		if not data.get(pair[0]) is String or data[pair[0]] != pair[1]: return false
	for field in ["version","release_url","download_url","sha256"]:
		if not data.get(field) is String: return false
	var version: String = data.version
	if version_parts(version).is_empty(): return false
	if data.release_url != REPOSITORY+"/releases/tag/"+version: return false
	if data.download_url != REPOSITORY+"/releases/download/"+version+"/Dolikepet-"+version+"-windows-x64.zip": return false
	var hash_pattern := RegEx.new()
	hash_pattern.compile("^[a-f0-9]{64}$")
	if hash_pattern.search(data.sha256) == null: return false
	var bytes = data.get("size_bytes")
	return (bytes is int or bytes is float) and bytes > 0 and bytes <= 2147483648 and float(bytes) == floor(float(bytes))
