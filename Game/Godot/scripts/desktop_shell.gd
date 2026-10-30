extends Node
## One tray entry for all widgets; settings is deliberately an independent window.
signal action_requested(id: int)
var indicator: StatusIndicator
var tray_menu: PopupMenu
var windows: Array[Window] = []
var taskbar_windows: Array[Window] = []
var native_bridge: Object
var tracked: Dictionary = {}
var stopping := false
var helper_pid := -1
var request := ""
var previous := ""
var poll := 0.0

func prepare_window(window: Window, desktop_widget := false) -> void:
	if stopping or OS.get_name()!="Windows" or DisplayServer.get_name()=="headless" or not is_instance_valid(window) or taskbar_windows.has(window): return
	if not is_instance_valid(native_bridge) and ClassDB.class_exists("GDCubismUserModel"):
		native_bridge = ClassDB.instantiate("GDCubismUserModel")
	if not is_instance_valid(native_bridge) or not native_bridge.has_method("exclude_desktop_window_from_taskbar"): return
	var id := window.get_window_id()
	if id == DisplayServer.INVALID_WINDOW_ID: return
	native_bridge.call("exclude_desktop_window_from_taskbar", DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,id), desktop_widget)

func start(widgets: Array[Window], icon: Texture2D, cache_override := "", exceptions: Array[Window] = []) -> bool:
	if OS.get_name()!="Windows" or DisplayServer.get_name()=="headless": return false
	windows = widgets
	taskbar_windows = exceptions
	indicator = StatusIndicator.new()
	tray_menu = PopupMenu.new()
	tray_menu.name = "TrayMenu"
	tray_menu.prefer_native_menu = true
	add_child(tray_menu)
	tray_menu.add_item("桌宠设置…",14)
	tray_menu.add_item("打开猫咪小对话框…",25)
	tray_menu.add_item("聊天记录…",24)
	tray_menu.add_item("计分板…",23)
	tray_menu.add_check_item("猫的饭盆",17)
	tray_menu.add_item("恢复默认大小与位置",20)
	tray_menu.add_separator()
	tray_menu.add_item("退出桌宠",22)
	tray_menu.id_pressed.connect(func(id): action_requested.emit(id))
	indicator.icon = icon
	indicator.tooltip = "Dolike 桌宠 · 猫的饭盆"
	add_child(indicator)
	indicator.menu = indicator.get_path_to(tray_menu)
	indicator.visible = true
	var cache := cache_override if not cache_override.is_empty() else ProjectSettings.globalize_path("user://desktop-shell")
	DirAccess.make_dir_recursive_absolute(cache)
	var bytes := FileAccess.get_file_as_bytes("res://native/DesktopShell.exe")
	var helper := cache.path_join("DesktopShell-"+str(hash(bytes))+".exe")
	if not FileAccess.file_exists(helper):
		var file := FileAccess.open(helper,FileAccess.WRITE)
		if file==null: return false
		file.store_buffer(bytes); file.close()
	request = cache.path_join("windows-"+str(OS.get_process_id())+".txt")
	_sync_windows()
	helper_pid = OS.create_process(helper,[str(OS.get_process_id()),request])
	return helper_pid>0

func _sync_windows() -> void:
	var handles := PackedStringArray()
	_collect_windows(get_tree().root, handles)
	var text := "\n".join(handles)
	if text==previous: return
	var file := FileAccess.open(request,FileAccess.WRITE)
	if file!=null: file.store_string(text); file.close(); previous = text

func _collect_windows(node: Node, handles: PackedStringArray) -> void:
	if node is Window and not taskbar_windows.has(node):
		var window := node as Window
		var desktop_widget := windows.has(window)
		if not tracked.has(window.get_instance_id()):
			tracked[window.get_instance_id()] = true
			prepare_window(window, desktop_widget)
			window.visibility_changed.connect(prepare_window.bind(window,desktop_widget))
		var id := window.get_window_id()
		if id != DisplayServer.INVALID_WINDOW_ID:
			handles.append(str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,id))+":"+("1" if desktop_widget else "0"))
	for child in node.get_children(): _collect_windows(child, handles)

func _process(dt: float) -> void:
	if request.is_empty(): return
	poll -= dt
	if poll>0.0: return
	poll = 0.15
	_sync_windows()
	if windows.size()>1: tray_menu.set_item_checked(tray_menu.get_item_index(17),windows[1].visible)

func _exit_tree() -> void:
	stopping = true
	if is_instance_valid(indicator): indicator.visible = false
	# The helper exits automatically with its parent; terminating only our own
	# idle helper also supports tests removing/recreating the host within one process.
	if helper_pid>0 and OS.is_process_running(helper_pid): OS.kill(helper_pid)
	if not request.is_empty(): DirAccess.remove_absolute(request)
	if is_instance_valid(native_bridge): native_bridge.free()
