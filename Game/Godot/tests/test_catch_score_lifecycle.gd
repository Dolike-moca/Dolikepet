extends SceneTree
const Challenge = preload("res://scripts/catch_challenge.gd")
const Score = preload("res://scripts/catch_score_window.gd")
var checks := 0
var failures := 0
var opened := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("SCORE LIFECYCLE: "+words)
func run() -> void:
	root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	var score = Score.new(); score.use_pointer_override = true; root.add_child(score)
	score.board_requested.connect(func(): opened += 1)
	var game = Challenge.new()
	score.refresh(game.snapshot(0),0,root.current_screen)
	check(not score.visible,"appeared without score")
	game.released(0,0,0,700,420); game.caught(1,1,0,false,true)
	score.refresh(game.snapshot(3.9),0.1,root.current_screen)
	check(score.visible and score.view.fade==1.0,"active challenge faded before its end")
	game.advance(4,1,0)
	for time in [4.0,5.0,7.0,8.0,8.5]:
		score.refresh(game.snapshot(time),0.1,root.current_screen)
		check(is_equal_approx(score.view.fade,game.opacity(time)),"five second fade differs")
	check(score.view.data.total==1 and score.view.data.streak==1 and game.total==0,"ended score display lost result or round not reset")
	var before: float = score.view.fade
	score.pointer_override = Vector2(40,60)
	score.refresh(game.snapshot(8.5),0.1,root.current_screen)
	check(is_equal_approx(score.view.fade,before),"hover snapped immediately opaque")
	score.refresh(game.snapshot(8.6),0.1,root.current_screen)
	check(score.view.fade>before and score.view.fade<1.0,"hover restore is not smooth")
	score.refresh(game.snapshot(8.7),0.1,root.current_screen)
	check(is_equal_approx(score.view.fade,1.0),"hover restore did not reach full alpha")
	score.refresh(game.snapshot(30),0.1,root.current_screen)
	check(score.visible and score.view.fade==1.0,"hover expired")
	check(not game.active(),"hover restarted gameplay timer")
	var click := InputEventMouseButton.new(); click.pressed = true; click.button_index = MOUSE_BUTTON_LEFT; click.position = Vector2(60,60)
	score.window_input.emit(click); check(opened==0,"single click opened board")
	click.double_click = true; score.window_input.emit(click); check(opened==1,"double click did not open board")
	click.position = Vector2(1,1); score.window_input.emit(click); check(opened==1,"transparent margin catches clicks")
	check(score.mouse_passthrough_polygon.size()==4 and not score.mouse_passthrough,"native region missing")
	score.pointer_override = Vector2(-10,-10)
	score.refresh(game.snapshot(30.1),0.1,root.current_screen)
	score.refresh(game.snapshot(34.1),0.1,root.current_screen)
	check(is_equal_approx(score.view.fade,0.5),"leaving did not restart five seconds")
	await process_frame; await RenderingServer.frame_post_draw
	var image: Image = score.get_texture().get_image()
	check(absf(image.get_pixel(20,100).a-0.5)<0.02,"actual panel alpha differs")
	score.refresh(game.snapshot(35.1),0.1,root.current_screen)
	check(not score.visible and score.get_window_id()==DisplayServer.INVALID_WINDOW_ID,"expired native window not closed")
	score.pointer_override = Vector2(40,60)
	score.refresh(game.snapshot(36),0.1,root.current_screen)
	check(not score.visible,"moving over expired window reopened it")
	game.released(40,1,0,700,420)
	score.refresh(game.snapshot(40),0.1,root.current_screen)
	check(not score.visible,"unscored throw reopened old result")
	game.caught(41,2,0,false,true); score.refresh(game.snapshot(41),0.1,root.current_screen)
	check(score.visible and score.view.fade==1.0,"new catch did not open panel")
	score.pointer_override = Vector2(-10,-10)
	# Update once outside before simulating a long suspended render frame.
	score.refresh(game.snapshot(41.1),0.1,root.current_screen)
	game.advance(60,2,0); score.refresh(game.snapshot(60),0.1,root.current_screen)
	check(not score.visible,"stalled frame extended hidden time")
	score.queue_free(); await process_frame
	print("SCORE LIFECYCLE: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
