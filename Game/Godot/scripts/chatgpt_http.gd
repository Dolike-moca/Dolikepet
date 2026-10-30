extends Node
## Small OAuth JSON requests. No redirects, external endpoints or raw error logs.
signal finished(result: Dictionary)
var request := HTTPRequest.new()
var busy := false

func _ready() -> void:
	request.timeout = 25.0
	request.max_redirects = 0
	request.body_size_limit = 2097152
	request.use_threads = true
	add_child(request)
	request.request_completed.connect(_complete)

func send(url: String, method: int, headers: PackedStringArray, body: String) -> bool:
	if busy: return false
	if not (url.begins_with("https://auth.openai.com/") or url == "https://api.openai.com/v1/models"): return false
	busy = true
	var error := request.request(url, headers, method, body)
	if error != OK:
		busy = false
		return false
	return true

func cancel() -> void:
	if not busy: return
	request.cancel_request(); busy = false
	finished.emit({"ok":false, "status":0, "data":{}, "canceled":true})

func _complete(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if not busy: return
	busy = false
	var data := {}
	if not bytes.is_empty():
		var parser := JSON.new()
		if parser.parse(bytes.get_string_from_utf8()) == OK and parser.data is Dictionary: data = parser.data
	finished.emit({"ok":result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300,
		"status":code, "data":data, "empty":bytes.is_empty()})
