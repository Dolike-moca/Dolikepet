extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Sleep = preload("res://scripts/sleep_pose.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var mask: SubViewport
var pet
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize() -> void: call_deferred("run")
func draw(pose: Dictionary) -> Image:
	pet.apply_pose(pose,0.0)
	await process_frame; await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func digest(image: Image) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(image.get_data())
	return hash.finish().hex_encode()
func run() -> void:
	root.size = Vector2i(520,520); root.position = Vector2i(-1600,-1600); root.mouse_passthrough = true
	viewport = SubViewport.new(); viewport.size = root.size; viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	mask = SubViewport.new(); mask.size = root.size; mask.transparent_bg = true; mask.gui_disable_input = true
	mask.world_2d = viewport.world_2d; mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(mask)
	pet = Pet.new(); viewport.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))),"model failed to load")
	if not pet.available: quit(1); return
	pet.fit(Vector2(520,520)); pet.set_seated(true); pet.sitting.amount = 1.0; pet.tail.automatic = false
	var behavior = Behavior.new(); behavior.automatic_blinks = false
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,520,false).duplicate()
	base.motionReset = true; base.breath = 0.35; base.facingScale = 1.0
	var baseline := await draw(base)
	var baseline_hash := digest(baseline)
	var neutral_root: Transform2D = pet.model.transform
	var floor_transform: Transform2D = pet.sitting.sprite.global_transform
	var sleep := base.duplicate(); sleep.merge({"sleepWeight":1.0,"sleepEye":0.0,"sleepPhase":6.0,"sleepWakeStretch":0.0},true)
	var shown := await draw(sleep)
	check(digest(shown)!=baseline_hash,"sleep did not visibly change the seated pose")
	check(pet.sitting.amount==1.0 and pet.sitting.seated,"sleep changed the accepted sitting transition")
	check(pet.model.transform==neutral_root and pet.sitting.sprite.global_transform==floor_transform,"sleep breathing moved the seated floor or whole root")
	check(pet.params[pet.mapping.eyeNear].get("value")==0.0 and pet.params[pet.mapping.eyeFar].get("value")==0.0,"sleep eyes are not completely closed")
	check(pet.sleep_pose.mark.visible and pet.sleep_pose.decoration_layer is CanvasLayer,"sleep Z did not use its own decoration canvas")
	var mask_with_z := digest(mask.get_texture().get_image())
	check(mask_with_z!=digest(shown),"hit viewport unexpectedly contains sleep Z decoration")
	pet.sleep_pose.mark.hide()
	await process_frame; await RenderingServer.frame_post_draw
	check(mask_with_z==digest(mask.get_texture().get_image()),"changing Z visibility changed the pet hit mask")
	check(digest(viewport.get_texture().get_image())==mask_with_z,"visual difference beyond isolated Z remains in the hit canvas")
	var near_scale: Vector2 = pet.pickup_pose.hold_rig.near.transform.get_scale()
	var far_scale: Vector2 = pet.pickup_pose.hold_rig.far.transform.get_scale()
	sleep.sleepPhase = 1.0
	await draw(sleep)
	var crest: PackedVector2Array = Secondary.read_points(pet.meshes.ArtMesh24)
	sleep.sleepPhase = 3.0
	await draw(sleep)
	var trough: PackedVector2Array = Secondary.read_points(pet.meshes.ArtMesh24)
	var maximum := 0.0
	for index in crest.size(): maximum = maxf(maximum,crest[index].distance_to(trough[index]))
	check(maximum>0.1 and maximum<10.0,"sleep breathing is missing or too large")
	check(pet.pickup_pose.hold_rig.near.transform.get_scale().is_equal_approx(near_scale) and pet.pickup_pose.hold_rig.far.transform.get_scale().is_equal_approx(far_scale),"sleep stretched an approved whole arm")
	check(pet.model.transform==neutral_root and pet.sitting.sprite.global_transform==floor_transform,"sleep breath cycle moved planted seated legs")
	var eye_values := []
	for eye in [0.0,0.2,0.5,0.8,1.0]:
		sleep.sleepEye = eye
		await draw(sleep)
		eye_values.append(float(pet.params[pet.mapping.eyeNear].get("value")))
	var correct_eyes := true
	for index in eye_values.size(): correct_eyes = correct_eyes and is_equal_approx(eye_values[index],[0.0,0.2,0.5,0.8,1.0][index])
	check(correct_eyes,"sleep eyelid opening lost intermediate values")
	sleep.sleepEye = 0.0; sleep.speechWeight = 1.0; sleep.speechMouth = 0.7
	await draw(sleep)
	check(is_equal_approx(float(pet.params[pet.mapping.mouth].get("value")),0.7),"sleep prevented ordinary speech mouth animation")
	for flag in ["dragHeld","fallActive","landingActive","dizzyActive","bowlHitActive","mealActive","bowlCalling"]:
		var interrupt := sleep.duplicate(); interrupt[flag] = true
		check(Sleep.weight(interrupt)==0.0 and Sleep.prepare(interrupt)==interrupt,"sleep overrode "+flag)
	var off := base.duplicate(); off.sleepWeight = 0.0; off.sleepEye = 0.0; off.sleepPhase = 8.0
	check(digest(await draw(off))==baseline_hash and not pet.sleep_pose.mark.visible,"sleepWeight zero did not restore exact original seated pixels")
	for failure in failures: printerr("SLEEP RENDER: "+failure)
	print("Sleep render: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
