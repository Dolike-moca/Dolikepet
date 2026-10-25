extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("MENU IDLE: " + message)
func tick(count: int = 1) -> void:
	for f in count:
		app._process(1.0 / 60)
		await process_frame
func pointer() -> Vector2i:
	return Vector2i(app.falling.body.position.round()) if app.falling.active() else root.position + Vector2i(root.size.x / 2, root.size.y / 3)
func dismiss() -> void:
	app.menu.hide()
	await tick(2)
func stage(height: float, gravity: bool) -> void:
	app.menu.hide()
	app.settings_window.hide()
	app.menu_holding = false
	app.dragging = false
	app.drag_motion.cancel()
	app.falling.cancel()
	app.landing.cancel()
	app.falling.configure(gravity)
	app.roaming.configure("off")
	app.pet.set_seated(false)
	app.pet.sitting.amount = 0.0
	app.pet.sitting.velocity = 0.0
	app.idle_sitting.manual_pose()
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x + 400, area.end.y - root.size.y * (1.0 + height))
	app.falling.reposition(Vector2(root.position))
func run() -> void:
	var path := "res://../../_work/tests/menu-idle-settings.cfg"
	var settings := ConfigFile.new()
	settings.set_value("window", "size", 420)
	settings.set_value("pet", "auto_fall_enabled", false)
	settings.set_value("pet", "roaming_mode", "off")
	settings.set_value("pet", "auto_sit_enabled", true)
	settings.set_value("pet", "auto_sit_min_seconds", 5)
	settings.set_value("pet", "auto_sit_max_seconds", 5)
	settings.save(path)
	app = Scene.instantiate()
	app.settings_path = path
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	root.mouse_passthrough = true
	app.bubble.hide()
	check(app.pet.available, app.pet.failure)
	if not app.pet.available: quit(1); return
	stage(0.0, false)
	await tick(3)
	app.roaming.configure("free")
	app.roaming.state = "walking"
	app.roaming.facing = 1
	app.roaming.facing_scale = -1.0
	app.roaming.travel_position = Vector2(root.position)
	app.roaming.speed = root.size.x * 0.18
	app.roaming.weight = 1.0
	app.roaming.cadence = 1.7
	var at := root.position
	var before_time: float = app.behavior.time
	var before_tail: float = app.pet.tail.time
	var phase: float = app.roaming.phase
	app._open_menu(pointer())
	check(app.roaming.state == "menu_stopping" and not app.menu_holding, "ground walk did not begin a soft stop")
	await tick(45)
	check(app.menu.visible, "menu disappeared while stopping")
	check(root.position.x > at.x and root.position.x - at.x < root.size.x * 0.03, "ground braking stopped abruptly or travelled too far")
	check(app.roaming.speed == 0.0 and app.roaming.weight == 0.0 and app.roaming.phase > phase, "gait froze instead of settling")
	check(app.behavior.time > before_time + 0.7 and app.pet.tail.time > before_tail + 0.7, "menu paused idle animation")
	check(not app.falling.paused and app.idle_sitting.elapsed == 0.0, "menu paused physics or advanced auto rest")
	at = root.position
	await tick(40)
	check(root.position == at, "ground pet resumed walking in menu")
	await dismiss()
	check(app.roaming.wait_remaining > 3.0, "closing menu resumed an expired walking deadline")
	# Opening a menu must preserve automatic seated rest, not count as a wake.
	app.pet.set_seated(true)
	app.pet.sitting.amount = 1.0
	app.pet.sitting.velocity = 0.0
	app.idle_sitting.automatically_seated = true
	app._open_menu(pointer())
	await tick(15)
	check(app.pet.sitting.seated and app.idle_sitting.automatically_seated, "opening menu woke seated pet")
	await dismiss()
	check(app.pet.sitting.seated and app.roaming.rest_remaining > 5.0, "seated rest did not restart after menu")
	# Native free-flight velocity is carried into a stationary spring grab.
	stage(1.0, true)
	await tick(2)
	app.falling.body.linear_velocity = Vector2(450, 350)
	app.falling.body.rotation = deg_to_rad(12.0)
	app.falling.body.angular_velocity = 0.8
	var position_before: Vector2 = app.falling.body.position
	var velocity_before: Vector2 = app.falling.body.linear_velocity
	var spin_before: float = app.falling.body.angular_velocity
	var pin := pointer()
	app._open_menu(pin)
	check(app.menu_holding and app.falling.state == "held" and app.drag_motion.state == "held", "air menu did not catch pet")
	check(app.falling.body.position == position_before and app.falling.body.linear_velocity == velocity_before \
		and app.falling.body.angular_velocity == spin_before, "menu catch teleported or discarded momentum")
	before_time = app.drag_motion.time
	before_tail = app.pet.tail.time
	await tick(20)
	check(not app.falling.paused and not app.falling.body.freeze, "menu hold froze native simulation")
	check(app.drag_motion.face > 0.95 and app.pet.tail.group_count > 0, "suspended expression/tail did not run")
	check(app.drag_motion.time > before_time + 0.3 and app.pet.tail.time > before_tail + 0.3, "held animation clocks paused")
	check(app.falling.body.position.distance_to(position_before) > 2.0, "spring never absorbed incoming movement")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50, 20)
	app._input(motion)
	app._update_drag_pointer(pin + Vector2i(300, 100), true)
	check(app.falling.body.pointer == Vector2(pin), "menu cursor dragged the suspended pet")
	await tick(100)
	check(app.menu.visible and app.menu_holding and app.falling.state == "held", "suspended menu pet fell or lost menu")
	check(app.falling.body.linear_velocity.length() < 12.0 and app.falling.body.spring_gap.length() < 12.0, "menu suspension did not settle")
	var settled := app.falling.body.position as Vector2
	await tick(20)
	check(app.falling.body.position.distance_to(settled) < 1.0, "stationary menu pin drifted after settling")
	app._menu_action(12)
	check(app.manual_sit_pending and not app.pet.sitting.seated, "menu sit did not wait for release and floor contact")
	await dismiss()
	check(not app.menu_holding and app.falling.state == "falling", "dismissing menu left invisible grab")
	check(absf(app.falling.body.linear_velocity.x) < 40.0, "closing menu restored the old throw")
	await tick(10)
	check(app.falling.body.linear_velocity.y > 30.0, "gravity did not resume after menu")
	await tick(130)
	check(not app.manual_sit_pending and app.pet.sitting.seated and not app.idle_sitting.automatically_seated,
		"menu-requested sitting was lost during release/landing")
	# Existing left-hand suspension passes ownership without resetting attachment.
	stage(1.0, true)
	app.drag_pointer = root.position + Vector2i(app.pet.physics_anchor())
	app._begin_grab()
	app.dragging = true
	app.drag_moved = true
	app.drag_motion.age = 0.5
	var attachment: Vector2 = app.falling.body.attachment
	app._open_menu(app.drag_pointer)
	check(not app.dragging and app.menu_holding and app.falling.body.attachment == attachment \
		and app.drag_motion.age == 0.5, "right-click restarted the existing pickup")
	await tick(10)
	# Opening/minimizing an independent settings draft must release the menu pin.
	app.menu.hide()
	app._menu_action(14)
	await tick(2)
	settled = app.falling.body.position
	app.settings_window.mode = Window.MODE_MINIMIZED
	await tick(15)
	check(not app.menu_holding and not app.falling.paused and app.falling.body.position.distance_to(settled)>1.0, "minimized settings froze the pet")
	app.settings_window.hide()
	await tick(3)
	check(not app.menu_holding and not app.falling.paused, "settings close retained menu ownership")
	# A floor animation already in progress finishes under the open menu.
	stage(1.2, true)
	for f in 120:
		await tick()
		if app.landing.active(): break
	check(app.landing.state == "hard", "no hard landing for menu regression")
	app._open_menu(pointer())
	var age: float = app.landing.age
	await tick(25)
	check(not app.menu_holding and app.landing.age > age + 0.3 and app.pet.sitting.amount > 0.95, "menu caught grounded pet or froze impact collapse")
	await tick(170)
	check(app.menu.visible and not app.landing.active() and app.pet.sitting.seated \
		and not app.pet.landing_pose.sprites[0].visible, "dizzy landing/recovery froze in menu")
	await dismiss()
	# Gravity-disabled hover is caught too, then softly returns to hovering.
	stage(0.8, false)
	app._open_menu(pointer())
	await tick(60)
	at = root.position
	await dismiss()
	await tick(80)
	check(not app.menu_holding and not app.falling.active() and root.position.distance_to(at) < 10.0, "disabled gravity unexpectedly dropped after menu")
	app._open_menu(pointer())
	await tick(3)
	app._menu_action(20)
	app.menu.hide()
	check(not app.menu_holding and not app.falling.active() and not app.drag_motion.active(), "reset retained a menu grab")
	print("MENU IDLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
