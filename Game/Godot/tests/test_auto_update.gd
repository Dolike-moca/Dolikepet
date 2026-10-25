extends SceneTree
const Update = preload("res://scripts/app_update.gd")
class LocalUpdate extends "res://scripts/app_update.gd":
	var package_url := ""
	var transfers := 0
	func _request_package(_url: String) -> Error:
		transfers += 1
		return download.request(package_url)
var base := ""
var fixture := ""
var failures: Array[String] = []
var count := 0
var notices: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func verify(value: bool, text: String) -> void:
	count += 1
	if not value: failures.append(text)
func service(name: String, cache: String = ""):
	var updater = LocalUpdate.new()
	updater.feed_url = base+"/feed/"+name
	updater.package_url = base+"/package/"+name
	updater.cache_dir = fixture.path_join(cache if not cache.is_empty() else name)
	root.add_child(updater)
	updater.notice_requested.connect(func(id, words):
		notices.append({"id":id,"text":words})
		updater.acknowledge_notice(id))
	return updater
func wait_for(updater, states: Array) -> void:
	var end := Time.get_ticks_msec()+15000
	while not updater.state in states and Time.get_ticks_msec()<end: await process_frame
	verify(updater.state in states,"timed out: "+str(updater.state)+" / "+str(states))
func dispose(updater) -> void:
	updater.queue_free()
	await process_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): base = arg.trim_prefix("--server=")
		if arg.begins_with("--fixture="): fixture = arg.trim_prefix("--fixture=")
	if not base.begins_with("http://127.0.0.1:") or fixture.is_empty(): quit(2); return
	var updater = service("offline")
	updater.start_automatic(0.0)
	await wait_for(updater,["error"])
	verify(updater.next_check>0 and notices.is_empty(),"offline retry is quiet")
	updater.next_check = 0.0
	await wait_for(updater,["ready"])
	verify(updater.transfers==1,"reconnect downloads once")
	verify(notices.size()==2 and str(notices[0].id).ends_with("available") and str(notices[1].id).ends_with("ready"),"new version and completion notify in order")
	verify(Update._verify_file(updater.package_path,int(updater.manifest.size_bytes),str(updater.manifest.sha256)),"final file verifies")
	verify(updater._part_path.is_empty() and updater.progress==1.0,"no partial completion")
	verify(updater.package_path.begins_with(fixture) and updater.next_check>20000.0,"isolated cache and periodic recheck")
	var cached_path: String = updater.package_path
	updater._fail("fixture offline after download")
	verify(updater.has_download() and updater.verified_path==cached_path,"verified package remains accessible offline")
	await dispose(updater)
	updater = service("good","offline")
	updater.start_automatic(0.0)
	await wait_for(updater,["ready"])
	verify(updater.transfers==0 and notices.size()==2,"restart verifies cache without downloading or repeating acknowledged notices")
	await dispose(updater)
	var corrupt := FileAccess.open(cached_path,FileAccess.WRITE)
	corrupt.store_string("broken cache"); corrupt.close()
	updater = service("good","offline")
	updater.start_automatic(0.0)
	await wait_for(updater,["ready"])
	verify(updater.transfers==1 and Update._verify_file(updater.package_path,int(updater.manifest.size_bytes),str(updater.manifest.sha256)),"corrupt cache repaired by fresh verified download")
	await dispose(updater)
	for scenario in ["wrong-hash","truncated","oversized","http-error"]:
		var before := notices.size()
		updater = service(scenario)
		updater.start_automatic(0.0)
		await wait_for(updater,["download_error"])
		verify(not FileAccess.file_exists(updater.package_path) and updater._part_path.is_empty(),"bad response never promoted: "+scenario)
		verify(notices.size()==before+1 and updater.next_check>0.0,"bad download does not emit ready and retries: "+scenario)
		await dispose(updater)
	updater = service("current")
	updater.start_automatic(0.0)
	await wait_for(updater,["current"])
	verify(updater.transfers==0 and updater.package_path.is_empty(),"current version is not downloaded")
	await dispose(updater)
	updater = service("bad-manifest")
	updater.start_automatic(0.0)
	await wait_for(updater,["error"])
	verify(updater.transfers==0,"invalid URL cannot start download")
	await dispose(updater)
	updater = service("good","blocked")
	var file := FileAccess.open(fixture.path_join("blocked"),FileAccess.WRITE)
	file.store_string("fixture prevents directory creation"); file.close()
	updater.start_automatic(0.0)
	await wait_for(updater,["download_error"])
	verify(updater.transfers==0,"unwritable cache fails safely")
	await dispose(updater)
	updater = service("slow")
	updater.start_automatic(0.0)
	await wait_for(updater,["downloading"])
	var deadline := Time.get_ticks_msec()+5000
	while updater.download.get_downloaded_bytes()==0 and Time.get_ticks_msec()<deadline: await process_frame
	verify(updater.download.get_downloaded_bytes()>0 and FileAccess.file_exists(updater._part_path),"cancel fixture has received and written a real partial download")
	var original_request: int = updater.download.get_instance_id()
	updater.check(); updater.download_update()
	verify(updater.state=="downloading" and updater.transfers==1 and updater.download.get_instance_id()==original_request,"manual checks never duplicate active transfer")
	var part: String = updater._part_path
	await dispose(updater)
	verify(not FileAccess.file_exists(part),"closing during transfer removes its own partial file")
	for text in failures: printerr(text)
	print("AUTO UPDATE: %d checks, %d failures" % [count,failures.size()])
	quit(0 if failures.is_empty() else 1)
