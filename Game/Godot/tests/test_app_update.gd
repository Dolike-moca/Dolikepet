extends SceneTree
const Update = preload("res://scripts/app_update.gd")
var failures: Array[String] = []
var count := 0
func _initialize() -> void: call_deferred("run")
func verify(value: bool, text: String) -> void:
	count += 1
	if not value: failures.append(text)
func manifest(version := Update.VERSION) -> Dictionary:
	return {"schema":1, "channel":"stable", "platform":"windows-x86_64", "version":version,
		"release_url":Update.REPOSITORY+"/releases/tag/"+version,
		"download_url":Update.REPOSITORY+"/releases/download/"+version+"/Dolikepet-"+version+"-windows-x64.zip",
		"size_bytes":123, "sha256":"a".repeat(64)}
func run() -> void:
	verify(ProjectSettings.get_setting("application/config/version") == Update.VERSION, "project version must match feed client")
	verify(Update.VERSION=="0.3.1" and Update.RELEASE_NAME=="色孽的赐福", "release version and name")
	verify(Update.newer("0.3.1","0.3.0"), "patch release is newer than the previous public build")
	verify(not Update.newer("beta0.3.1","0.3.1"), "patch compatibility entry does not trigger another upgrade")
	verify(Update.newer("0.2.0","beta0.1.0"), "upgrade from original beta numbering")
	verify(not Update.newer("beta0.2.0","0.2.0"), "compatibility tag is not a newer build")
	verify(Update.newer("0.3.0","0.2.0"), "next stable version compares correctly")
	for pair in [["beta0.1.1","beta0.1.0"],["beta0.10.0","beta0.9.9"],["beta1.0.0","beta0.99.99"]]:
		verify(Update.newer(pair[0],pair[1]),"numeric version order")
	for pair in [["beta0.1.0","beta0.1.0"],["beta0.1.0","beta0.2.0"],["beta0.01.2","beta0.1.0"],["garbage","beta0.1.0"]]:
		verify(not Update.newer(pair[0],pair[1]),"invalid/older version must not update")
	verify(Update.valid_manifest(manifest()),"valid published manifest")
	for value in [null,[],"hello",{}, {"schema":1}]: verify(not Update.valid_manifest(value),"reject malformed manifest")
	for field in ["release_url","download_url","version","sha256","size_bytes","channel","schema","platform"]:
		var data := manifest()
		data[field] = "https://example.org/other.exe"
		verify(not Update.valid_manifest(data),"reject untrusted field: "+field)
	for value in [-1,0,1.5,2147483649]:
		var data := manifest(); data.size_bytes = value
		verify(not Update.valid_manifest(data),"reject invalid package size")
	var page = load("res://scripts/pet_settings.gd").new()
	root.add_child(page)
	await process_frame
	var service = page.updater
	service.auto_download = false
	service.cache_dir = ProjectSettings.globalize_path("res://../../_work/tests/update-unit")
	service.feed_url = "http://127.0.0.1:1/unavailable"
	verify(service.state=="idle", "host connects notices before scheduling startup check")
	verify(not page.download_button.visible and not page.update_button.disabled,"initial settings controls")
	page.digestion_hours.value = 12
	service._completed(HTTPRequest.RESULT_SUCCESS,200,[],JSON.stringify(manifest("beta0.10.0")).to_utf8_buffer())
	verify(service.state=="available" and page.download_button.visible,"new version opens download entry")
	verify(page.digestion_hours.value==12,"checking updates preserves settings draft")
	service._completed(HTTPRequest.RESULT_SUCCESS,200,[],JSON.stringify(manifest()).to_utf8_buffer())
	verify(service.state=="current" and service.release_url.is_empty() and not page.download_button.visible,"current version clears old download")
	service._completed(HTTPRequest.RESULT_SUCCESS,200,[],JSON.stringify(manifest("beta0.0.9")).to_utf8_buffer())
	verify(service.state=="current","never downgrade")
	for code in [404,429,500]:
		service._completed(HTTPRequest.RESULT_SUCCESS,code,[],PackedByteArray())
		verify(service.state=="error" and not page.update_button.disabled,"HTTP error allows retry")
	for result in [HTTPRequest.RESULT_TIMEOUT,HTTPRequest.RESULT_CANT_CONNECT,HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED]:
		service._completed(result,0,[],PackedByteArray())
		verify(service.state=="error" and not page.download_button.visible and service.next_check>=60.0,"network errors schedule retry without offering unverified files")
	service._completed(HTTPRequest.RESULT_SUCCESS,200,[],"<html>bad gateway</html>".to_utf8_buffer())
	verify(service.state=="error","non-JSON rejected")
	service.check()
	verify(service.state=="checking" and page.update_button.disabled,"manual asynchronous check")
	service.check()
	verify(service.state=="checking","double click cannot duplicate request")
	await process_frame
	verify(page.digestion_hours.value==12,"UI still processes while request is pending")
	service.request.cancel_request()
	page.queue_free()
	await process_frame
	for text in failures: printerr(text)
	print("Update interface: ",count," checks ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
