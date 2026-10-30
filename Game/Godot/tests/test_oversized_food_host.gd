extends SceneTree
## Real pet/meal coordinator, fake worker completion, files only in _work.
const Scene = preload("res://scenes/pet.tscn")
const Food = preload("res://scripts/food_item.gd")
const MB := 1048576
var app
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("OVERSIZED HOST: fixture timeout"); quit(1))
	call_deferred("run")

func tick(count: int) -> void:
	for frame in count:
		app._process(1.0 / 60.0)
		if frame % 12 == 11: await process_frame

func run() -> void:
	var base := ProjectSettings.globalize_path("res://../../_work/tests/oversized-food-host/%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(base)
	var cfg := ConfigFile.new()
	cfg.set_value("window","size",420)
	cfg.set_value("pet","auto_fall_enabled",false)
	cfg.set_value("pet","auto_sit_enabled",false)
	cfg.set_value("pet","roaming_mode","off")
	cfg.set_value("bowl","visible",false)
	cfg.set_value("stomach","capacity_bytes",100 * MB)
	var settings_path := base.path_join("pet.cfg")
	cfg.save(settings_path)
	app = Scene.instantiate(); app.settings_path = settings_path
	root.add_child(app); app.set_process(false); app.set_process_input(false)
	root.mouse_passthrough = true
	app.bowl_window.set_process(false); app.bowl_files.set_process(false)
	app.bowl_summon.finish(); app.bowl_jump.cancel(); app.behavior.command("normal")
	app.roaming.configure("off"); app.roaming.weight = 0.0
	check(app.pet.available, "accepted pet model failed to load")
	check(app.bowl_files.helper.is_empty() and app.bowl_files.jobs.is_empty(), "fixture unexpectedly started a native user-data worker")
	if not app.pet.available: finish(); return
	var files = app.bowl_files
	files.initialized = true; files.storage_ready = true
	files.smallest_bytes = 500 * MB
	for spec in [["oldest",900],["smallest",500]]:
		var token: String = spec[0]
		var path := base.path_join(token + ".txt")
		var stream := FileAccess.open(path,FileAccess.WRITE)
		stream.store_string("Generated fixture; size metadata is simulated without a real worker.")
		stream.close()
		files.entries.append({"path":path,"token":token,"bytes":int(spec[1])*MB,"ready":true,"icon":"","label":token})
		files.stable[token] = true; files.textures[token] = Food.DEMO_TEXTURES[0]
	var first: Array = files.food_items()
	check(first.size() == 1 and first[0].source.token == "oldest", "host did not select just the oldest oversized file")
	if first.is_empty(): finish(); return
	var item = first[0]
	app.satiety.resting = true; app._observe_stomach()
	check(not app.satiety.resting and app._food_available(item), "host did not reopen a hungry oversized meal")
	files.smallest_bytes = 100 * MB
	check(not app._food_available(item), "host ignored a fitting file in the complete snapshot")
	files.smallest_bytes = 500 * MB
	files.pending["another"] = 1
	check(not app._food_available(item), "host treated reserved bytes plus a large file as one exception")
	files.pending.clear(); files.pending["empty-pending"] = 0
	check(not app._food_available(item), "host ignored a zero-byte pending meal")
	files.pending.clear()
	var held = Food.from_texture(Food.DEMO_TEXTURES[0],"held")
	held.source = {"token":"held","bytes":1}
	app.pickup.current = held
	check(not app._food_available(item), "host allowed an oversized meal while holding another item")
	app.pickup.current = null
	files.stomach_bytes = 50 * MB; app._observe_stomach()
	check(not app._food_available(item), "host allowed oversized food at fifty percent fullness")
	files.stomach_bytes = 49 * MB; app._observe_stomach()
	check(not app.satiety.resting and app._food_available(item), "host did not recover strictly below fifty percent")
	files.stomach_bytes = 0; app._observe_stomach()
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x + 600,area.end.y - 420)
	app.falling.reposition(Vector2(root.position))
	app.bowl_window.place(Vector2i(root.position.x+15,area.end.y-app.bowl_window.size.y))
	app.bowl_window.show(); app.bowl_window.mouse_passthrough = true
	await tick(240)
	check(app.pickup.current != null and app.pickup.current.source.token == "oldest", "actual nearby-bowl pickup did not begin the oversized file")
	check(app.pickup.foods.is_empty() and files.jobs.is_empty(), "oversized meal queued a second file or swallowed before chewing finished")
	if app.pickup.current != null:
		app.pickup.age = app.pickup.food_end + app.pickup.tail_time - 0.01
		await tick(3)
	check(files.jobs.size() == 1 and files.jobs[0].action == "swallow" and files.jobs[0].token == "oldest", "completion did not submit exactly the oldest oversized file")
	check(FileAccess.file_exists(item.source.path), "host directly altered food before the worker reply")
	if files.jobs.size() == 1:
		files.running = files.jobs.pop_front()
		files._finish({"ok":true,"stomach_bytes":900*MB})
		files.running = {}
	check(app.satiety.used == 900 * MB and app.satiety.resting, "worker completion did not retain actual over-capacity usage and rest")
	app._update_satiety_menu()
	check(app.satiety_bar.value == 100.0 and app.menu.get_item_text(app.menu.get_item_index(30)) == "饱食度 100.0%", "menu did not cap oversized satiety at one hundred percent")
	var actual_usage := String.humanize_size(900 * MB) + " / " + String.humanize_size(100 * MB)
	check(app.settings_window.fullness_label.text == "100.0%" and app.settings_window.stomach_usage.text.begins_with(actual_usage), "settings lost actual food bytes or displayed over-one-hundred percent")
	await tick(60)
	check(not app.pickup.active() and files.jobs.is_empty() and files.food_items().is_empty(), "full oversized meal started another pickup or swallow")
	check(app.bubble_label.text == "吃饱了" and not app.satiety.full_pending, "oversized meal did not complete the existing satisfied reaction")
	var reaction: float = app.behavior.reaction_until
	app._observe_stomach(); await tick(10)
	check(app.behavior.reaction_until == reaction, "re-observing over-capacity usage replayed the full reaction")
	files.stomach_bytes = 0; files.smallest_bytes = 500 * MB; app._observe_stomach()
	check(not app.satiety.resting and files.food_items().size() == 1, "digestion did not make the next single oversized meal eligible")
	finish()

func finish() -> void:
	if is_instance_valid(app): app.queue_free()
	for failure in failures: printerr("OVERSIZED HOST: " + failure)
	print("Oversized food host: ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
