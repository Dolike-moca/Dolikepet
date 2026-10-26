extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
var target := Vector2.ZERO
class Buttons extends RefCounted:
	func desktop_primary_pressed() -> bool: return true
	func desktop_capture_matches(_handle: int) -> bool: return false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("PHYSICS HOST: " + message)
func tick(count: int = 1) -> void:
	for i in count:
		var held: bool = app.dragging
		if held: app._update_drag_pointer(Vector2i(target), true)
		# Keep ownership during the host tick; pretending dragging=false now
		# correctly exercises orphan-spring cleanup, not a valid held gesture.
		app._process(1.0 / 60)
		if held: app._update_drag_pointer(Vector2i(target), true)
		await process_frame
func grab() -> void:
	app.dragging = true
	app.drag_moved = true
	app.drag_pointer = root.position + Vector2i(app.pet.physics_anchor())
	app.drag_window = root.position
	target = Vector2(app.drag_pointer)
	app._begin_grab()
func opaque_point() -> Vector2:
	var image: Image = app.hit_area.image
	for y in range(0,image.get_height(),4):
		for x in range(0,image.get_width(),4):
			if image.get_pixel(x,y).a>0.99: return Vector2(x,y)
	return Vector2(-1,-1)
func run() -> void:
	var path := ProjectSettings.globalize_path("res://../../_work/tests/physics-host-settings.cfg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var settings := ConfigFile.new()
	settings.set_value("window", "size", 420)
	settings.set_value("window", "position", Vector2i(120, 100))
	settings.set_value("pet", "auto_fall_enabled", false)
	settings.set_value("pet", "roaming_mode", "off")
	settings.set_value("pet", "auto_sit_enabled", false)
	check(settings.save(path)==OK,"isolated settings fixture could not be saved")
	app = Scene.instantiate()
	app.settings_path = path
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app.drag_input.bridge = Buttons.new()
	root.mouse_passthrough = true
	app.bubble.hide()
	check(app.pet.available, app.pet.failure)
	if not app.pet.available: quit(1); return
	await tick(3)
	var at: Vector2i = root.position
	await tick(20)
	check(root.position == at and not app.falling.active(), "disabled gravity moved idle window")
	# Normal clicks retain the threshold; no physical activation on click jitter.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	await RenderingServer.frame_post_draw
	app._capture_hit_area()
	click.position = opaque_point()
	app._input(click)
	app._update_drag_pointer(app.drag_pointer + Vector2i(3, 0), true)
	check(not app.drag_moved and not app.falling.active(), "click jitter activates body")
	click.pressed = false
	app._input(click)
	# Grabbing a seated pet in a mirror turn must regain a full-width pose.
	app._menu_action(12)
	app.pet.sitting.amount = 1.0
	app.pet.facing_scale = -0.12
	app.roaming.facing_scale = -0.12
	app.roaming.state = "turning"
	grab()
	target += Vector2(110, -65)
	await tick(65)
	check(not app.pet.sitting.seated and app.pet.sitting.amount == 0.0, "held sitting did not unfold")
	check(app.pet.facing_scale == -1.0 and app.roaming.state == "idle", "compressed turn leaked into physics")
	check(root.position.distance_to(at) > 30, "native body failed to move OS window")
	var origin: Vector2 = app.falling.window_position()
	for f in 15:
		target += Vector2(12, -4)
		await tick()
	var v: Vector2 = app.falling.body.linear_velocity
	var w: float = app.falling.body.angular_velocity
	app._finish_drag()
	check(app.falling.body.linear_velocity == v and app.falling.body.angular_velocity == w, "host discarded throw momentum")
	await tick(5)
	check(app.falling.window_position().distance_to(origin) > 20, "release stopped immediately")
	# Independent settings do not freeze or replace the active trajectory.
	app.settings_window.show_settings(true, 5, 10, "off", false)
	await tick(2)
	origin = app.falling.window_position()
	await tick(20)
	check(not app.falling.paused and app.falling.window_position().distance_to(origin)>1.0, "settings froze trajectory")
	v = app.falling.body.linear_velocity
	app.settings_window.hide()
	await tick(2)
	check(app.falling.body.linear_velocity.length() > v.length() * 0.6, "settings close lost momentum")
	# An in-flight left press catches without needing another five-pixel drag.
	v = app.falling.body.linear_velocity
	origin = app.falling.body.position
	click.pressed = true
	await RenderingServer.frame_post_draw
	app._capture_hit_area()
	click.position = opaque_point()
	app._input(click)
	check(app.drag_moved and app.falling.state == "held", "midair click did not immediately catch")
	check(app.falling.body.position == origin and app.falling.body.linear_velocity == v, "catch teleported or cleared speed")
	app.drag_pointer = root.position + Vector2i(app.pet.physics_anchor(-1))
	app._begin_grab()
	target = Vector2(app.drag_pointer)
	await tick(20)
	var held_size := root.size
	app._zoom(24)
	target = Vector2(app.drag_pointer)
	await tick(8)
	check(root.size==held_size and app.size_change.pending() and app.size_change.state=="waiting", "held resize did not wait for release")
	check(app.falling.size == Vector2(root.size) and app.falling.body.position.is_finite(), "held resize failed")
	app._finish_drag()
	app.falling.configure(true)
	app.idle_sitting.configure(true, 5, 5)
	app._menu_action(12)
	check(app.manual_sit_pending and not app.pet.sitting.seated, "manual sit not deferred until landing")
	for f in 240:
		await tick()
		if app.falling.pose().fallActive: check(not app.pet.sitting.seated, "sat before actual floor contact")
	check(not app.falling.active(), "host never returned physical ownership to idle")
	check(app.pet.sitting.seated and not app.manual_sit_pending, "deferred sit lost after landing")
	app._menu_action(13)
	await tick(120)
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	check(absi(root.position.y + root.size.y - area.end.y) < 2, "floor handoff differs from walking floor")
	# Inspect real meshes at the angular/strain limits in both facings.
	var clipped := 0
	app.pet.tail.automatic = false
	for facing in [-1.0, 1.0]:
		for angle in [-24.0, 24.0]:
			for f in 45:
				var pose: Dictionary = app.behavior.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, root.size.y, false).duplicate()
				pose.merge({"dragHang": 1.0, "dragFace": 1.0, "dragHeld": true, "dragTime": f / 60.0,
					"dragTilt": deg_to_rad(angle) * facing, "dragBend": deg_to_rad(5.0 * signf(angle)),
					"dragStretch": 0.135, "physicsActive": true, "facingScale": facing})
				app.pet.apply_pose(pose, 1.0 / 60)
				for node in app.pet.meshes.values():
					if not node.visible or node.self_modulate.a < 0.01: continue
					for p in app.pet.deformation.read_points(node):
						if not Rect2(Vector2(-1, -1), Vector2(root.size) + Vector2(2, 2)).has_point(app.pet.transform * app.pet.model.transform * p): clipped += 1
	check(clipped == 0, "extreme physical tilt clips viewport: " + str(clipped))
	app._menu_action(20)
	check(not app.dragging and not app.drag_motion.active() and not app.falling.active(), "reset leaves active body")
	app._save_settings()
	var saved := ConfigFile.new()
	saved.load(path)
	check(saved.get_value("pet", "auto_fall_enabled", false), "gravity setting not saved")
	print("PHYSICS HOST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
