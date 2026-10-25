extends SceneTree
const Scores = preload("res://scripts/game_scores.gd")
const Board = preload("res://scripts/score_board.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("SCORE BOARD: "+words)
func run() -> void:
	root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	var out := ProjectSettings.globalize_path("res://../../_work/tests/score-board-%d"%Time.get_ticks_usec())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var store = Scores.new(); store.configure(out.path_join("history.json"),75)
	# Synthetic records live only in this explicitly isolated fixture.
	store.rounds.clear(); store.current.clear()
	for round_id in 65:
		var game := "juggle" if round_id%2==0 else "catch"
		var total := 0
		for i in range(1,21):
			var multiplier := 7 if game=="juggle" and i%3==0 else 1
			var walls := (i+round_id)%3+1; var base := walls*walls*multiplier
			var bonus := i if i%10==0 else 0; total += base+bonus
			store.record_award({"game":game,"at":round_id*70+i*2.0,"streak":i,"base":base,"bonus":bonus,
				"walls":walls,"multiplier":multiplier,"delta":base+bonus,"total":total})
		store.finish_round({"at":round_id*70+45.0,"reason":"锅落地 · 本轮结束" if game=="juggle" else "没接住 · 本轮结束"})
		store.rounds[-1].ended = 1792848000+round_id*70
	var board = Board.new(); root.add_child(board); board.bind(store); board.open_board(root.current_screen)
	check(board.visible and not board.exclusive and not board.transient,"board blocked parent")
	check(board.rows.item_count==50 and not board.next.disabled,"history not paginated")
	board.next.pressed.emit(); check(board.rows.item_count==15 and board.next.disabled,"second page missing")
	board.previous.pressed.emit(); check(board.rows.item_count==50,"previous page failed")
	board.game_filter.select(2); board.game_filter.item_selected.emit(2)
	check(board.listed.size()==33 and board.rows.item_count==33,"game filter mixed records")
	check(board.details.text.contains("高速 ×7") and board.details.text.contains("连击 +20"),"detail awards missing")
	board.sort_filter.select(1); board.sort_filter.item_selected.emit(1)
	check(board.listed[0].total>=board.listed[-1].total,"score sort failed")
	check(board.chart.values.size()==20,"per-round chart missing")
	await process_frame; await RenderingServer.frame_post_draw
	board.get_texture().get_image().save_png(out.path_join("recent.png"))
	board.tabs.current_tab = 1; board.game_rank.select(1); board.game_rank.item_selected.emit(1)
	check(board.ranking.text.contains("10    ") and board.stats.text.contains("33 局"),"top ten/statistics incomplete")
	check(board.trend.values.size()==30,"recent thirty trend missing")
	await process_frame; await RenderingServer.frame_post_draw
	board.get_texture().get_image().save_png(out.path_join("records.png"))
	board.mode = Window.MODE_MINIMIZED; await process_frame
	board.open_board(root.current_screen); check(board.mode==Window.MODE_WINDOWED,"minimized board not restored")
	board.close_requested.emit(); check(not board.visible,"board close quits/blocks host")
	board.open_board(root.current_screen); check(board.visible,"board failed to reopen")
	board.size = Vector2i(720,600); await process_frame; await RenderingServer.frame_post_draw
	board.get_texture().get_image().save_png(out.path_join("compact.png"))
	board.queue_free(); await process_frame
	print("SCORE BOARD: %d checks, %d failures; %s"%[checks,failures,out]); quit(0 if failures==0 else 1)
