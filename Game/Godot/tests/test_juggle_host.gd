extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
const Behavior = preload("res://scripts/pet_behavior.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("JUGGLE HOST: "+label)
func run() -> void:
	var fixture := ProjectSettings.globalize_path("res://../../_work/tests/juggle-host-%d"%Time.get_ticks_usec())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixture = arg.trim_prefix("--fixture=")
	DirAccess.make_dir_recursive_absolute(fixture)
	var path := fixture.path_join("settings-%d.cfg"%Time.get_ticks_usec())
	var cfg := ConfigFile.new(); cfg.set_value("window","size",420)
	cfg.set_value("pet","auto_fall_enabled",false); cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("pet","auto_sit_enabled",false); cfg.set_value("bowl","visible",false); cfg.save(path)
	var app = Scene.instantiate(); app.settings_path = path; root.add_child(app)
	app.set_process(false); app.set_process_input(false); app.bowl_files.set_process(false)
	root.mouse_passthrough = true; root.position = Vector2i(350,350)
	var pot = app.bowl_window; pot.set_process(false); pot.show()
	var area := Rect2(DisplayServer.screen_get_usable_rect(root.current_screen))
	var b = Behavior.new(); b.automatic_blinks = false
	var base: Dictionary = b.update(0,Vector2.ZERO,Vector2.ZERO,420,false).duplicate()
	base.motionReset = true
	app.pet.apply_pose(base,1.0/60)
	var target: Dictionary = app._bowl_hit_target()
	check(not target.juggle,"stationary ordinary hit auto-started")
	app.dragging = true; app.drag_moved = false
	check(app._bowl_hit_target().is_empty(),"unmoved click started juggle")
	app.drag_moved = true
	target = app._bowl_hit_target(); check(target.juggle,"actively moved cat cannot receive pot")
	var crown := Rect2(target.cap[0],Vector2.ZERO)
	for point in target.cap: crown = crown.expand(point)
	pot.place(Vector2i(crown.get_center().x-pot.rest_size.x*0.5,crown.position.y-pot.rest_size.y-25))
	pot.velocity = 1000.0; pot.arm_drop()
	for i in 12:
		pot._advance_fall(1.0/120,area)
		if app.juggle_game.active(): break
	check(app.juggle_game.active() and pot.juggle.active(),"real silhouette/crown did not start juggle")
	check(app.juggle_game.total==1 and app.score_game=="juggle","first contact did not score/switch panel")
	check(not app.bowl_hit.active() and not app.landing.active(),"normal stun interrupted game")
	app._update_catch_game(1.0/60)
	check(app.catch_score.view.data.game=="juggle" and app.catch_score.visible,"shared green score not selected")
	# Apply actual limp pose and compare crown against what the renderer uses.
	var p := base.duplicate(); p.dragHeld = true; p.dragHang = 1.0; p.dragFace = 1.0
	for i in 50:
		p = app.juggle_motion.prepare(base,1.0/60,true,true,2.0)
		p.dragHeld = true; app.pet.apply_pose(p,1.0/60)
	check(app.pet.landing_pose.sprites[0].visible and app.pet.landing_pose.sprites[0].modulate.a>0.99,"held cat lacks dizzy eyes")
	check(not app.pet.drag_pose.sprites[0].visible,"squeezed eyes cover dizzy eyes")
	target = app._bowl_hit_target()
	var rendered: PackedVector2Array = app.pet.crown_cap()
	for i in rendered.size(): check(rendered[i]+Vector2(root.position)==target.cap[i],"hit crown differs from rendered crown")
	# A moving/regrabbed cat must keep this round, never start the throw game.
	app.drag_pointer = root.position+Vector2i(180,100); app._begin_grab()
	check(app.juggle_game.active() and not app.catch_game.active(),"regrab switched games")
	app._finish_drag()
	check(app.juggle_game.active() and app.catch_game.phase=="idle","release created throw challenge")
	app.dragging = true; app.drag_moved = true
	# Real high-speed collision with two prior wall bounces.
	crown = Rect2(target.cap[0],Vector2.ZERO)
	for point in target.cap: crown = crown.expand(point)
	var f = pot.juggle; f.state = "flight"; f.angle = 0.0
	f.center = Vector2(crown.get_center().x,crown.position.y-f.bounds().end.y-25)
	f.velocity = Vector2(0,4000); f.boosted = true; f.walls = 2; f.armed = true; f.separated = true; f.last_cap.clear()
	for i in 5:
		pot._advance_fall(1.0/120,area)
		if app.juggle_game.streak==2: break
	check(app.juggle_game.total==29 and app.juggle_game.base_points==28,"real boosted rebound score")
	check(app.game_scores.current.events[-1].blessing=="慈父的赐福","blessing not recorded")
	# Only actual ground contact ends the game; hover/spin never uses a timer.
	f.state = "flight"; f.angle = 0; f.center = Vector2(area.get_center().x,area.end.y-f.bounds().end.y-1)
	f.velocity = Vector2(0,1000); f.armed = false
	pot._advance_fall(1.0/60,area)
	check(not app.juggle_game.active() and not f.active(),"ground failed to finish")
	check(f.animating() and f.state=="settle","ground skipped residual hop/roll")
	check(app.game_scores.rounds.size()==1 and int(app.game_scores.rounds[0].total)==29,"round not persisted")
	var end: float = app.juggle_game.ended_at
	check(app.juggle_game.snapshot(end+4.9).shown and not app.juggle_game.snapshot(end+5).shown,"end fade not five seconds")
	check(not app.bowl_files.initialized,"test accessed real food")
	for frame in 600: pot._advance_fall(1.0/120,area)
	check(not f.animating() and absf(pot.sprite.rotation)<0.001,"native pot failed to settle upright")
	check(app.game_scores.rounds.size()==1 and app.juggle_game.ended_at==end,"settling created another round/end time")
	app.falling.state = "held"; app.falling.body.linear_velocity = Vector2(190,-250); app.falling.body.angular_velocity = 0.0
	target = app._bowl_hit_target()
	check(target.velocity.distance_to(Vector2(190,-250))<0.01,"target uses cursor instead of physical body velocity")
	app.falling.body.linear_velocity = Vector2.ZERO
	# User interception cancels both the physical game and its record.
	var polygon := PackedVector2Array()
	for point in pot.silhouette: polygon.append(point-Vector2(pot.rest_size)*0.5)
	f.start(Vector2(500,300),Vector2(pot.rest_size),polygon,area); app._on_juggled({"walls":0,"boosted":false})
	pot.end_juggle("拿起饭盆 · 本轮结束")
	check(not app.juggle_game.active() and not f.active() and app.game_scores.rounds.size()==2,"manual pot grab failed to finish once")
	# Intercepting the post-game rolling pot clears motion without a duplicate end.
	f.state = "settle"; f.angle = 0.8; f.velocity = Vector2(25,0)
	pot.end_juggle("拿起收尾中的饭盆")
	check(not f.animating() and app.game_scores.rounds.size()==2,"interrupted settling recorded twice")
	app.queue_free(); await process_frame
	print("JUGGLE HOST: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
