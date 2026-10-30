extends SceneTree
## Real native HWND opacity; no global input, fixture files, or external windows.
var checks := 0
var failures: Array[String] = []

func verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func handle_for(window: Window) -> int:
	var id := window.get_window_id()
	return 0 if id == DisplayServer.INVALID_WINDOW_ID else DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, id)

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): printerr("CHAT OPACITY: fixture timed out"); quit(1))
	call_deferred("run")

func run() -> void:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		printerr("CHAT OPACITY: requires native Windows display server")
		quit(1); return
	var bridge = ClassDB.instantiate("GDCubismUserModel")
	verify(is_instance_valid(bridge) and bridge.has_method("set_companion_window_opacity") and bridge.has_method("get_companion_window_opacity"), "native opacity API is available")
	if not failures.is_empty():
		if is_instance_valid(bridge): bridge.free()
		quit(1); return
	var window := Window.new()
	window.title = "Dolike isolated whole-window opacity fixture"
	window.visible = false; window.unfocusable = true
	window.size = Vector2i(360, 240); window.position = Vector2i(100, 100)
	root.add_child(window)
	var color := ColorRect.new()
	color.color = Color(0.85, 0.25, 0.12, 1.0)
	color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(color)
	window.show()
	await process_frame; await process_frame
	var handle := handle_for(window)
	var foreground: int = bridge.companion_foreground_handle()
	var position := window.position
	var size := window.size
	verify(handle != 0, "fixture owns a native HWND")
	verify(not bridge.set_companion_window_opacity(0, 0.5) and not bridge.set_companion_window_opacity(-1, 0.5), "invalid native handles are rejected")
	verify(not bridge.set_companion_window_opacity(handle, NAN) and not bridge.set_companion_window_opacity(handle, INF), "non-finite opacity is rejected")
	verify(bridge.set_companion_window_opacity(handle, 0.5), "native half opacity applies to real Godot Window")
	await process_frame; await process_frame
	verify(absf(float(bridge.get_companion_window_opacity(handle)) - 128.0 / 255.0) < 0.00001, "native layered alpha remains half across rendering frames")
	verify(window.visible and window.position == position and window.size == size and int(bridge.companion_foreground_handle()) == foreground, "fade preserves visibility, placement and foreground")
	verify(color.modulate.a == 1.0 and color.color.a == 1.0, "content stays fully drawn while HWND supplies opacity")
	verify(bridge.set_companion_window_opacity(handle, -2.0) and bridge.get_companion_window_opacity(handle) == 0.0, "negative finite opacity clamps to zero")
	verify(bridge.set_companion_window_opacity(handle, 2.0) and bridge.get_companion_window_opacity(handle) == 1.0, "above-one opacity restores fully opaque rendering")
	for opacity in [0.9, 0.5, 0.1, 0.4, 0.7, 1.0]:
		verify(bridge.set_companion_window_opacity(handle, opacity), "repeated fade/return applies")
		await process_frame
	verify(bridge.set_companion_window_opacity(handle, 0.1), "prepare fade before hide")
	window.hide()
	var hidden_handle := handle_for(window)
	if hidden_handle != 0:
		verify(bridge.set_companion_window_opacity(hidden_handle, 1.0) and not window.visible, "restoring hidden HWND never shows it")
	else:
		verify(bridge.get_companion_window_opacity(handle) == -1.0, "Godot destroyed HWND cannot retain opacity state")
	window.show()
	await process_frame
	handle = handle_for(window)
	verify(bridge.set_companion_window_opacity(handle, 1.0) and bridge.get_companion_window_opacity(handle) == 1.0, "reopened native Window is opaque")
	var pet := Window.new()
	pet.visible = false; pet.borderless = true; pet.transparent = true; pet.transparent_bg = true; pet.unfocusable = true
	root.add_child(pet); pet.show()
	verify(not bridge.set_companion_window_opacity(handle_for(pet), 0.5), "per-pixel transparent pet-style Window is rejected")
	pet.hide(); pet.queue_free()
	verify(int(bridge.companion_foreground_handle()) == foreground, "opacity and reopen never acquire foreground focus")
	window.hide(); window.queue_free(); bridge.free()
	await process_frame
	for failure in failures: printerr("CHAT OPACITY: " + failure)
	print("Chat window native opacity: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
