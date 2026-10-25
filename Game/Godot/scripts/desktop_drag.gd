extends RefCounted
## Both widgets use the same physical-button and capture lifetime. The input
## cache alone is insufficient after a lost up or a transfer to another window.
var bridge: Object
var capture_expected := false

func primary_pressed() -> bool:
	if OS.get_name()=="Windows" and is_instance_valid(bridge) and bridge.has_method("desktop_primary_pressed"):
		return bridge.call("desktop_primary_pressed")
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _handle(window: Window) -> int:
	var id := window.get_window_id()
	# Hiding a nonembedded Window destroys its native handle before emitting
	# visibility_changed. Its capture has already been released by Windows.
	if not DisplayServer.get_window_list().has(id): return 0
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,id)

func _owns_capture(window: Window) -> bool:
	var handle := _handle(window)
	return handle!=0 and is_instance_valid(bridge) and bridge.has_method("desktop_capture_matches") \
		and bridge.call("desktop_capture_matches",handle)

func begin(window: Window) -> void:
	# Native mouse-down has established capture before dispatching the event.
	# Pure scripted input (tests, non-Windows) has no native capture to monitor.
	capture_expected = _owns_capture(window)

func held(window: Window) -> bool:
	return primary_pressed() and window.visible and window.mode!=Window.MODE_MINIMIZED \
		and (not capture_expected or _owns_capture(window))

func release_capture(window: Window) -> void:
	capture_expected = false
	var handle := _handle(window)
	if handle!=0 and OS.get_name()=="Windows" and is_instance_valid(bridge) and bridge.has_method("release_desktop_capture"):
		bridge.call("release_desktop_capture",handle)

func repair_cache(window: Window) -> void:
	# Never synthesize an up while a fresh press owns another widget. All local
	# drag flags/physics must be released before flushing a late native/cache up.
	if primary_pressed() or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = Input.get_mouse_button_mask() & ~MOUSE_BUTTON_MASK_LEFT
	event.position = Vector2(DisplayServer.mouse_get_position()-window.position)
	event.global_position = event.position; event.window_id = window.get_window_id()
	Input.parse_input_event(event); Input.flush_buffered_events()
