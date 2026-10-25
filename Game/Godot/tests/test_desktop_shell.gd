extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var shell = preload("res://scripts/desktop_shell.gd").new()
	root.add_child(shell)
	var bowl := Window.new(); bowl.title = "Isolated tray fixture"; bowl.visible = false; root.add_child(bowl)
	var cache := ProjectSettings.globalize_path("res://../../_work/tests/desktop-shell/cache")
	var started: bool = shell.start([root,bowl],preload("res://assets/app/icon.png"),cache)
	await create_timer(0.6).timeout
	var ok: bool = started and OS.is_process_running(shell.helper_pid) and shell.indicator.visible and shell.tray_menu.is_native_menu()
	print("Desktop tray/helper integration: ","PASS" if ok else "FAIL")
	if not ok: printerr("helper, tray, or native menu failed")
	shell.queue_free(); bowl.queue_free(); await process_frame
	quit(0 if ok else 1)
