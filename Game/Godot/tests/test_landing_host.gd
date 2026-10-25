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
		if failures < 15: printerr("LANDING HOST: " + message)
func tick(count: int = 1) -> void:
	for f in count:
		var held: bool = app.dragging
		app.dragging = false # Synthetic test input; don't poll the real mouse.
		app._process(1.0 / 60)
		app.dragging = held
		await process_frame
func drop(height: float, velocity: Vector2 = Vector2.ZERO) -> void:
	app.landing.cancel()
	app.drag_motion.cancel()
	app.falling.cancel()
	app.dragging = false
	app.pet.set_seated(false)
	app.pet.sitting.amount = 0.0
	app.pet.sitting.velocity = 0.0
	app.idle_sitting.manual_pose()
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x + 400, area.end.y - root.size.y * (1.0 + height))
	app.falling.reposition(Vector2(root.position))
	app._process(1.0 / 60)
	app.falling.body.linear_velocity = velocity
func wait_impact() -> void:
	for f in 150:
		if app.landing.active(): return
		check(not app.pet.sitting.seated, "sat before touching ground")
		await tick()
	check(false, "no landing animation")
func run() -> void:
	var path := "res://../../_work/tests/landing-host-settings.cfg"
	var settings := ConfigFile.new()
	settings.set_value("window", "size", 420)
	settings.set_value("pet", "auto_fall_enabled", true)
	settings.set_value("pet", "roaming_mode", "off")
	settings.set_value("pet", "auto_sit_enabled", false)
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
	drop(0.15)
	await wait_impact()
	check(app.landing.state == "soft", "low landing wrong tier")
	await tick(160)
	check(not app.pet.sitting.seated and not app.landing.active(), "low landing did not return to standing")
	drop(1.2)
	await wait_impact()
	check(app.landing.state == "hard", "high landing wrong tier")
	await tick(21)
	check(app.pet.sitting.amount >= 0.95, "host missed faster impact sitting")
	check(app.pet.sitting.seated and app.idle_sitting.automatically_seated, "hard landing failed to seat as automatic rest")
	check(app.pet.landing_pose.sprites[0].visible and app.roaming.state == "idle", "dizzy overlay/activity conflict")
	app._register_interaction(false)
	check(app.pet.sitting.seated, "passing pointer woke dizzy pet")
	app._menu_action(14)
	await tick(2)
	var before_age: float = app.landing.age
	await tick(40)
	check(app.landing.age>before_age and app.pet.sitting.amount>=0.95, "settings froze dizziness")
	app.settings_window.hide()
	await tick(180)
	check(not app.landing.active() and not app.pet.landing_pose.sprites[0].visible, "dizzy failed to recover")
	check(app.pet.sitting.seated and app.idle_sitting.automatically_seated, "recovery lost seated rest")
	app.roaming.configure("free")
	app.roaming.rest_remaining = 0.01
	await tick(2)
	check(not app.pet.sitting.seated, "activity mode could not wake recovered pet")
	app.roaming.configure("off")
	# Fast downward release close to the ground must also absorb a hard impact.
	drop(0.1, Vector2(0, 2200))
	await wait_impact()
	check(app.landing.state == "hard", "fast low throw ignored impact speed")
	await tick(24)
	app.dragging = true
	app.drag_moved = true
	app.drag_pointer = root.position + Vector2i(app.pet.physics_anchor())
	app.drag_window = root.position
	app._begin_grab()
	await tick(10)
	check(not app.landing.active() and not app.pet.sitting.seated, "regrab didn't interrupt dizziness")
	check(not app.pet.landing_pose.sprites[0].visible and app.drag_motion.face > 0.9, "dizzy/drag faces overlap")
	app._menu_action(20)
	check(not app.landing.active() and not app.falling.active(), "reset didn't cancel landing/physics")
	print("LANDING HOST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
