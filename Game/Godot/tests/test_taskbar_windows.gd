extends SceneTree
## Native window roles with isolated host state; no global input or user folders.
var failures: Array[String] = []
var checks := 0
var app

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func hidden_from_taskbar(window: Window) -> bool:
	var id := window.get_window_id()
	if id == DisplayServer.INVALID_WINDOW_ID: return false
	return bool(app.desktop_shell.native_bridge.call("desktop_window_is_taskbar_hidden",
		DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, id)))

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("TASKBAR WINDOWS: fixture timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	var fixture := ProjectSettings.globalize_path("res://../../_work/tests/taskbar-windows/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(fixture)
	app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = fixture.path_join("pet.cfg")
	root.add_child(app)
	app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false); root.mouse_passthrough = true
	await process_frame
	app._setup_desktop_shell(fixture.path_join("shell"))
	verify(is_instance_valid(app.desktop_shell.native_bridge), "synchronous native bridge is available")
	verify(hidden_from_taskbar(root), "pet window is excluded before the helper's first poll")
	app.bowl_window.show()
	verify(hidden_from_taskbar(app.bowl_window), "newly shown bowl is synchronously excluded")
	app.settings_window.show_settings(false, 60, 300)
	await process_frame
	verify(not hidden_from_taskbar(app.settings_window), "settings alone keeps its normal taskbar role")
	app.ai_chat.open_panel(); app.ai_memory.open_panel(); app.score_board.open_board(root.current_screen)
	await process_frame
	for window in [app.ai_chat, app.ai_memory, app.score_board]:
		verify(hidden_from_taskbar(window), str(window.title) + " is excluded from taskbar")
		window.hide(); window.show()
		verify(hidden_from_taskbar(window), str(window.title) + " stays excluded after reopening")
	# A late-created confirmation/dialog must not need a new hardcoded host list.
	var late := Window.new(); late.visible = false; late.title = "Isolated late auxiliary window"
	app.settings_window.add_child(late)
	app.desktop_shell._sync_windows()
	var foreground: int = app.desktop_shell.native_bridge.call("companion_foreground_handle")
	app.desktop_shell.prepare_window(late)
	verify(not late.visible and int(app.desktop_shell.native_bridge.call("companion_foreground_handle")) == foreground,
		"preparing hidden auxiliary window neither shows nor activates it")
	late.show()
	verify(hidden_from_taskbar(late), "late settings child is excluded on first show")
	late.hide()
	await create_timer(0.4).timeout
	verify(OS.is_process_running(app.desktop_shell.helper_pid), "taskbar maintenance helper stays running")
	verify(app.desktop_shell.indicator.visible, "one shared tray icon remains available")
	verify(not late.visible, "background maintenance does not reopen hidden dialogs")
	verify(not hidden_from_taskbar(app.settings_window), "maintenance still leaves settings visible in taskbar")
	var request: String = FileAccess.get_file_as_string(app.desktop_shell.request)
	var settings_handle := str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, app.settings_window.get_window_id()))
	verify(not request.split("\n").has(settings_handle+":0") and not request.split("\n").has(settings_handle+":1"),
		"settings is excluded from helper requests")
	var chat_handle := str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, app.ai_chat.get_window_id()))
	verify(request.split("\n").has(chat_handle+":0"), "chat keeps normal minimizing policy instead of desktop-widget policy")
	app.queue_free(); await process_frame
	for failure in failures: printerr("TASKBAR WINDOWS: " + failure)
	print("Taskbar windows: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
