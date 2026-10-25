extends SceneTree
const Scene = preload("res://scenes/pet.tscn")
var app
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CATCH HOST: "+words)
func run() -> void:
	var path := "res://../../_work/tests/catch-settings-%d.cfg"%Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420); cfg.set_value("pet","auto_fall_enabled",false)
	cfg.set_value("pet","auto_sit_enabled",false); cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("catch_game","best",1700); cfg.save(path)
	app = Scene.instantiate(); app.settings_path = path; root.add_child(app)
	app.set_process(false); app.set_process_input(false); root.mouse_passthrough = true
	app.bowl_window.set_process(false); app.bowl_files.set_process(false)
	check(not app.catch_score.visible,"scoreboard visible before first qualifying catch")
	check(app.catch_game.best==0,"incompatible old scoring record reused")
	check(not app.bowl_files.initialized,"fixture touched real food")
	var body = app.falling.body
	# Test actual input handlers with deterministic contact counters; native
	# collision production is separately exercised by test_catch_physics.
	app.drag_pointer = root.position+Vector2i(210,80); app._begin_grab()
	for n in range(1,41):
		app.dragging = true; app.drag_moved = true; body.linear_velocity = Vector2(700,-700); body.grounded = false
		app._finish_drag(); body.wall_sequence += 1
		app._begin_grab(); app._update_catch_game(1.0/60)
		check(app.catch_game.streak==n,"input path did not increment streak")
	check(app.catch_game.total==140 and app.catch_score.view.data.delta==41,"40th catch score/delta")
	check(app.catch_score.view.data.base_points==1 and app.catch_score.view.data.bonus==40,"view combined base +1 and streak +40")
	check(app.catch_score.visible and not app.catch_score.mouse_passthrough and app.catch_score.unfocusable,"scoreboard cannot receive double clicks or steals focus")
	check(app.catch_score.borderless and not app.catch_score.transient,"scoreboard is modal/has frame")
	app._menu_action(11)
	check(app.catch_score.always_on_top==root.always_on_top,"scoreboard ignored topmost preference")
	app._menu_action(11)
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	check(Rect2i(area).encloses(Rect2i(app.catch_score.position,app.catch_score.size)),"scoreboard escaped usable desktop")
	cfg.load(path)
	check(int(cfg.get_value("catch_game","best_per_throw",0))==140,"record not persisted on catch")
	check(int(cfg.get_value("catch_game","best",0))==1700,"old scoring record was destroyed")
	app.catch_game.deadline = Time.get_ticks_msec()/1000.0-0.01; app._update_catch_game(1.0/60)
	check(app.catch_game.total==0 and app.catch_game.best==140,"host timeout did not clear round")
	check(app.game_scores.rounds.size()==1 and int(app.game_scores.rounds[0].total)==140,"host did not save completed round")
	check(app.game_scores.rounds[0].events.size()==40,"host lost per-catch details")
	app.catch_score.board_requested.emit()
	check(app.score_board.visible and not app.score_board.exclusive and not app.score_board.transient,"score board is modal or failed to open")
	app.score_board.hide()
	# Hunger must never automatically summon a pot over an active challenge.
	app.catch_game.streak = 1; app.catch_game.phase = "caught"
	app.bowl_files.storage_ready = true; app.satiety.auto_open = true; app.satiety.resting = false
	app._update_bowl(600.0,app.catch_game.active(),Rect2(area))
	check(not app.bowl_summon.active(),"challenge allowed automatic pot summon")
	app.catch_game.finish("fixture")
	app.catch_score.hide(); app.queue_free(); await process_frame
	app = Scene.instantiate(); app.settings_path = path; root.add_child(app)
	app.set_process(false); app.set_process_input(false); app.bowl_files.set_process(false)
	check(app.catch_game.best==140 and app.catch_game.total==0 and not app.catch_score.visible,"restart restored live round/lost record")
	app.queue_free(); await process_frame
	print("CATCH HOST: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
