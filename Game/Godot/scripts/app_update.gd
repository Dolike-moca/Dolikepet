extends Node
## Public version manifest. No credentials, background installer or startup request.
signal changed
const VERSION := "0.2.0"
const RELEASE_NAME := "纳垢的赐福"
const REPOSITORY := "https://github.com/Dolike-moca/Dolikepet"
const FEED_URL := "https://raw.githubusercontent.com/Dolike-moca/Dolikepet/main/updates/latest.json"
var state := "idle"
var message := "手动检查新版本，更新时保留原文件夹中的饭盆和胃袋。"
var release_url := ""
var latest_version := ""
var request := HTTPRequest.new()

func _ready() -> void:
	request.timeout = 15.0
	request.body_size_limit = 65536
	request.max_redirects = 3
	request.use_threads = true
	add_child(request)
	request.request_completed.connect(_completed)

func check() -> void:
	if state == "checking": return
	state = "checking"
	message = "正在检查更新…"
	release_url = ""
	latest_version = ""
	changed.emit()
	var error := request.request(FEED_URL, ["Accept: application/json", "Cache-Control: no-cache", "User-Agent: Dolikepet/"+VERSION])
	if error != OK: _fail("暂时无法连接更新服务，请稍后重试。")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("检查更新失败，请检查网络后重试。")
		return
	if code != 200:
		_fail("更新服务暂不可用（%d），请稍后重试。" % code)
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		_fail("更新信息格式不正确，请稍后重试。")
		return
	var data = parser.data
	if not valid_manifest(data):
		_fail("更新信息格式不正确，请稍后重试。")
		return
	latest_version = data.version
	if newer(latest_version, VERSION):
		state = "available"
		release_url = data.release_url
		message = "发现新版本 %s，点击下方按钮查看并下载。" % latest_version
	else:
		state = "current"
		release_url = ""
		message = "当前已是最新版本（%s）。" % VERSION
	changed.emit()

func _fail(text: String) -> void:
	state = "error"
	message = text
	release_url = ""
	latest_version = ""
	changed.emit()

static func version_parts(value: String) -> PackedStringArray:
	var pattern := RegEx.new()
	pattern.compile("^(?:beta)?(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})\\.(0|[1-9][0-9]{0,5})$")
	var found := pattern.search(value)
	if found == null: return []
	return [found.get_string(1), found.get_string(2), found.get_string(3)]

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
	if not (schema is int or schema is float): return false
	if schema != 1: return false
	for pair in [["channel", "stable"], ["platform", "windows-x86_64"]]:
		if not data.get(pair[0]) is String or data[pair[0]] != pair[1]: return false
	for field in ["version", "release_url", "download_url", "sha256"]:
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
