extends SceneTree
## End-to-end checks and contact sheet of the actual renderer in every pose.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Meal = preload("res://scripts/meal_motion.gd")
const Food = preload("res://scripts/food_item.gd")
var failures := 0
var checks := 0
var captured := {}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<15: printerr("SHARED ARMS: "+reason)

func run() -> void:
	root.size = Vector2i(600,600)
	root.position = Vector2i(-1600,-1600)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600,600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new()
	viewport.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))):
		printerr(pet.failure); quit(1); return
	pet.fit(Vector2.ONE*600)
	var braid_orders := {"ArtMesh17":pet.meshes.ArtMesh17.z_index,"ArtMesh25":pet.meshes.ArtMesh25.z_index}
	var behavior = Behavior.new()
	var base: Dictionary = behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0; base.motionReset = true
	var meal = Meal.new()
	meal.rng.seed = 20261027
	meal.request_food([Food.from_texture(Food.DEMO_TEXTURES[0])],100,600)
	meal.state = "holding"
	var states := [
		["站立",0.0,{}],
		["行走 · 前摆",0.0,{"walkWeight":1.0,"walkPhase":PI*0.5}],
		["行走 · 后摆",0.0,{"walkWeight":1.0,"walkPhase":PI*1.5}],
		["坐下过渡",0.5,{}],
		["坐姿",1.0,{}],
		["拖拽悬挂",0.0,{"dragHeld":true,"dragHang":1.0,"dragFace":1.0,"dragTime":0.6,"dragTilt":0.14,"dragBend":0.1,"dragStretch":0.10}],
		["下落",0.0,{"fallActive":true,"fallFace":1.0,"fallStretch":0.065,"fallSpeed":3.0,"dragTilt":-0.12}],
		["落地回弹",0.0,{"landingActive":true,"landingKnee":0.7,"landingInfluence":1.0,"landingUpperBounce":0.06,"landingUpperTilt":0.08}],
		["眩晕坐姿",1.0,{"dizzyActive":true,"dizzyAlpha":1.0,"dizzyUpperSway":0.06,"dizzyWobble":7.0}],
		["咀嚼吞咽",1.0,{"chewAlpha":1.0,"chewBend":0.8,"chewShiver":0.6}],
		["取食 · 星星眼",1.0,{"meal_age":3.0}],
		["进食 · 小口吃",1.0,{"meal_age":meal.segments[0].start+meal.segments[0].duration*0.4}],
		["侧看 · 左",0.0,{"gazeX":-1.0,"bodyX":-0.85,"headZ":-18.0}],
		["侧看 · 右",0.0,{"gazeX":1.0,"bodyX":0.85,"headZ":18.0}],
		["微笑",0.0,{"mouth":1.0}],
		["闭眼休息",1.0,{"eyeNear":0.0,"eyeFar":0.0}]
	]
	var out := "res://../../_work/tests/shared-arm-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var sheet := SubViewport.new()
	sheet.size = Vector2i(1600,2000)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var background := ColorRect.new()
	background.color = Color("292633")
	background.size = Vector2(sheet.size)
	sheet.add_child(background)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei"])
	for facing in [1.0,-1.0]:
		for i in states.size():
			var state: Array = states[i]
			pet.sitting.amount = state[1]
			pet.sitting.seated = state[1]>0.0
			pet.falling_pose.face = 0.0; pet.falling_pose.stretch = 0.0
			pet.drag_eye_transition.was_held = false
			pet.drag_eye_transition.recovering = false
			var p := base.duplicate()
			p.merge(state[2],true)
			if p.has("meal_age"):
				meal.age = p.meal_age
				p.merge(meal.pose(),true)
			p.facingScale = facing
			if p.get("fallActive",false):
				pet.falling_pose.face = 1.0; pet.falling_pose.stretch = 0.065
			pet.apply_pose(p,0.0)
			var rig = pet.pickup_pose.hold_rig
			var body: Transform2D = pet.pickup_pose.gaze_body
			var alignment: Transform2D = pet.landing_pose.upper_transform(body,p)*Pet.PickupPose.upper_transform(body,p)*Pet.ChewingBody.upper_transform(body,p)*body
			var inverse := alignment.affine_inverse()
			var captured_far: Transform2D = inverse*rig.far.transform
			var captured_near: Transform2D = inverse*rig.near.transform
			captured[str(i)+"/"+str(facing)] = {"title":state[0],"held":rig.enabled,
				"far":[captured_far.x.x,captured_far.x.y,captured_far.y.x,captured_far.y.y,captured_far.origin.x,captured_far.origin.y],
				"near":[captured_near.x.x,captured_near.x.y,captured_near.y.x,captured_near.y.y,captured_near.origin.x,captured_near.origin.y]}
			for id in rig.SOCKETS:
				var expected: Vector2 = rig.SOCKETS[id]
				if id=="ArtMesh26": expected = rig.FAR_REST_SOCKET.lerp(expected,Pet.PickupPose.amount(p))
				check((inverse*rig.shoulders[id]).distance_to(expected)<0.003,state[0]+" shoulder moved "+id)
				check(pet.meshes[id].self_modulate.a==0.0,state[0]+" exposed old arm "+id)
			var far_art = rig.FarArt if rig.enabled else rig.FarRestArt
			var far_registration: Transform2D = rig.FAR_HOLD if rig.enabled else rig.FAR_REST
			for pair in [[rig.near,rig.NEAR_HOLD,rig.NearArt],[rig.far,far_registration,far_art]]:
				var local: Transform2D = inverse*pair[0].transform
				check(pair[0].visible and pair[0].modulate.a==1.0,state[0]+" hid common arm")
				check(pair[0].texture==pair[2],state[0]+" changed arm artwork")
				var art_scale: float = 1.19298833568046 if pair[0]==rig.far and rig.enabled else 1.0
				check(absf(local.x.length()-pair[1].x.length()*art_scale)<0.00001 and absf(local.y.length()-local.x.length())<0.00001 and absf(local.x.dot(local.y))<0.00001,state[0]+" stretched arm")
			for id in ["ArtMesh2","ArtMesh25","ArtMesh27"]:
				check(pet.meshes[id].visible and pet.meshes[id].self_modulate.a==1.0,state[0]+" hid hair "+id)
			check(rig.far.z_index<pet.meshes.ArtMesh5.z_index,state[0]+" rear shoulder crossed scarf")
			for id in braid_orders:
				check(pet.meshes[id].z_index==braid_orders[id],state[0]+" moved whole braid in front of its root occluders")
			check(pet.meshes.ArtMesh17.z_index<pet.meshes.ArtMesh2.z_index and pet.meshes.ArtMesh17.z_index<pet.meshes.ArtMesh5.z_index,state[0]+" braid root crossed sidelocks/scarf")
			if rig.enabled:
				check(rig.near.z_index>pet.pickup_pose.food.z_index and pet.pickup_pose.food.z_index>pet.meshes.ArtMesh5.z_index,state[0]+" arm/food/scarf order wrong")
				check(pet.meshes.ArtMesh17.self_modulate.a==0.0,state[0]+" duplicated original braid")
				for piece in rig.braid_layers.pieces:
					check(piece.node.visible and piece.node.modulate.a==1.0,state[0]+" hid split braid")
				check(rig.braid_layers.pieces[0].node.z_index==braid_orders.ArtMesh17,state[0]+" exposed braid root")
				check(rig.braid_layers.pieces[1].node.z_index>rig.near.z_index,state[0]+" arm covered hanging braid")
				check(pet.meshes.ArtMesh25.z_index>rig.far.z_index,state[0]+" far arm covered braid")
			else:
				check(not rig.far_rest_overlay.visible,state[0]+" hand-turn overlay leaked into rest")
				if i in [0,3,4,12,13,14,15]:
					var psd_local: Transform2D = inverse*rig.far.transform
					check((psd_local*rig.FAR_REST_ROOT).distance_to(Vector2(-304,166))<0.003,state[0]+" normal shoulder left the PSD socket")
					# Independently captured from the accepted 8-degree preview.
					check((psd_local*rig.FAR_REST_PALM).distance_to(Vector2(-399.41357421875,457.112060546875))<0.01,state[0]+" normal palm differs from the accepted 8-degree preview")
					check(absf(psd_local.get_rotation()-deg_to_rad(-8.0))<0.001,state[0]+" normal far arm reverted to its old angle")
				check(rig.near.z_index<pet.meshes.ArtMesh17.z_index,state[0]+" resting arm crossed native braid depth")
				check(pet.meshes.ArtMesh17.self_modulate.a==1.0,state[0]+" did not restore native braid")
				for piece in rig.braid_layers.pieces: check(not piece.node.visible,state[0]+" leaked held braid into another pose")
			await process_frame
			await RenderingServer.frame_post_draw
			var rendered := viewport.get_texture().get_image()
			rendered.save_png(out.path_join("pose-%02d-facing-%d.png"%[i,int(facing)]))
			if facing == 1.0:
				var cell := Vector2((i%4)*400,(i/4 as int)*500)
				var label := Label.new()
				label.text = state[0]
				label.position = cell+Vector2(24,14)
				label.add_theme_font_override("font",font)
				label.add_theme_font_size_override("font_size",24)
				sheet.add_child(label)
				var view := TextureRect.new()
				view.texture = ImageTexture.create_from_image(rendered)
				view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				view.size = Vector2(400,400)
				view.position = cell+Vector2(0,65)
				sheet.add_child(view)
	await process_frame
	await RenderingServer.frame_post_draw
	check(sheet.get_texture().get_image().save_png(out.path_join("shared-arms-all-poses.png")) == OK, "save all-pose preview")
	var capture_file := FileAccess.open(out.path_join("geometry.json"),FileAccess.WRITE)
	capture_file.store_string(JSON.stringify(captured,"\t"))
	print("SHARED ARMS: ",checks," checks; ",failures," failures; all-pose preview saved")
	quit(0 if failures==0 else 1)
