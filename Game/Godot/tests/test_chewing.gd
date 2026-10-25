extends SceneTree
const Motion = preload("res://scripts/chewing_motion.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Scene = preload("res://scenes/pet.tscn")
const Secondary = preload("res://scripts/secondary_deformation.gd")
const ChewingPose = preload("res://scripts/chewing_pose.gd")
const ChewingBody = preload("res://scripts/chewing_body.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 20: printerr("CHEWING: " + message)

func simulation(fps: int, seed_value: int = 20261022) -> Array:
	var motion = Motion.new()
	motion.rng.seed = seed_value
	motion.start()
	var samples := []
	var min_x := INF
	var max_x := -INF
	var max_y := 0.0
	var valid := true
	var previous: Dictionary = motion.pose()
	var max_step := 0.0
	for f in 26 * fps:
		var p: Dictionary = motion.update(1.0 / fps)
		valid = valid and p.chewOffset.is_finite() and absf(p.chewAngle) <= deg_to_rad(3.001) \
			and p.chewAlpha >= 0.0 and p.chewAlpha <= 1.0 \
			and p.chewNod >= 0.0 and p.chewNod <= 1.2 \
			and p.chewSquint >= 0.0 and p.chewSquint <= 0.4 \
			and p.chewSqueeze >= 0.0 and p.chewSqueeze <= 1.0 \
			and p.chewSwallowMouth >= 0.0 and p.chewAlpha + p.chewSwallowMouth <= 1.000001
		min_x = minf(min_x, p.chewOffset.x)
		max_x = maxf(max_x, p.chewOffset.x)
		max_y = maxf(max_y, p.chewOffset.y)
		max_step = maxf(max_step, p.chewOffset.distance_to(previous.chewOffset))
		previous = p
		if (f + 1) % (fps / 10) == 0: samples.append(p.duplicate())
	check(valid and min_x < -3.8 and max_x > 3.8 and max_y > 8.8, "ellipse/roll invalid at %d fps" % fps)
	# Under 0.6 desktop pixels per 30 Hz step, including the quickest group.
	check(max_step * fps < 80.0, "motion snapped at %d fps: %.4f model pixels" % [fps, max_step])
	check(not motion.active() and previous.chewAlpha == 0.0 and previous.chewOffset == Vector2.ZERO, "demo failed to finish")
	# At swallowing peak, the food mouth yields to the supplied swallow mouth.
	motion.start()
	var at: float = motion.groups[0].chew_end + motion.groups[0].rest * (0.83 if motion.groups[0].long_swallow else 0.46)
	while motion.age < at: motion.update(1.0 / fps)
	var resting: Dictionary = motion.pose()
	check(resting.chewAlpha == 0.0 and resting.chewSwallow == 1.0 and resting.chewSwallowMouth == 1.0 and resting.chewNod > 0.98 \
		and resting.chewOffset == Vector2.ZERO, "swallow failed to close/settle/nod")
	for f in fps: motion.update(1.0 / fps, true)
	check(motion.pose() == resting, "explicit pause advanced chewing")
	motion.cancel()
	for f in ceili(0.2 * fps): motion.update(1.0 / fps)
	check(not motion.active() and motion.pose().chewAlpha == 0.0, "cancel did not release mouth")
	return samples

func run() -> void:
	var baseline := simulation(30)
	for fps in [60, 120]:
		var samples := simulation(fps)
		var error := 0.0
		for i in samples.size():
			error = maxf(error, samples[i].chewOffset.distance_to(baseline[i].chewOffset))
			error = maxf(error, absf(samples[i].chewAngle - baseline[i].chewAngle))
			error = maxf(error, absf(samples[i].chewAlpha - baseline[i].chewAlpha))
			error = maxf(error, absf(samples[i].chewNod - baseline[i].chewNod))
			error = maxf(error, absf(samples[i].chewSwallow - baseline[i].chewSwallow))
			error = maxf(error, absf(samples[i].chewSwallowMouth - baseline[i].chewSwallowMouth))
			error = maxf(error, absf(samples[i].chewSquint - baseline[i].chewSquint))
			error = maxf(error, absf(samples[i].chewSqueeze - baseline[i].chewSqueeze))
			error = maxf(error, absf(samples[i].chewEyeClose - baseline[i].chewEyeClose))
			error = maxf(error, absf(samples[i].chewBend - baseline[i].chewBend))
			error = maxf(error, absf(samples[i].chewShiver - baseline[i].chewShiver))
		check(error < 0.00002, "motion changes with frame rate")
	var boundary = Motion.new()
	boundary.rng.seed = 20261022
	boundary.start()
	var boundaries := [0.12, boundary.duration]
	for group in boundary.groups:
		boundaries.append_array([group.start + group.normal_time, group.chew_end, group.end])
		boundaries.append_array([group.chew_end - group.eye_lead, group.chew_end + group.rest * 0.28,
			group.chew_end + group.rest * group.eye_release])
		boundary.age = group.chew_end - group.eye_lead - 0.01
		check(boundary.pose().chewSquint == 0.0, "eyes narrowed before the final chew")
		boundary.age = group.chew_end - 0.05
		check(boundary.pose().chewSquint > 0.1 and boundary.pose().chewNod == 0.0, "squint did not anticipate swallowing")
		boundary.age = group.chew_end + group.rest * 0.46
		check(is_equal_approx(boundary.pose().chewSquint, group.eye_depth), "squint did not peak with swallowing")
		boundary.age = group.chew_end + group.rest * 0.87
		check(boundary.pose().chewNod == 0.0 and boundary.pose().chewSquint > 0.05, "eyes failed to lag head recovery")
		for ratio in [0.16, 0.22, 0.43, 0.50, 0.78, 0.86]: boundaries.append(group.chew_end + group.rest * ratio)
	for at in boundaries:
		boundary.age = at - 0.00001
		var before: Dictionary = boundary.pose()
		boundary.age = at + 0.00001
		check(boundary.pose().chewOffset.distance_to(before.chewOffset) < 0.001, "orbit jumps across group/turn boundary")
		check(absf(boundary.pose().chewNod - before.chewNod) < 0.001 \
			and absf(boundary.pose().chewAlpha - before.chewAlpha) < 0.001 \
			and absf(boundary.pose().chewSwallowMouth - before.chewSwallowMouth) < 0.001 \
			and absf(boundary.pose().chewSquint - before.chewSquint) < 0.001, "mouth, eyes or nod snap across swallow boundary")
	var counts := {}
	var shortest := INF
	var longest := 0.0
	var valid := true
	for trial in 80:
		var random_motion = Motion.new()
		random_motion.rng.seed = 9100 + trial
		random_motion.start()
		var original_schedule: Array = random_motion.groups.duplicate(true)
		for group in random_motion.groups:
			counts[group.chews] = true
			shortest = minf(shortest, group.chew_time)
			longest = maxf(longest, group.chew_time)
			valid = valid and group.chews >= 3 and group.chews <= 7 \
				and group.period >= Motion.PERIOD_MIN and group.period <= Motion.PERIOD_MAX \
				and group.rest >= (Motion.LONG_REST_MIN if group.long_swallow else Motion.REST_MIN) \
				and group.rest <= (Motion.LONG_REST_MAX if group.long_swallow else Motion.REST_MAX) \
				and group.eye_depth >= 0.30 and group.eye_depth <= 0.40 \
				and group.eye_lead >= 0.30 and group.eye_lead <= 0.42 \
				and group.eye_release >= 0.70 and group.eye_release <= 0.78
		for f in 15: random_motion.update(1.0 / 60)
		valid = valid and random_motion.groups == original_schedule
	check(valid and counts.size() == 5 and longest - shortest > 1.5, "swallow timing not varied or resampled per frame")
	check_long_swallow_logic()
	var face = ChewingPose.new()
	for eye in [0.0, 0.25, 0.6, 1.0]:
		var pose := {"headZ": 0.0, "mouth": 0.0, "eyeNear": eye, "eyeFar": eye, "chewSquint": 0.35}
		var prepared: Dictionary = face.prepare(pose)
		check(is_equal_approx(prepared.eyeNear, eye * 0.65) and prepared.eyeFar == prepared.eyeNear,
			"swallow eyes reopened/overrode a blink")
	boundary.age = boundary.groups[0].chew_end + boundary.groups[0].rest * 0.46
	boundary.cancel()
	for f in 15: boundary.update(1.0 / 60)
	check(boundary.pose().chewSquint == 0.0, "cancel left eyes narrowed")
	var b = Behavior.new()
	b.automatic_blinks = false
	b.command("talk")
	b.command("chew")
	check(b.talk_until == 0.0 and b.mode == "normal", "talk competes with chewing")
	for action in ["normal", "happy", "closed", "closedHappy", "talk", "pet"]:
		b.command("chew")
		for f in 20: b.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 420, false)
		b.command(action)
		for f in 20: b.update(1.0 / 60, Vector2.ZERO, Vector2.ZERO, 420, false)
		check(not b.chewing.active() and b.values.chewAlpha == 0.0, action + " left chewing active")
	if DisplayServer.get_name() == "headless":
		finish(); return
	root.size = Vector2i(600, 600)
	root.position = Vector2i(24, 24)
	root.mouse_passthrough = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(600, 600)
	root.add_child(preview)
	var pet = Pet.new()
	viewport.add_child(pet)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	check(pet.load_pet(config), pet.failure)
	if not pet.available: finish(); return
	pet.fit(Vector2(600, 600))
	b = Behavior.new()
	b.automatic_blinks = false
	var out := "res://../../_work/tests/chewing-bend-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var sprite: Sprite2D = pet.chewing_pose.sprite
	# Exercise both facings, seated/standing and head follow. The sprite must
	# use the same fresh head affine without scale changes across its orbit.
	for sample in [[1.0, 0.0, false], [1.0, 18.0, false], [-1.0, -18.0, true]]:
		b.command("chew")
		var pose: Dictionary = b.update(0.1, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
		pose = b.update(0.1, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
		pose.headZ = sample[1]
		pose.facingScale = sample[0]
		pet.set_seated(sample[2])
		pet.sitting.amount = 1.0 if sample[2] else 0.0
		pet.apply_pose(pose, 0.0)
		var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
		var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
		var local: Transform2D = head.affine_inverse() * sprite.transform
		check(local.origin.distance_to(pet.chewing_pose.CENTER + pose.chewOffset) < 0.001, "mouth detached from head")
		check(absf(local.x.length() - local.y.length()) < 0.00001 and absf(local.x.dot(local.y)) < 0.00001, "chewing deformed the mouth")
		check(sprite.visible and sprite.modulate.a == 1.0 and pet.meshes.ArtMesh3.self_modulate.a == 0.0 \
			and pet.meshes.ArtMesh4.self_modulate.a == 0.0, "normal mouth overlaps chewing")
		for override in ["dragFace", "fallActive", "dizzyAlpha"]:
			var priority: Dictionary = pose.duplicate()
			priority[override] = true if override == "fallActive" else 1.0
			priority.chewNod = 1.0
			priority.chewSwallow = 1.0
			priority.chewSwallowMouth = 1.0
			priority.chewSquint = 0.4
			priority.chewSqueeze = 1.0
			priority.chewEyeClose = 1.0
			check(pet.chewing_pose.prepare(priority).headZ == priority.headZ, "swallow nod overrides " + override)
			check(pet.chewing_pose.prepare(priority).eyeNear == priority.eyeNear, "swallow eyes override " + override)
			for f in 12: pet.apply_pose(priority, 1.0 / 60)
			check(not sprite.visible, override + " did not override chew mouth")
			check(not pet.chewing_pose.swallow_sprite.visible, override + " did not override swallow mouth")
			check(not pet.chewing_pose.eyes[0].visible and not pet.chewing_pose.eyes[1].visible, override + " did not override swallowing eyes")
		for f in 12: pet.apply_pose(pose, 1.0 / 60)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("head-%d.png" % sample[1]))
	check_swallow_geometry(pet)
	check_squeeze_geometry(pet)
	check_bend_geometry(pet)
	check_relief_geometry(pet)
	# Actual renderer preview, including entry/exit and manual blink mid-chew.
	pet.set_seated(false)
	pet.sitting.amount = 0.0
	pet.sitting.velocity = 0.0
	b = Behavior.new()
	b.automatic_blinks = false
	# This actual random seed contains one rare swallow in the middle group.
	# Production remains random with its 4% chance; no forced runtime branch.
	b.chewing.rng.seed = 20261034
	b.command("chew")
	var frame_count: int = ceili((b.chewing.duration + 1.0) * 30)
	var hair_release := 0.0
	var hair_peak := 0.0
	var hair_settled := 0.0
	var hair_layer_difference := 0.0
	# Hair follows body recovery, which finishes before the extended face hold.
	var release_time: float = b.chewing.groups[1].end - Motion.SMILE_HOLD
	print("SWALLOW PREVIEW: duration %.3f s, groups %s, frames %d" % [b.chewing.duration, b.chewing.groups, frame_count])
	for f in frame_count:
		if f == 30: b.command("blink")
		var pose: Dictionary = b.update(1.0 / 30, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
		pet.apply_pose(pose, 1.0 / 30)
		if pose.chewBend > 0.0:
			for offset in pet.hair_inertia.offsets.values(): hair_peak = maxf(hair_peak, offset.length())
		if b.chewing.age > release_time and b.chewing.age < release_time + 0.20:
			for offset in pet.hair_inertia.offsets.values(): hair_release = maxf(hair_release, offset.length())
			hair_layer_difference = maxf(hair_layer_difference, pet.hair_inertia.offsets.hairFront.distance_to(pet.hair_inertia.offsets.hairBack))
		if b.chewing.age > release_time + 1.0 and b.chewing.age < release_time + 1.2:
			for offset in pet.hair_inertia.offsets.values(): hair_settled = maxf(hair_settled, offset.length())
		check(is_equal_approx(pet.params[pet.mapping.eyeNear].get("value"), pose.eyeNear * (1.0 - pose.chewSquint) * (1.0 - pose.chewEyeClose)) \
			and is_equal_approx(pet.params[pet.mapping.eyeFar].get("value"), pose.eyeFar * (1.0 - pose.chewSquint) * (1.0 - pose.chewEyeClose)),
			"rendered eyes differ from swallowing/blink pose")
		if f == 31: check(pose.eyeNear == 0.0 and sprite.visible, "blink hides chewing mouth")
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(out.path_join("frame-%04d.png" % f))
	check(not sprite.visible and pet.meshes.ArtMesh3.self_modulate.a == 1.0, "end failed to restore normal mouth")
	check(not pet.chewing_pose.swallow_sprite.visible, "end left swallowing mouth visible")
	check(not pet.chewing_pose.eyes[0].visible and pet.meshes.ArtMesh6.self_modulate.a == 1.0, "end left squeezed eyes behind")
	check(hair_peak > 2.0 and hair_release > 0.5 and hair_layer_difference > 0.1 and hair_settled < hair_release * 0.25,
		"hair failed to lag the torso recovery in distinct layers or settle")
	print("BEND HAIR: peak %.4f, release %.4f, settled %.4f, layers %.4f" % [hair_peak, hair_release, hair_settled, hair_layer_difference])
	preview.queue_free()
	viewport.queue_free()
	await process_frame
	# Real menu routing and busy/pause rules with isolated settings.
	var settings_path := "res://../../_work/tests/chewing-test-settings.cfg"
	var settings := ConfigFile.new()
	settings.set_value("window", "size", 420)
	settings.set_value("pet", "auto_fall_enabled", false)
	settings.set_value("pet", "roaming_mode", "free")
	settings.set_value("pet", "auto_sit_min_seconds", 5.0)
	settings.set_value("pet", "auto_sit_max_seconds", 5.0)
	settings.save(settings_path)
	var app = Scene.instantiate()
	app.settings_path = settings_path
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	app.bubble.hide()
	var area := DisplayServer.screen_get_usable_rect(root.current_screen)
	root.position = Vector2i(area.position.x + 40, area.end.y - root.size.y)
	app.falling.reposition(Vector2(root.position))
	app._menu_action(6)
	check(app.behavior.chewing.active() and app.menu.get_item_text(app.menu.get_item_index(6)).contains("咀嚼"), "menu action missing")
	for f in 320: app._process(1.0 / 60)
	check(app.roaming.weight == 0.0 and app.idle_sitting.elapsed == 0.0 and not app.pet.sitting.seated, "idle movement/rest interrupted demo")
	var age: float = app.behavior.chewing.age
	app.settings_window.show()
	for f in 20: app._process(1.0 / 60)
	check(app.behavior.chewing.age > age, "independent settings froze chew timer")
	app.settings_window.hide()
	app._open_menu(root.position + Vector2i(210, 160))
	for f in 20: app._process(1.0 / 60)
	check(app.behavior.chewing.age > age + 0.3, "right menu paused chewing")
	app.menu.hide()
	app.drag_pointer = root.position + Vector2i(210, 160)
	app._begin_grab()
	for f in 20: app._process(1.0 / 60)
	check(not app.behavior.chewing.active() and not app.pet.chewing_pose.sprite.visible, "grab failed to cancel chewing")
	finish()

func check_long_swallow_logic() -> void:
	var eligible := 0
	var events := 0
	var long_motion
	var all_valid := true
	var phase_continuous := true
	for seed_value in range(12000, 14000):
		var motion = Motion.new()
		motion.rng.seed = seed_value
		motion.start()
		var had_event := false
		for group in motion.groups:
			if not had_event: eligible += 1
			if group.long_swallow:
				all_valid = all_valid and not had_event
				had_event = true
				events += 1
				if long_motion == null: long_motion = motion
			var times: PackedFloat64Array = group.turn_times
			var previous := -0.000001
			for step in 80:
				var phase: float = Motion.turns_at(group, group.chew_time * step / 79.0)
				phase_continuous = phase_continuous and phase >= previous and phase <= group.chews
				previous = phase
			for i in range(1, times.size() - 1):
				var a: float = Motion.turns_at(group, times[i] - 0.00001)
				var c: float = Motion.turns_at(group, times[i] + 0.00001)
				phase_continuous = phase_continuous and absf((i - a) - (c - i)) < 0.0000001
	check(all_valid and events > 0, "multiple long swallows in a demo")
	check(phase_continuous, "per-chew speed changes reversed or snapped")
	var rate := float(events) / eligible
	check(rate > 0.03 and rate < 0.05, "long swallow probability differs from 4 percent")
	print("LONG SWALLOW: %d events / %d eligible, %.3f%%" % [events, eligible, rate * 100.0])
	if long_motion == null: return
	var group: Dictionary = {}
	for candidate in long_motion.groups:
		if candidate.long_swallow: group = candidate; break
	for sample in [[0.11, 0.55, 0.0], [0.44, 0.0, 1.0], [0.83, 1.2, 1.0], [0.98, 1.2, 1.0]]:
		long_motion.age = group.chew_end + group.rest * sample[0]
		var pose: Dictionary = long_motion.pose()
		check(is_equal_approx(pose.chewNod, sample[1]) and is_equal_approx(pose.chewSqueeze, sample[2])
			and pose.chewAlpha == 0.0, "long swallow lost its two efforts or pause")
		if sample[0] == 0.98:
			check(pose.chewEyeClose == 1.0, "normal eyes reopened before the squeezed artwork disappeared")
	for key in ["chewAlpha", "chewSwallowMouth", "chewNod", "chewSqueeze", "chewEyeClose", "chewSquint", "chewBend", "chewReliefSmile", "chewReliefLift", "chewReliefRock"]:
		var previous := 0.0
		var max_step := 0.0
		for f in 720:
			long_motion.age = group.chew_end - 0.5 + (group.rest + group.relief + 0.5) * f / 719.0
			var value: float = long_motion.pose()[key]
			if f > 0: max_step = maxf(max_step, absf(value - previous))
			previous = value
		var sample_dt: float = (group.rest + group.relief + 0.5) / 719.0
		check(max_step / sample_dt < 25.0, "long swallow channel snapped: " + key)
		for boundary in [group.chew_end, group.chew_end+group.rest, group.end]:
			long_motion.age = boundary-0.000001
			var left: float = long_motion.pose()[key]
			long_motion.age = boundary+0.000001
			check(absf(long_motion.pose()[key]-left) < 0.0001, "expression boundary jumps: " + key)
	var earlier_bend := 0.0
	for fraction in [0.20, 0.40, 0.60, 0.74]:
		long_motion.age = group.chew_end + group.rest * fraction
		var current: Dictionary = long_motion.pose()
		check(current.chewBend >= earlier_bend and current.chewBend > 0.30, "torso straightened between swallowing efforts")
		earlier_bend = current.chewBend
	long_motion.age = group.chew_end + group.rest * 0.75
	check(absf(long_motion.pose().chewShiver) < 0.000001 and long_motion.pose().chewBend > 0.99, "torso recovered before shivering stopped")
	# Observe the resulting motion, not just configured limits: 2–3 distinct
	# efforts, quiet gaps, heavier final two, and a decaying tail in each effort.
	var burst_counts := {}
	for seed_value in range(20261020,20261120):
		var trial = Motion.new()
		trial.rng.seed = seed_value
		trial.start()
		for candidate in trial.groups:
			if not candidate.long_swallow: continue
			check(candidate.rest >= 1.5 and candidate.rest <= 2.5 and candidate.relief >= 1.25 and candidate.relief <= 1.55,
				"strain/relief clocks outside selected ranges")
			var peaks := []
			var in_burst := false
			var peak := 0.0
			var quiet := 0.0
			var burst_values := []
			var decays := true
			var stays_bent := true
			var stops_before_recovery := true
			var previous_bend := 0.0
			for step in 1601:
				var u := float(step)/1600.0
				trial.age = candidate.chew_end + candidate.rest*u
				var value: Dictionary = trial.pose()
				var amount: float = absf(value.chewShiver)
				if u > 0.24 and u < 0.73:
					stays_bent = stays_bent and value.chewBend + 0.00001 >= previous_bend
					previous_bend = value.chewBend
				# Require sustained quiet, so a sine zero crossing never counts
				# as a separate effort.
				if amount > 0.001:
					in_burst = true
					quiet = 0.0
					peak = maxf(peak,amount)
				elif in_burst:
					quiet += candidate.rest/1600.0
				if in_burst:
					burst_values.append(amount)
					if quiet >= 0.065:
						var tail: Array = burst_values.slice(int(burst_values.size()*0.75))
						decays = decays and tail.max() < peak*0.6
						peaks.append(peak); in_burst = false; peak = 0.0; burst_values.clear()
				if u > 0.74: stops_before_recovery = stops_before_recovery and amount < 0.00001
			if in_burst: peaks.append(peak)
			check(stays_bent and stops_before_recovery and decays, "efforts failed to decay/hold bend/stop before recovery")
			burst_counts[peaks.size()] = true
			check(peaks.size() in [2,3], "long swallow did not form 2–3 separate efforts: %s" % [peaks])
			if peaks.size() >= 3:
				check(peaks[-1] > peaks[-2] and peaks[-2] > peaks[0], "final two efforts are not heavier")
	check(burst_counts.has(2) and burst_counts.has(3), "burst-count variation missing")
	var long_samples: Array = simulation(30,20261034)
	for fps in [60,120]:
		var samples: Array = simulation(fps,20261034)
		var error := 0.0
		for i in samples.size():
			for key in ["chewBend","chewShiver","chewSqueeze","chewEyeClose","chewSwallowMouth","chewReliefSmile","chewReliefLift","chewReliefRock"]:
				error = maxf(error,absf(samples[i][key]-long_samples[i][key]))
		check(error < 0.00002, "strong long swallow changes with frame rate")
	var relief_start: float = group.chew_end+group.rest
	var peak_smile := 0.0
	var rock_forward := 0.0
	var rock_back := 0.0
	for step in 121:
		var r := float(step)/120.0
		long_motion.age = relief_start+group.relief*r
		var relief: Dictionary = long_motion.pose()
		check(relief.chewShiver == 0.0, "relief still shivers")
		if relief.chewSqueeze > 0.00001: check(relief.chewEyeClose == 1.0, "relief opened eyes under squeezed artwork")
		if relief.chewReliefSmile > 0.6:
			check(relief.chewEyeClose == 1.0 and relief.chewSwallowMouth == 0.0 and relief.chewAlpha == 0.0,
				"happy relief lacks closed eyes or overlaps another mouth")
		peak_smile = maxf(peak_smile,relief.chewReliefSmile)
		rock_back = maxf(rock_back,relief.chewReliefRock)
		rock_forward = minf(rock_forward,relief.chewReliefRock)
	check(peak_smile > 0.9 and rock_back > 0.9 and rock_forward < -0.05, "relief missing smile/overshoot/soft settle")
	long_motion.age = group.end
	check(long_motion.pose().chewBend == 0.0 and long_motion.pose().chewShiver == 0.0, "bend/shiver leaked into normal chewing")
	long_motion.age = group.chew_end + group.rest * 0.63
	var frozen: Dictionary = long_motion.pose()
	for f in 60: long_motion.update(1.0 / 60, true)
	check(long_motion.pose() == frozen, "paused long swallow changed")
	long_motion.cancel()
	for f in 15: long_motion.update(1.0 / 60)
	check(long_motion.pose().chewSqueeze == 0.0 and long_motion.pose().chewEyeClose == 0.0 \
		and long_motion.pose().chewBend == 0.0 and long_motion.pose().chewShiver == 0.0 \
		and long_motion.pose().chewSwallowMouth == 0.0 and long_motion.pose().chewReliefSmile == 0.0, "cancel left swallowing pose behind")
	var interrupted = Motion.new()
	interrupted.rng.seed = 20261034
	interrupted.start()
	var middle: Dictionary = interrupted.groups[1]
	interrupted.age = middle.chew_end+middle.rest+middle.relief*0.45
	check(interrupted.pose().chewReliefSmile > 0.9, "relief cancellation fixture is not smiling")
	interrupted.cancel()
	for f in 15: interrupted.update(1.0/60)
	var cleared: Dictionary = interrupted.pose()
	check(cleared.chewReliefSmile == 0.0 and cleared.chewReliefLift == 0.0 and cleared.chewReliefRock == 0.0,
		"interrupting relief left a smile or upper-body offset")

func check_relief_geometry(pet) -> void:
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	var motion = Motion.new()
	motion.rng.seed = 20261034
	motion.start()
	var group: Dictionary = motion.groups[1]
	for facing in [1.0,-1.0]:
		for seated in [false,true]:
			pet.set_seated(seated)
			pet.sitting.amount = 1.0 if seated else 0.0
			pet.sitting.velocity = 0.0
			for z in [-18.0,18.0]:
				base.facingScale = facing
				base.headZ = z
				pet.apply_pose(base,0.0)
				var supported: Transform2D = pet.sitting.sprite.global_transform
				var lower := {}
				for id in ["ArtMesh21","ArtMesh22","ArtMesh23"]: lower[id] = Secondary.read_points(pet.meshes[id]).duplicate()
				for fraction in [0.30,0.45,0.65,0.80,0.95]:
					motion.age = group.chew_end+group.rest+group.relief*fraction
					var pose: Dictionary = base.duplicate()
					pose.merge(motion.pose(),true)
					pet.apply_pose(pose,0.0)
					var stays_supported: bool = pet.sitting.sprite.global_transform == supported
					for id in lower: stays_supported = stays_supported and Secondary.read_points(pet.meshes[id]) == lower[id]
					check(stays_supported, "happy relief moved standing/seated support")
					if fraction == 0.45:
						var prepared: Dictionary = pet.chewing_pose.prepare(pose)
						check(prepared.mouth > 0.9 and prepared.eyeNear == 0.0 and prepared.eyeFar == 0.0,
							"happy relief failed to use native closed-happy expression")
						check(pet.meshes.ArtMesh3.self_modulate.a == 1.0 and not pet.chewing_pose.sprite.visible
							and not pet.chewing_pose.swallow_sprite.visible and not pet.chewing_pose.eyes[0].visible
							and not pet.chewing_pose.eyes[1].visible, "relief smile overlaps a swallowing feature")
						for override in ["dragHeld","fallActive","dizzyActive"]:
							var priority: Dictionary = pose.duplicate()
							priority[override] = true
							check(pet.chewing_pose.prepare(priority) == priority and ChewingBody.angle(priority) == 0.0,
								"happy relief overrides physical animation")
	pet.set_seated(false)
	pet.sitting.amount = 0.0
	print("RELIEF GEOMETRY: native closed smile, physical priorities and fixed supports verified")

func check_bend_geometry(pet) -> void:
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	pet.tail.automatic = false
	var base: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	base.chewNod = 1.2
	base.chewSqueeze = 1.0
	base.chewEyeClose = 1.0
	base.chewSwallow = 1.0
	base.chewSwallowMouth = 1.0
	var max_scarf_error := 0.0
	for facing in [1.0, -1.0]:
		for seated in [false, true]:
			pet.set_seated(seated)
			pet.sitting.amount = 1.0 if seated else 0.0
			pet.sitting.velocity = 0.0
			base.facingScale = facing
			pet.apply_pose(base, 0.0)
			var lower: Transform2D = pet.sitting.sprite.global_transform
			var before := {}
			for id in pet.meshes: before[id] = Secondary.read_points(pet.meshes[id]).duplicate()
			var eye_before: Transform2D = pet.chewing_pose.eyes[0].transform
			var mouth_before: Transform2D = pet.chewing_pose.swallow_sprite.transform
			for amount in [0.35, 0.70, 1.0]:
				for shiver in [-1.0, 0.0, 1.0]:
					var pose: Dictionary = base.duplicate()
					pose.chewBend = amount
					pose.chewShiver = shiver
					pet.apply_pose(pose, 0.0)
					var head_now := Secondary.read_points(pet.meshes.ArtMesh18)
					var body: Transform2D = pet.deformation._affine("ArtMesh24", pet.model.call("get_raw_mesh_vertices").ArtMesh24)
					var upper: Transform2D = ChewingBody.upper_transform(body, pose)
					var max_head_error := 0.0
					for i in head_now.size(): max_head_error = maxf(max_head_error, head_now[i].distance_to(upper * before.ArtMesh18[i]))
					var scarf_now := Secondary.read_points(pet.meshes.ArtMesh5)
					for i in scarf_now.size():
						if before.ArtMesh5[i].y + 1024.0 < 1160.0:
							max_scarf_error = maxf(max_scarf_error, scarf_now[i].distance_to(upper * before.ArtMesh5[i]))
					check(max_head_error < 0.002 and absf(upper.determinant() - 1.0) < 0.00001,
						"torso bend stretched the head/neck")
					check(pet.chewing_pose.eyes[0].transform.is_equal_approx(upper * eye_before), "squeezed eyes detached during bend")
					check(pet.chewing_pose.swallow_sprite.transform.is_equal_approx(upper * mouth_before), "swallow mouth detached during bend")
					var supported: bool = pet.sitting.sprite.global_transform == lower
					for id in ["ArtMesh21", "ArtMesh22", "ArtMesh23", "ArtMesh28"]:
						supported = supported and Secondary.read_points(pet.meshes[id]) == before[id]
					check(supported, "bend/shiver moved soles, seated hips, skirt or tail root")
					var torso_now := Secondary.read_points(pet.meshes.ArtMesh24)
					var max_curve := 0.0
					for i in torso_now.size(): max_curve = maxf(max_curve, torso_now[i].distance_to(upper * before.ArtMesh24[i]))
					check(max_curve > 1.0 and head_now[0].x < before.ArtMesh18[0].x - 1.0, "torso failed to curve forward from the waist")
	check(max_scarf_error < 0.002, "bending lost scarf/neck continuity")
	for override in ["dragHeld", "fallActive", "dizzyActive"]:
		var pose: Dictionary = base.duplicate()
		pose[override] = true
		pet.apply_pose(pose, 0.0)
		var before := Secondary.read_points(pet.meshes.ArtMesh24).duplicate()
		pose.chewBend = 1.0
		pose.chewShiver = 1.0
		pet.apply_pose(pose, 0.0)
		check(Secondary.read_points(pet.meshes.ArtMesh24) == before, "swallow bend overrides " + override)
	print("BEND GEOMETRY: scarf %.6f px; lower support unchanged" % max_scarf_error)
	# Let the intentionally exercised drag-release eye handoff complete before
	# the independent preview starts; do not mistake it for swallowing eyes.
	for f in 12: pet.apply_pose(base, 1.0 / 60)
	pet.set_seated(false)
	pet.sitting.amount = 0.0

func check_squeeze_geometry(pet) -> void:
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var original: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
	original.breath = 0.0
	original.motionReset = true
	for facing in [1.0, -1.0]:
		for seated in [false, true]:
			for z in [-18.0, 0.0, 18.0]:
				var pose: Dictionary = original.duplicate()
				pose.facingScale = facing
				pose.headZ = z
				pose.chewSqueeze = 1.0
				pose.chewEyeClose = 1.0
				pose.chewSwallow = 1.0
				pose.chewSwallowMouth = 1.0
				pose.chewNod = 1.2
				pet.set_seated(seated)
				pet.sitting.amount = 1.0 if seated else 0.0
				pet.sitting.velocity = 0.0
				pet.apply_pose(pose, 0.0)
				for i in 2:
					var eye: Sprite2D = pet.chewing_pose.eyes[i]
					var reference: Sprite2D = pet.drag_pose.sprites[i]
					check(eye.texture == reference.texture and eye.transform.is_equal_approx(reference.transform)
						and eye.z_index == reference.z_index and eye.visible and eye.modulate.a == 1.0,
						"swallow eyes differ from PSD drag eye placement/orientation")
				check(pet.meshes.ArtMesh6.self_modulate.a == 0.0 and pet.meshes.ArtMesh8.self_modulate.a == 0.0
					and pet.meshes.ArtMesh3.self_modulate.a == 0.0 and pet.chewing_pose.swallow_sprite.visible and not pet.drag_pose.sprites[2].visible,
					"swallow shows normal eyes or activates the dragged mouth")
	pet.set_seated(false)
	pet.sitting.amount = 0.0

func check_swallow_geometry(pet) -> void:
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	pet.tail.automatic = false
	var original: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 600, false).duplicate()
	original.breath = 0.0
	original.motionReset = true
	var max_scarf_error := 0.0
	var max_body_error := 0.0
	for facing in [1.0, -1.0]:
		for seated in [false, true]:
			for z in [-18.0, 0.0, 18.0]:
				var pose: Dictionary = original.duplicate()
				pose.headZ = z
				pose.facingScale = facing
				pet.set_seated(seated)
				pet.sitting.amount = 1.0 if seated else 0.0
				pet.sitting.velocity = 0.0
				pet.apply_pose(pose, 0.0)
				var body_before := Secondary.read_points(pet.meshes.ArtMesh24).duplicate()
				var lower_before: Transform2D = pet.sitting.sprite.global_transform
				var before_raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
				var before_head: Transform2D = pet.deformation._affine("ArtMesh18", before_raw.ArtMesh18)
				pose.chewNod = 1.0
				pose.chewSwallow = 1.0
				pose.chewSwallowMouth = 1.0
				pet.apply_pose(pose, 0.0)
				var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
				var head: Transform2D = pet.deformation._affine("ArtMesh18", raw.ArtMesh18)
				var delta: Transform2D = head * before_head.affine_inverse()
				check(absf(rad_to_deg(delta.get_rotation()) + 1.2) < 0.005, "nod direction or amplitude differs with gaze/facing")
				check(delta.get_scale().distance_to(Vector2.ONE) < 0.00001, "nod stretches head/neck")
				var body_now := Secondary.read_points(pet.meshes.ArtMesh24)
				for i in body_now.size(): max_body_error = maxf(max_body_error, body_now[i].distance_to(body_before[i]))
				check(body_before == body_now and pet.sitting.sprite.global_transform == lower_before, "nod moves torso/seated support")
				var scarf := Secondary.read_points(pet.meshes.ArtMesh5)
				var neutral: PackedVector2Array = pet.deformation.reference.ArtMesh5
				for i in neutral.size():
					if neutral[i].y + 1024.0 <= 1160.0:
						max_scarf_error = maxf(max_scarf_error, scarf[i].distance_to(head * neutral[i]))
				var mouth: Sprite2D = pet.chewing_pose.swallow_sprite
				check(not pet.chewing_pose.sprite.visible and mouth.visible and pet.meshes.ArtMesh3.self_modulate.a == 0.0,
					"swallow mouth missing or overlaps normal mouth")
				check(mouth.flip_h and not mouth.flip_v and mouth.transform.origin.distance_to(head * ChewingPose.CENTER) < 0.002,
					"swallow mouth flip or position differs across head/facing/sitting")
	check(max_scarf_error < 0.002 and max_body_error < 0.001, "nod loses scarf/torso continuity")
	print("SWALLOW GEOMETRY: scarf %.6f px, torso %.6f px" % [max_scarf_error, max_body_error])
	pet.set_seated(false)
	pet.sitting.amount = 0.0

func finish() -> void:
	print("CHEWING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
