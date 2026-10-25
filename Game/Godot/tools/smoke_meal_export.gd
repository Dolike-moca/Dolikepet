extends SceneTree
## Run against the exported PCK with --main-pack; arguments: settings path, PNG paths.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()<3: printerr("SMOKE requires settings path and two PNGs"); quit(1); return
	var report := FileAccess.open(args[0]+".result",FileAccess.WRITE)
	report.store_line("started"); report.flush()
	var settings := ConfigFile.new()
	settings.set_value("pet","auto_fall_enabled",false)
	settings.set_value("window","size",600)
	settings.save(args[0])
	var scene = load("res://scenes/pet.tscn")
	var app = scene.instantiate()
	app.settings_path = args[0]
	app.bowl_root_override = args[0].get_base_dir().path_join("smoke-fixture/bowl")
	root.add_child(app)
	app.set_process(false)
	app.set_process_input(false)
	if not app.pet.available: printerr(app.pet.failure); quit(1); return
	var braid_orders := {"ArtMesh17":app.pet.meshes.ArtMesh17.z_index,"ArtMesh25":app.pet.meshes.ArtMesh25.z_index}
	report.store_line("native model loaded"); report.flush()
	app._feed_pngs(PackedStringArray([args[1],args[2]]))
	if not app.pickup.meal_enabled or app.pickup.foods.size()!=1:
		printerr("SMOKE exported PNG queue failed to start"); quit(1); return
	if app.pickup.segments.size()<8 or app.pickup.segments.size()>10:
		printerr("SMOKE exported pack does not contain the small-bite schedule"); quit(1); return
	if not app.pickup.pose().has("foodCuts"):
		printerr("SMOKE exported pack does not contain rounded bites"); quit(1); return
	for frame in 40: app._process(0.05)
	report.store_line("first pickup advanced"); report.flush()
	if app.pet.sitting.amount<0.999 or not app.pet.pickup_pose.hold_rig.enabled:
		printerr("SMOKE exported meal did not use the approved seated arm rig"); quit(1); return
	if app.pet.pickup_pose.hold_rig.far.texture!=app.pet.pickup_pose.hold_rig.FarArt:
		printerr("SMOKE exported meal did not use the palm-facing arm"); quit(1); return
	var held_rig = app.pet.pickup_pose.hold_rig
	var held_body: Transform2D = app.pet.pickup_pose.gaze_body
	var held_pose: Dictionary = app.pickup.pose()
	var pickup_script = load("res://scripts/pickup_pose.gd")
	var held_upper: Transform2D = pickup_script.upper_transform(held_body,held_pose)*pickup_script.Spine.upper_transform(held_body,held_pose)
	var held_length: float = ((held_upper*held_body).affine_inverse().basis_xform(held_rig.palms.ArtMesh26-held_rig.shoulders.ArtMesh26)).length()
	if absf(held_length-306.349487304688)>0.01:
		printerr("SMOKE exported meal does not contain the approved longer far arm"); quit(1); return
	if app.pickup.admire_duration<5.0 or app.pickup.admire_duration>6.0:
		printerr("SMOKE exported pack does not contain the longer star-eye hold"); quit(1); return
	for id in ["ArtMesh2","ArtMesh25","ArtMesh27"]:
		if not app.pet.meshes[id].visible or app.pet.meshes[id].self_modulate.a!=1.0:
			printerr("SMOKE exported meal hid hair: "+id); quit(1); return
	for id in braid_orders:
		if app.pet.meshes[id].z_index!=braid_orders[id]:
			printerr("SMOKE exported meal changed the native braid depth: "+id); quit(1); return
	var braids = app.pet.pickup_pose.hold_rig.braid_layers
	if app.pet.meshes.ArtMesh17.self_modulate.a!=0.0 or braids.pieces[0].node.z_index!=braid_orders.ArtMesh17 or braids.pieces[1].node.z_index<=app.pet.pickup_pose.hold_rig.near.z_index:
		printerr("SMOKE exported meal lost braid root/arm occlusion"); quit(1); return
	for piece in braids.pieces:
		if not piece.node.visible or piece.node.modulate.a!=1.0:
			printerr("SMOKE exported meal hid split braid"); quit(1); return
	var at: float = app.pickup.age
	app._feed_pngs(PackedStringArray([args[1]]))
	if app.pickup.age != at or app.pickup.foods.size()!=2:
		printerr("SMOKE exported append reset progress"); quit(1); return
	for frame in 3000:
		app._process(0.05)
		if frame%500==0:
			report.store_line("frame %d served %d completed %d"%[frame,app.pickup.served,app.pickup.completed]); report.flush()
		if not app.pickup.active(): break
	if app.pickup.completed!=3 or app.pickup.active() or app.pet.pickup_pose.food.visible:
		printerr("SMOKE exported queue did not eat all three PNGs"); quit(1); return
	if app.pet.pickup_pose.hold_rig.enabled or app.pet.meshes.ArtMesh17.self_modulate.a!=1.0:
		printerr("SMOKE exported meal did not restore the normal arms/hair"); quit(1); return
	for piece in braids.pieces:
		if piece.node.visible:
			printerr("SMOKE exported meal left a foreground braid after release"); quit(1); return
	var rig = app.pet.pickup_pose.hold_rig
	if rig.far.texture!=rig.FarRestArt or rig.far_rest_overlay.visible:
		printerr("SMOKE exported idle did not restore the PSD far-arm art"); quit(1); return
	if not rig.near.visible or not rig.far.visible or app.pet.meshes.ArtMesh19.self_modulate.a!=0.0 or app.pet.meshes.ArtMesh26.self_modulate.a!=0.0:
		printerr("SMOKE exported idle did not keep common arm art"); quit(1); return
	# Verify the actual exported rig, after the entire meal/release lifecycle.
	var normal_body: Transform2D = app.pet.pickup_pose.gaze_body
	var normal_arm: Transform2D = normal_body.affine_inverse()*rig.far.transform
	if absf(normal_arm.get_rotation()-deg_to_rad(-8.0))>0.001 or (normal_arm*rig.FAR_REST_ROOT).distance_to(Vector2(-304,166))>0.01:
		printerr("SMOKE exported idle did not restore the 8-degree rest angle at the PSD shoulder"); quit(1); return
	print("EXPORTED MEAL: 8-degree rest restored; common arms retained; longer star eyes; hair visible; all 3 queued PNGs eaten")
	report.store_line("PASS: 8-degree rest, common arms, longer star eyes, visible hair, 3 external PNGs completed"); report.close()
	quit()
