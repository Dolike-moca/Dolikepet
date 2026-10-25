extends SceneTree
const Pickup = preload("res://scripts/pickup_motion.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Scene = preload("res://scenes/pet.tscn")
var checks := 0
var failures := 0
var samples: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("HANDOFF: "+message)

func timing(fps: int, seed_value: int) -> void:
	var motion = Pickup.new()
	motion.rng.seed = seed_value
	motion.request(100,600)
	motion.state = "holding"
	motion.age = Pickup.CATCH_TIME+motion.admire_duration+motion.bite_duration*0.45
	var b = Behavior.new()
	b.automatic_blinks = false
	b.chewing.rng.seed = seed_value
	var started := 0
	var first_motion := -1.0
	var prior := Vector2.ZERO
	var largest_speed := 0.0
	for frame in fps*2:
		var p: Dictionary = motion.update(1.0/fps)
		if motion.take_eat_request():
			started += 1
			check(p.biteOpen == 0.0,"chewing began with an open jaw")
			b.command("chew",p.biteChewAge)
		var pose: Dictionary = b.update(1.0/fps,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
		pose.merge(p)
		if started > 0:
			check(absf(b.chewing.age-p.biteChewAge)<0.00001,"pickup and chew clocks diverged")
			check(absf(p.biteAlpha+pose.chewAlpha-1.0)<0.00001,"handoff leaves a gap or doubles its mouth weights")
			largest_speed = maxf(largest_speed,prior.distance_to(pose.chewOffset)*fps)
			prior = pose.chewOffset
			if first_motion < 0.0 and pose.chewOffset.length() > 0.05:
				first_motion = motion.age-Pickup.CATCH_TIME-motion.admire_duration-motion.bite_duration*Pickup.Bite.CLOSED
			if frame == int(fps*0.4):
				var held_age: float = b.chewing.age
				var held_offset: Vector2 = pose.chewOffset
				for pause_frame in 5:
					motion.update(1.0/fps,true,true)
					b.update(1.0/fps,Vector2.ZERO,Vector2.ZERO,600,false,true)
				check(b.chewing.age == held_age and b.values.chewOffset == held_offset,"pause advanced the handoff")
		if fps == 60 and seed_value == 20261022: samples.append(pose)
	check(started == 1,"chew event did not occur exactly once")
	check(first_motion > 0.0 and first_motion < 0.18,"closed mouth waits too long before the first gentle chew")
	check(largest_speed < 80.0,"first chew jumps instead of easing in")
	motion.cancel(true)
	b.command("normal")
	for frame in fps/4: b.update(1.0/fps,Vector2.ZERO,Vector2.ZERO,600,false)
	check(b.chewing.pose().chewAlpha == 0.0 and motion.pose().biteAlpha == 0.0,"cancel left either mouth visible")

func run() -> void:
	for fps in [30,60,120]:
		for seed_value in [20261022,9051,4302]: timing(fps,seed_value)
	if DisplayServer.get_name() == "headless": finish(); return
	root.size = Vector2i(600,600)
	root.position = Vector2i(24,24)
	root.mouse_passthrough = true
	var pet = Pet.new()
	root.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))),pet.failure)
	if not pet.available: finish(); return
	var max_step := 0.0
	var max_native := 0.0
	var max_registration := 0.0
	for size in [240,600,800]:
		pet.fit(Vector2.ONE*size)
		for facing in [-1.0,1.0]:
			var previous := Vector2.ZERO
			var previous_visible := false
			for i in samples.size():
				var pose := samples[i].duplicate()
				pose.facingScale = facing
				pose.motionReset = i == 0
				pet.apply_pose(pose,1.0/60.0)
				if pose.biteChewAge >= 0.0:
					max_native = maxf(max_native,pet.meshes.ArtMesh4.self_modulate.a)
					max_native = maxf(max_native,pet.meshes.ArtMesh3.self_modulate.a)
					if pet.bite_face.mouth.visible and pet.chewing_pose.sprite.visible:
						var center: Vector2 = pet.bite_face.mouth.global_transform*pet.bite_face.closed_center
						max_registration = maxf(max_registration,center.distance_to(pet.chewing_pose.sprite.global_position))
					var now: Vector2 = pet.chewing_pose.sprite.global_position
					if previous_visible: max_step = maxf(max_step,now.distance_to(previous)*600.0/size)
					previous = now
					previous_visible = true
	check(max_native < 0.00001,"default mouth flashes through the blend")
	check(max_registration < 0.002,"the two mouths do not share a center during the blend")
	check(max_step < 0.8,"rendered mouth jumps during handoff/first chew: "+str(max_step))
	print("HANDOFF native mouth alpha ",max_native,"; registration ",max_registration,"; max 60Hz step at 600px ",max_step)
	pet.queue_free()
	await process_frame
	# Exercise the actual menu/runtime route, not just the standalone motions.
	var path := "res://../../_work/tests/bite-handoff-test-settings.cfg"
	var settings := ConfigFile.new()
	settings.set_value("pet","auto_fall_enabled",false)
	settings.set_value("window","size",600)
	settings.save(path)
	var app = Scene.instantiate()
	app.settings_path = path
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app._start_pickup_demo()
	app.pickup.state = "holding"
	app.pickup.age = Pickup.CATCH_TIME+app.pickup.admire_duration+app.pickup.bite_duration*0.55
	for frame in 35: app._process(1.0/60.0)
	var runtime_chew = app.pickup.segments[0].chew
	check(runtime_chew.from_bite,"runtime started the standalone chew entry")
	check(absf(runtime_chew.age-app.pickup.pose().biteChewAge)<0.00001,"runtime handoff clock diverged")
	var age: float = app.pickup.age
	app.settings_window.show()
	for frame in 10: app._process(1.0/60.0)
	check(app.pickup.age > age,"independent settings froze handoff")
	app.settings_window.hide()
	app.drag_pointer = root.position+Vector2i(300,160)
	app._begin_grab()
	for frame in 20: app._process(1.0/60.0)
	check(not app.pet.bite_face.mouth.visible and not app.pet.chewing_pose.sprite.visible,"grab left a mouth from the handoff")
	finish()

func finish() -> void:
	print("HANDOFF CHECKS: ",checks," passed: ",checks-failures," failed: ",failures)
	quit(0 if failures == 0 else 1)
