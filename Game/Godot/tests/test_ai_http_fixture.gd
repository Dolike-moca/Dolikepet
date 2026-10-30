extends SceneTree
## Runs against tools/test-ai-http.py's loopback fixture, never a paid API.
const Transport = preload("res://scripts/ai_http.gd")
var checks := 0
var failures: Array[String] = []
var endpoint := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("AI HTTP: "+label)

func request(path: String) -> Dictionary:
	var transport := Transport.new()
	root.add_child(transport)
	transport.endpoint_override = endpoint+path
	var state := {"http":transport,"parts":[],"done":[],"errors":[],"cancels":0,"frames":0}
	transport.delta.connect(func(text): state.parts.append(text))
	transport.completed.connect(func(text): state.done.append(text))
	transport.failed.connect(func(text): state.errors.append(text))
	transport.canceled.connect(func(): state.cancels += 1)
	check(transport.start("fixture-key-never-real", {"model":"fixture","input":"fixture-only"}), path+" starts")
	var start := Time.get_ticks_msec()
	while transport.busy and Time.get_ticks_msec()-start<5000:
		if path=="/cancel" and state.frames==5: transport.cancel()
		if path=="/timeout" and state.frames==5: transport._started_at -= 181000
		state.frames += 1
		await process_frame
	check(not transport.busy, path+" reaches terminal state")
	if transport.busy: transport.cancel()
	transport.free()
	return state

func retry_after_empty_error() -> Dictionary:
	var transport := Transport.new()
	root.add_child(transport)
	transport.endpoint_override = endpoint+"/empty-status/401"
	var state := {"done":[],"errors":[],"retried":false}
	transport.completed.connect(func(text): state.done.append(text))
	transport.failed.connect(func(text):
		state.errors.append(text)
		if state.retried: return
		state.retried = true
		transport.endpoint_override = endpoint+"/stream"
		check(transport.start("fixture-key-never-real", {"model":"fixture","input":"retry-fixture"}),
			"new request may start synchronously from failed listener"))
	check(transport.start("fixture-key-never-real", {"model":"fixture","input":"empty-error-fixture"}),
		"empty HTTP error request starts")
	var start := Time.get_ticks_msec()
	while transport.busy and Time.get_ticks_msec()-start<5000: await process_frame
	check(not transport.busy and state.errors.size()==1 and state.done==["你好喵！陪你一会儿。"],
		"zero-body HTTP error cannot terminate replacement request")
	transport.free()
	return state

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--endpoint="): endpoint = arg.trim_prefix("--endpoint=")
	if not endpoint.begins_with("http://127.0.0.1:"):
		printerr("A loopback --endpoint is required")
		quit(2)
		return
	var state: Dictionary = await request("/stream")
	check(state.done==["你好喵！陪你一会儿。"] and state.errors.is_empty(), "HTTP stream preserves UTF8 and completes")
	check(state.parts.size()==2 and state.frames>5, "incremental frames continue while receiving")
	for code in [400,401,403,404,429,500,302]:
		state = await request("/status/"+str(code))
		check(state.errors.size()==1 and state.done.is_empty(), str(code)+" handled once")
		check(not "raw-server-body" in str(state.errors), str(code)+" never leaks raw error body")
	state = await request("/truncated")
	check(state.done.is_empty() and state.errors.size()==1 and state.parts==["半句话"], "closed stream without completion is failure")
	state = await request("/wrong-type")
	check(state.done.is_empty() and state.errors.size()==1, "non-SSE response rejected")
	state = await request("/cancel")
	check(state.cancels==1 and state.done.is_empty() and state.errors.is_empty(), "cancel stops pending network request")
	state = await request("/timeout")
	check(state.errors.size()==1 and state.done.is_empty(), "total timeout stops pending request")
	await retry_after_empty_error()
	print(JSON.stringify({"suite":"ai_http_fixture","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
