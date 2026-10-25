extends SceneTree
const Food = preload("res://scripts/food_item.gd")
var failures := 0
func check(ok: bool, words: String) -> void:
	if not ok: failures += 1; printerr(words)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/pet.tscn").instantiate()
	app.settings_path = ProjectSettings.globalize_path("res://../../_work/tests/bowl-hit/settings.cfg")
	DirAccess.make_dir_recursive_absolute(app.settings_path.get_base_dir())
	root.add_child(app); app.set_process(false); app.set_process_input(false)
	app.bowl_window.set_process(false)
	# Use the actual Window motion to cover fast crossings, side escape and
	# single-shot arming. Hidden test window never accepts desktop files.
	var pot = app.bowl_window
	pot.fit_pet(420)
	var hits: Array = []
	pot.struck_pet.disconnect(app._on_bowl_hit)
	pot.struck_pet.connect(func(event): hits.append(event))
	var cap := PackedVector2Array([Vector2(500,600),Vector2(620,550),Vector2(740,600)])
	pot.impact_target = func(): return {"cap":cap,"extent":420.0}
	for fps in [30,60,120]:
		for distance in [65.0,350.0]:
			hits.clear()
			pot.at = Vector2(620,550)-pot._feet()[1]-Vector2(0,distance)
			pot.velocity = 0.0; pot.arm_drop()
			for i in fps*4: pot._advance_fall(1.0/fps,Rect2(0,0,1400,1100))
			check(hits.size()==1,"one release produced missing/repeated hits")
			if hits.size()==1: check(hits[0].kind==("light" if distance<100 else "hard"),"fall classification changed with FPS")
			check(pot.at.x+pot.size.x<500 or pot.at.x>740,"pot did not escape head")
			check(pot.margin==Vector2.ZERO and pot.sprite.rotation==0.0,"native pot did not restore resting size")
	# Verify the expanded native window/input region follows every rotated edge.
	pot.at = Vector2(620,550)-pot._feet()[1]-Vector2(0,350)
	pot.velocity = 0.0; pot.arm_drop()
	var saw_rotation := false
	var saw_squash := false
	for i in 180:
		pot._advance_fall(1.0/60,Rect2(0,0,1400,1100))
		if pot.sprite.scale.y<pot.art_scale*0.95: saw_squash = true
		if pot.rebound.active():
			for point in pot.mouse_passthrough_polygon:
				check(Rect2(Vector2.ZERO,Vector2(pot.size)).has_point(point),"squashed art clipped by native window")
		if absf(pot.sprite.rotation)>0.005:
			saw_rotation = true
			for point in pot.mouse_passthrough_polygon:
				check(Rect2(Vector2.ZERO,Vector2(pot.size)).has_point(point),"rotating art clipped by native window")
	check(saw_rotation,"rebound has no visible tilt")
	check(saw_squash and pot.sprite.scale.is_equal_approx(Vector2.ONE*pot.art_scale),"squash missing or original scale not restored")
	pot.at = Vector2(620,550)-pot._feet()[1]-Vector2(0,350); pot.arm_drop()
	for i in 36: pot._advance_fall(1.0/60,Rect2(0,0,1400,1100))
	pot.place(Vector2i(100,100))
	check(not pot.rebound.active() and pot.margin==Vector2.ZERO and pot.sprite.rotation==0.0,"regrab did not immediately take control of pot")
	pot.impact_target = app._bowl_hit_target
	pot.struck_pet.connect(app._on_bowl_hit)
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(-1500,area.end.y-root.size.y)
	app.falling.cancel(); app.roaming.configure("still"); app.idle_sitting.enabled = false
	app.pet.set_seated(true); app.pet.sitting.amount = 1.0
	app.pickup.rng.seed = 104
	app.pickup.request_food([Food.from_texture(Food.DEMO_TEXTURES[0])],0,root.size.y)
	app.pickup.state = "holding"; app.pickup.age = app.pickup.CATCH_TIME+1.0
	var held = app.pickup.current
	var age: float = app.pickup.age
	app._on_bowl_hit({"kind":"light"})
	for i in 30: app._process(1.0/60)
	check(app.pickup.age==age and app.pickup.current==held,"light knock lost or consumed held food")
	check(app.pet.pickup_pose.food.visible,"held icon disappeared")
	check(app.pickup.take_finished().is_empty(),"light knock produced file completion")
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(app.settings_path.get_base_dir().path_join("light-meal.png"))
	for i in 60: app._process(1.0/60)
	check(app.pickup.age>age,"meal did not resume")
	app._on_bowl_hit({"kind":"hard"})
	app._process(1.0/60)
	check(app.landing.state=="hard","high knock did not reuse landing dizziness")
	age = app.pickup.age
	for i in 120: app._process(1.0/60)
	check(app.pickup.age==age and app.pickup.current==held,"dizziness progressed meal")
	check(app.pet.pickup_pose.food.visible,"dizziness lost held icon")
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(app.settings_path.get_base_dir().path_join("hard-meal.png"))
	for i in 100: app._process(1.0/60)
	check(not app.bowl_hit.active() and app.pickup.age>age,"hard knock did not recover")
	for i in 40: app._process(1.0/60)
	app._on_bowl_hit({"kind":"hard","dizzy_seconds":6.0})
	for i in 250: app._process(1.0/60)
	check(app.landing.active() and app.landing.pose().dizzyAlpha>0.99,"very high hit did not extend dizziness")
	var impact_age: float = app.bowl_hit.age
	var remaining: float = app.landing.dizzy_remaining()
	app._on_bowl_hit({"kind":"hard","dizzy_seconds":6.0})
	check(app.bowl_hit.age==impact_age,"second hit restarted extended dizziness")
	check(is_equal_approx(app.landing.dizzy_remaining(),remaining+6.0),"second hit did not add remaining time")
	app._on_bowl_hit({"kind":"light"})
	check(is_equal_approx(app.landing.dizzy_remaining(),remaining+9.0),"low hit did not extend existing dizziness")
	for i in 10: app._on_bowl_hit({"kind":"hard","dizzy_seconds":6.0})
	check(is_equal_approx(app.landing.dizzy_remaining(),30.0),"repeat hit cap is not 30 seconds")
	for i in 145: app._process(1.0/60)
	check(app.landing.active(),"stacked dizziness finished too early")
	for i in 1700: app._process(1.0/60)
	check(not app.bowl_hit.active() and not app.landing.active(),"extended hit did not finish")
	app._on_bowl_hit({"kind":"light"}); app._begin_grab()
	check(not app.bowl_hit.active(),"regrab did not interrupt reaction")
	app.falling.cancel(); app.queue_free(); await process_frame
	print("Bowl hit host: ",failures," failures")
	quit(1 if failures else 0)
