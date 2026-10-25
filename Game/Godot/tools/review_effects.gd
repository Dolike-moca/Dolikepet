extends SceneTree
## Deterministic visual contract. Run the same script against baseline/new PCK.
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Meal = preload("res://scripts/meal_motion.gd")
const Food = preload("res://scripts/food_item.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty(): printerr("Pass an absolute --out= directory"); quit(1); return
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(420,420); root.position = Vector2i(-1600,-1600)
	root.mouse_passthrough = true
	var viewport := SubViewport.new()
	viewport.size = Vector2i(420,420); viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pet = Pet.new(); viewport.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))):
		printerr(pet.failure); quit(1); return
	pet.fit(Vector2.ONE*420)
	# Tail constructors randomize their own generators independently of the meal.
	pet.tail.rng.seed = 20261024
	pet.tail.held_rng.seed = 20261025
	pet.tail.next_sway = 1.25
	var b = Behavior.new(); b.automatic_blinks = false
	var base: Dictionary = b.update(0.0,Vector2.ZERO,Vector2.ZERO,420,false).duplicate()
	var meal = Meal.new(); meal.rng.seed = 20261027
	meal.request_food([Food.from_texture(Food.DEMO_TEXTURES[0])],100,420)
	meal.state = "holding"
	var names := ["待机表情","行走与镜像","坐下站起","拖拽悬挂","下落落地眩晕","连续小口吃","举锅大喊","吃饱睁眼"]
	var metadata := {"protocol":2,"fps":30,"frames":720,"seed":20261027,"tailSeed":20261024,"heldTailSeed":20261025,"segments":names,"hashes":[]}
	for frame in 720:
		var index := frame/90 as int
		var t := float(frame%90)/89.0
		var p := base.duplicate()
		p.motionReset = frame%90==0; p.breath = sin(frame/30.0*2.0)*0.5+0.5
		p.facingScale = -1.0 if index==1 and t>0.5 else 1.0
		pet.sitting.amount = 0.0; pet.sitting.seated = false
		match index:
			0:
				p.gazeX = sin(t*TAU); p.headZ = sin(t*TAU)*1.2
				p.eyeNear = 1.0-maxf(0.0,1.0-absf(t-0.5)*12.0); p.eyeFar = p.eyeNear
			1: p.walkWeight = 1.0; p.walkPhase = t*TAU*4.0
			2:
				pet.sitting.amount = sin(t*PI); pet.sitting.seated = true
			3:
				p.merge({"dragHeld":t<0.75,"dragHang":1.0,"dragFace":1.0 if t<0.75 else 0.0,"dragTime":t*3.0,
					"dragTilt":sin(t*TAU)*0.14,"dragBend":0.1,"dragStretch":0.10},true)
			4:
				if t<0.33: p.merge({"fallActive":true,"fallFace":1.0,"fallStretch":0.065,"fallSpeed":3.0,"dragTilt":-0.12},true)
				elif t<0.66: p.merge({"landingActive":true,"landingKnee":sin((t-0.33)/0.33*PI)*0.7,"landingInfluence":1.0,"landingUpperBounce":0.06,"landingUpperTilt":0.08},true)
				else:
					pet.sitting.amount = 1.0; pet.sitting.seated = true
					p.merge({"dizzyActive":true,"dizzyAlpha":1.0,"dizzyUpperSway":sin(t*TAU*4)*0.06,"dizzyWobble":7.0},true)
			5:
				pet.sitting.amount = 1.0; pet.sitting.seated = true
				meal.age = t*(meal.food_end+meal.tail_time)
				p.merge(meal.pose(),true)
			6:
				p.merge({"bowlReach":minf(t*8.0,(1.0-t)*8.0),"bowlCalling":t<0.8,"bowlTime":t*6.0,
					"bowlTilt":sin(t*TAU*4.0)*0.1,"landingKnee":maxf(0.0,sin(t*TAU*3.0))*0.5},true)
			7:
				p.eyeNear = smoothstep(0.5,0.9,t); p.eyeFar = p.eyeNear
				p.mouth = 1.0-smoothstep(0.55,0.85,t)
		pet.apply_pose(p,1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image.save_png(out.path_join("frame-%04d.png"%frame))!=OK: quit(2); return
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(image.get_data())
		metadata.hashes.append(digest.finish().hex_encode())
	var file := FileAccess.open(out.path_join("review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata,"\t")); file.close()
	print("EFFECT REVIEW: "+out+" / 720 frames")
	quit()
