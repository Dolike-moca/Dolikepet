extends Node2D

const Secondary = preload("res://scripts/secondary_deformation.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
const Walking = preload("res://scripts/walking_pose.gd")
const Tail = preload("res://scripts/tail_motion.gd")
const WalkingHair = preload("res://scripts/walking_hair.gd")
const HairInertia = preload("res://scripts/hair_inertia.gd")
const DragPose = preload("res://scripts/drag_pose.gd")
const FallingHair = preload("res://scripts/falling_hair.gd")
const FallingPose = preload("res://scripts/falling_pose.gd")
const DragEyeTransition = preload("res://scripts/drag_eye_transition.gd")
const LandingPose = preload("res://scripts/landing_pose.gd")
const ChewingPose = preload("res://scripts/chewing_pose.gd")
const ChewingBody = preload("res://scripts/chewing_body.gd")
const PickupPose = preload("res://scripts/pickup_pose.gd")
const HungryFace = preload("res://scripts/hungry_face.gd")
const BiteFace = preload("res://scripts/bite_face.gd")
const Masks = preload("res://scripts/live2d_masks.gd")
const BowlReach = preload("res://scripts/bowl_reach_pose.gd")
var model: Node2D
var params: Dictionary = {}
var mapping: Dictionary = {}
var meshes: Dictionary = {}
var deformation = Secondary.new()
var sitting = Sitting.new()
var walking = Walking.new()
var tail = Tail.new()
var walking_hair = WalkingHair.new()
var hair_inertia = HairInertia.new()
var drag_pose = DragPose.new()
var falling_hair = FallingHair.new()
var falling_pose = FallingPose.new()
var drag_eye_transition = DragEyeTransition.new()
var landing_pose = LandingPose.new()
var chewing_pose = ChewingPose.new()
var chewing_body = ChewingBody.new()
var pickup_pose = PickupPose.new()
var hungry_face = HungryFace.new()
var bite_face = BiteFace.new()
var clipping_masks = Masks.new()
var bowl_reach = BowlReach.new()
var secondary_pose: Dictionary = {}
var facing_scale := 1.0
var fitted_size := Vector2(420, 420)
var bounds := Rect2()
var eye_center := Vector2.ZERO
var pixel_scale := 1.0
var pivot := Vector2.ZERO
var fit_position := Vector2.ZERO
var available := false
var failure := ""

func load_pet(config: Dictionary) -> bool:
	if not ClassDB.class_exists("GDCubismUserModel"):
		failure = "Live2D 插件尚未编译。请先完成 C++ 构建工具安装，再运行 tools/build-plugin.ps1。"
		return false
	model = ClassDB.instantiate("GDCubismUserModel")
	if not model.has_method("get_raw_mesh_vertices"):
		failure = "GDCubism 缺少本工程的顶点接口。请运行 tools/build-plugin.ps1 重新构建。"
		model.free()
		model = null
		return false
	model.set("playback_process_mode", 2) # MANUAL: exactly one update per frame.
	model.set("parameter_mode", 1) # NONE_PARAMETER: our controllers own values.
	model.set("physics_evaluate", false)
	model.set("pose_update", false)
	model.set("load_motions", false)
	model.set("load_expressions", false)
	add_child(model)
	model.set("assets", "res://" + config.model)
	for param in model.call("get_parameters"):
		params[param.get("id")] = param
	mapping = config.parameters
	for id in mapping.values():
		if not params.has(id):
			failure = "Live2D 模型缺少参数：" + id
			return false
	for key in mapping:
		params[mapping[key]].set("value", 1.0 if key in ["eyeNear", "eyeFar"] else 0.0)
	model.call("advance", 0.0)
	meshes = model.call("get_meshes")
	for id in ["ArtMesh18", "ArtMesh24", "ArtMesh5", Tail.MESH_ID] + Secondary.HAIR.keys() + Sitting.LOWER_IDS:
		if not meshes.has(id) or not meshes[id] is MeshInstance2D:
			failure = "Live2D 网格接口或模型不匹配：" + id
			return false
	var first := true
	for node in meshes.values():
		if not node.visible:
			continue
		for point in Secondary.read_points(node):
			if first:
				bounds = Rect2(point, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(point)
	if first or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		failure = "Live2D 模型没有可显示的网格。"
		return false
	var eyes: Array = config.gaze.irisDrawables
	for id in eyes:
		if not meshes.has(id):
			failure = "Live2D 模型缺少眼球：" + id
			return false
		var points := Secondary.read_points(meshes[id])
		var rect := Rect2(points[0], Vector2.ZERO)
		for point in points:
			rect = rect.expand(point)
		eye_center += rect.get_center() / eyes.size()
	var info: Dictionary = model.call("get_canvas_info")
	deformation.capture(meshes, info.origin_in_pixels.y)
	sitting.setup(model, meshes)
	walking.setup(sitting.boot_contours)
	drag_pose.setup(model, meshes, sitting.boot_contours)
	falling_pose.setup(model, meshes)
	landing_pose.setup(model, meshes)
	chewing_pose.setup(model, meshes)
	pickup_pose.setup(model, meshes)
	hungry_face.setup(model, meshes)
	bite_face.setup(model, meshes)
	bowl_reach.setup(model, meshes)
	chewing_pose.bite_origin = BiteFace.ANCHOR + bite_face.closed_center
	clipping_masks.setup(model, meshes)
	tail.setup(deformation.reference[Tail.MESH_ID])
	pivot = Vector2(bounds.get_center().x, bounds.end.y)
	available = true
	return true

func fit(size: Vector2) -> void:
	if not available:
		return
	pixel_scale = minf(size.x * 0.93 / bounds.size.x, size.y * 0.93 / bounds.size.y)
	fitted_size = size
	fit_position = Vector2(size.x * 0.5, size.y * 0.98) - pivot * pixel_scale
	_place(0.0)

func _place(angle: float) -> void:
	var placement := Transform2D(angle, Vector2(pixel_scale * facing_scale, pixel_scale), 0.0, Vector2.ZERO)
	placement.origin = Vector2(fitted_size.x * 0.5, fitted_size.y * 0.98) - placement * pivot
	transform = placement

func gaze_anchor() -> Vector2:
	# Keep the neutral anchor stable when hair/head/body move.
	return transform * (sitting.root_transform * eye_center)

func physics_anchor(facing: float = 1.0) -> Vector2:
	var neutral := Transform2D(0.0, Vector2(pixel_scale * signf(facing), pixel_scale), 0.0, Vector2.ZERO)
	neutral.origin = Vector2(fitted_size.x * 0.5, fitted_size.y * 0.98) - neutral * pivot
	return neutral * DragPose.PIVOT

func crown_cap() -> PackedVector2Array:
	# Main skull beneath the front hair; excludes ears, ahoge and flowing hair.
	var cap := PackedVector2Array()
	if not available or absf(facing_scale)<0.15: return cap
	var head: Transform2D = deformation._affine("ArtMesh18",Secondary.read_points(meshes.ArtMesh18))
	var world := transform*model.transform*head
	for point in [Vector2(510,535),Vector2(575,405),Vector2(695,320),Vector2(855,280),
		Vector2(1010,315),Vector2(1120,405),Vector2(1170,535)]:
		cap.append(world*(point-Vector2(1024,1024)))
	return cap

func food_gaze(pose: Dictionary) -> Vector2:
	# The same path as the visible icon, in this pet window's coordinates.
	var at := PickupPose.food_target(pickup_pose.gaze_body,pose)
	if pose.get("mealActive",false) and pickup_pose.hold_rig.enabled:
		at = pickup_pose.hold_rig.gaze_point
	var bowl_point := model.transform.affine_inverse()*PickupPose.BOWL_CENTER if pose.get("mealActive",false) else PickupPose.BOWL_CENTER
	at = at.lerp(bowl_point,pose.get("pickupBowlLook",0.0))
	return transform * (model.transform * at)

func set_seated(value: bool, speed: float = 1.0) -> void:
	sitting.set_seated(value, speed)

func apply_pose(pose: Dictionary, dt: float) -> void:
	if not available:
		return
	pose = falling_pose.update(pose, dt, sitting.amount)
	pose = drag_eye_transition.update(pose, dt)
	pose = bowl_reach.prepare(pose, dt)
	pose = landing_pose.prepare(pose)
	pose = chewing_pose.prepare(pose)
	pose = hungry_face.prepare(pose)
	for key in mapping:
		params[mapping[key]].set("value", pose[key])
	facing_scale = pose.get("facingScale", 1.0)
	_place(deg_to_rad(clampf(pose.bodyX, -1.0, 1.0) * 0.25)+pose.get("bowlTilt",0.0))
	model.call("advance", dt)
	var raw: Dictionary = model.call("get_raw_mesh_vertices")
	# A quick manual sit can arrive before roaming has finished easing the gait
	# out. Keep the standing meshes until the bent knees/feet have settled.
	var waiting_for_feet: bool = sitting.seated and sitting.amount == 0.0 \
		and pose.get("walkWeight", 0.0) > 0.00001
	if not waiting_for_feet:
		sitting.update(dt * (1.5 if pose.get("dragHeld", false) else 1.0))
	var body: Transform2D = deformation._affine("ArtMesh24", raw["ArtMesh24"])
	var head: Transform2D = deformation._affine("ArtMesh18", raw["ArtMesh18"])
	raw = landing_pose.deform(raw, body, pose.get("landingKnee", 0.0), sitting.amount)
	for id in Sitting.HIPS:
		if landing_pose.lowering.length_squared() > 0.000001: Secondary.write_points(meshes[id], raw[id])
	sitting.apply(model, meshes, raw, body)
	model.transform = drag_pose.root_transform(sitting.root_transform, landing_pose.root_pose(pose, sitting.amount), facing_scale)
	landing_pose.apply_root(model, transform, pose)
	secondary_pose = pose.duplicate()
	secondary_pose.walkingHair = walking_hair.update(dt, pose.get("walkPhase", 0.0),
		pose.get("walkWeight", 0.0), sitting.amount)
	# Follow the upper-head attachment through window travel, mirror turns and
	# sitting. Footfall bounce is already handled by walking_hair, so sample
	# before walking.apply adds that motion to the model transform.
	var motion_point := Vector2(0, -500)
	if pose.get("dizzyActive", false): motion_point = head * motion_point
	var chewing_upper := ChewingBody.upper_transform(body, pose)
	var pickup_upper := PickupPose.upper_transform(body, pose)
	# Amplify only swallowing's small local displacement, leaving desktop
	# travel/drag response unchanged. The existing layers still settle separately.
	var hair_point := motion_point + (chewing_upper * motion_point - motion_point) * ChewingBody.HAIR_GAIN
	hair_point += (pickup_upper * motion_point - motion_point) * 2.2
	var anchor: Vector2 = pose.get("motionOrigin", Vector2.ZERO) \
		+ transform * (model.transform * (landing_pose.upper_transform(body, pose) * hair_point))
	var inertia: Dictionary = hair_inertia.update(dt, anchor,
		minf(fitted_size.x, fitted_size.y), pose.get("motionReset", false)
			or (pose.get("fallActive", false) and not pose.get("physicsActive", false)))
	var local_inertia := {}
	for key in inertia:
		var screen_offset: Vector2 = inertia[key]
		# FallingHair supplies the strong upward lag. Keep the actual lateral
		# collision/regrab response without doubling the vertical wind effect.
		if pose.get("fallActive", false): screen_offset.y *= 0.25
		screen_offset.x *= signf(facing_scale)
		# Spring state stays in screen axes across a mirror; never divide by the
		# near-zero horizontal width during a turn.
		local_inertia[key] = (pickup_upper * chewing_upper * head).affine_inverse().basis_xform(screen_offset)
	secondary_pose.motionHair = local_inertia
	secondary_pose.fallingHair = falling_hair.update(dt, pose.get("fallSpeed", 0.0),
		pose.get("fallActive", false), pose.get("fallPaused", false))
	deformation.apply(meshes, secondary_pose, raw)
	tail.update(dt, pose.get("walkPhase", 0.0), pose.get("walkWeight", 0.0), sitting.amount,
		pose.get("dragHeld", false), pose.get("fallPaused", false),pose.get("juggleWeight",0.0),pose.get("juggleTail",0.0))
	tail.apply(meshes[Tail.MESH_ID], raw[Tail.MESH_ID], body)
	walking.apply(model, meshes, raw, body,
		pose.get("walkPhase", 0.0), pose.get("walkWeight", 0.0), sitting.amount)
	pickup_pose.apply_arms(meshes, body, pose)
	drag_pose.apply(model, meshes, raw, head, body, pose, sitting.amount)
	falling_pose.apply(meshes, head, body, pose)
	landing_pose.apply_face(meshes, head, pose, falling_pose.sprite)
	chewing_pose.apply(meshes, head, pose)
	hungry_face.apply(meshes, head, pose)
	bite_face.apply(meshes, head, pose)
	var faces: Array = landing_pose.sprites + drag_pose.sprites \
		+ [falling_pose.sprite, chewing_pose.sprite, chewing_pose.swallow_sprite, hungry_face.mouth, bite_face.mouth] + chewing_pose.eyes
	chewing_body.apply(meshes, body, pose, faces)
	pickup_pose.apply_upper(meshes, body, pose, faces)
	landing_pose.apply_upper(meshes, body, pose, faces)
	pickup_pose.apply_props(body, pose, landing_pose.upper_transform(body,pose))
	bowl_reach.apply(meshes,head,pickup_pose.hold_rig,pose.get("bowlReach",0.0),pose.get("bowlHitActive",false))
	# advance() sizes clipping viewports before runtime mesh deformation. Refit
	# once all layers have moved, including landing recoil and swallowing bends.
	clipping_masks.refresh()
	sitting.update_composite_coordinates()
