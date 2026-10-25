extends RefCounted
## Curved arm reach with a palm-side far arm and separate sleeve/hand depth.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Walking = preload("res://scripts/walking_pose.gd")
const Spine = preload("res://scripts/chewing_body.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
const ArmLayers = preload("res://scripts/pickup_arm_layers.gd")
const HoldRig = preload("res://scripts/feeding_hold_rig.gd")
const Food = preload("res://assets/feeding/burger.png")
const Bowl = preload("res://assets/feeding/bowl.png")
const BiteShader = preload("res://shaders/food_bite.gdshader")
const ORIGIN := Vector2(1024, 1024)
const FOOD_CENTER := Vector2(670, 1332) - ORIGIN
const FOOD_WIDTH := 520.0
const BOWL_CENTER := Vector2(270, 1880) - ORIGIN
const BOWL_WIDTH := 365.0
const SOURCE := Vector2(270, 1750) - ORIGIN
const PALMS := {"ArtMesh19": Vector2(1137, 1450) - ORIGIN,
	"ArtMesh26": Vector2(585, 1465) - ORIGIN}
const TARGETS := {"ArtMesh19": Vector2(925, 1380) - ORIGIN,
	"ArtMesh26": Vector2(467, 1305) - ORIGIN}
const FAR_HOLD_SHOULDER_DROP := Vector2(0.0,20.0)
var food: Sprite2D
var food_material: ShaderMaterial
var bowl: Sprite2D
var original_order := {}
var food_scale := 1.0
var bowl_scale := 1.0
var palms := {}
var spine = Spine.new()
var near_layers = ArmLayers.new()
var far_layers = ArmLayers.new()
var hold_rig = HoldRig.new()
var has_far_palm := false
var gaze_body := Transform2D.IDENTITY
var active_food
var depth_meshes := {}
static var hold_radii := {}

static func amount(pose: Dictionary) -> float:
	var priority: float = 1.0 if pose.get("bowlHitActive",false) else preload("res://scripts/chewing_pose.gd").priority(pose)
	return pose.get("pickupArms", 0.0) * priority

static func spine_pose(pose: Dictionary) -> Dictionary:
	return {"chewBend": pose.get("pickupLean", 0.0) * amount(pose)}

static func upper_transform(body: Transform2D, pose: Dictionary) -> Transform2D:
	return Spine.upper_transform(body, spine_pose(pose))

func setup(model: Node2D, meshes: Dictionary) -> void:
	depth_meshes = meshes
	food = Sprite2D.new()
	food.name = "PickupFood"
	food.texture = Food
	food.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	food_material = ShaderMaterial.new()
	food_material.shader = BiteShader
	food.material = food_material
	food_scale = FOOD_WIDTH / Food.get_image().get_used_rect().size.x
	# Center the opaque icon, not the padded 512 px source canvas.
	food.offset = Vector2(Food.get_size()) * 0.5 - Vector2(Food.get_image().get_used_rect().get_center())
	# Food passes in front of the complete face and scarf. The near hand is
	# brought forward during pickup so it still visibly embraces the edge.
	food.z_index = maxi(meshes.ArtMesh5.z_index, meshes.ArtMesh3.z_index) + 2
	food.hide()
	model.add_child(food)
	bowl = Sprite2D.new()
	bowl.name = "PickupBowl"
	bowl.texture = Bowl
	bowl.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bowl_scale = BOWL_WIDTH / Bowl.get_image().get_used_rect().size.x
	bowl.offset = Vector2(Bowl.get_size()) * 0.5 - Vector2(Bowl.get_image().get_used_rect().get_center())
	bowl.z_index = meshes.ArtMesh19.z_index - 3
	bowl.hide()
	model.add_child(bowl)
	for id in Walking.SHOULDERS: original_order[id] = meshes[id].z_index
	# The near forearm wraps over the larger icon's front-right edge. Keep
	# enough sleeve with the palm to avoid a hand emerging through its face.
	near_layers.setup(model,meshes.ArtMesh19,Walking.ELBOWS.ArtMesh19,
		(PALMS.ArtMesh19-Walking.ELBOWS.ArtMesh19).normalized(),-30.0,food.z_index+2)
	if ResourceLoader.exists("res://assets/feeding/arm_far_palm.png"):
		far_layers.setup(model,meshes.ArtMesh26,Walking.ELBOWS.ArtMesh26,
			(PALMS.ArtMesh26-Walking.ELBOWS.ArtMesh26).normalized(),35.0,food.z_index-1,
			load("res://assets/feeding/arm_far_palm.png"),Rect2(Vector2(505,1176)-ORIGIN,Vector2(287,372)),
			Rect2(129,26,959,1276))
		has_far_palm = true
	refresh_depth()
	hold_rig.setup(model,meshes)

func refresh_depth() -> void:
	# Cubism updates drawable orders on advance(). Reassert the carried stack
	# afterwards, keeping the rear support behind the scarf as well as food.
	food.z_index = maxi(depth_meshes.ArtMesh5.z_index,
		maxi(depth_meshes.ArtMesh18.z_index,depth_meshes.ArtMesh3.z_index))+2
	near_layers.pieces[1].node.z_index = food.z_index+1
	if has_far_palm:
		far_layers.pieces[1].node.z_index = mini(food.z_index-1,depth_meshes.ArtMesh5.z_index-1)

static func corrected(id: String, point: Vector2) -> Vector2:
	if id == "ArtMesh19": return point
	return Walking.SHOULDERS[id] + Walking.FAR_ARM_SHOULDER_OFFSET \
		+ Walking.FAR_ARM_BASIS * (point - Walking.SHOULDERS[id])

static func solve(id: String, weight: float, dip: float, grip: float = 1.0, gather: float = 1.0,
		carry: Vector2 = Vector2.ZERO, target_override: Vector2 = Vector2(INF,INF)) -> Dictionary:
	var shoulder := corrected(id, Walking.SHOULDERS[id])
	var elbow := corrected(id, Walking.ELBOWS[id])
	var palm := corrected(id, PALMS[id])
	var target: Vector2 = TARGETS[id] + carry_offset(gather) + carry + Vector2(0, 11.0 * dip)
	var adaptive := target_override.is_finite()
	var far_hold := adaptive and id == "ArtMesh26"
	var near_hold := adaptive and id == "ArtMesh19"
	if adaptive: target = target_override+carry+Vector2(0,11.0*dip)
	# Keep the near palm slightly open until contact. The far hand supports
	# from behind, so its wrist never cuts across the visible food surface.
	if id == "ArtMesh19": target += Vector2(17,9) * (1.0-grip)
	# Keep the far shoulder slightly below the near one, as in the standing
	# reference. Ease this small placement correction with the pickup itself.
	var root_offset := FAR_HOLD_SHOULDER_DROP if far_hold else Vector2.ZERO
	var ray := target - (shoulder+root_offset)
	var bone := {"shoulder": shoulder, "elbow": elbow, "palm": palm,
		"root_offset": root_offset*weight,
		"upper": 0.0, "lower": 0.0,
		"curve_start": -95.0 if near_hold else (-85.0 if far_hold else (-145.0 if id == "ArtMesh19" else -95.0)),
		"curve_end": 40.0 if near_hold else (45.0 if far_hold else (85.0 if id == "ArtMesh26" else 110.0))}
	# Solve against the continuous elbow curve rather than a sharp hinge.
	# Both forearms extend forward; the far wrist never folds back inward.
	var low := 0.0
	# The held near cuff and palm stay beyond the bend, as one rigid section.
	# A shallow elbow plus slight foreshortening preserves the reference pose.
	var high := deg_to_rad(35.0 if near_hold else (18.0 if far_hold else (115.0 if id == "ArtMesh19" else 86.0)))
	for step in 16:
		bone.lower = (low + high) * 0.5
		var distance := curve_point(palm,bone).distance_to(shoulder)
		if distance > ray.length(): low = bone.lower
		else: high = bone.lower
	bone.lower = (low + high) * 0.5
	# A lifted near forearm is slightly foreshortened. Keep the smooth, broad
	# elbow bend inside its non-folding range and shorten only its reach axis.
	var length := (curve_point(palm,bone)-shoulder).length()
	bone.reach_scale = lerpf(1.0,clampf(ray.length()/length,0.90,1.0),weight) if id == "ArtMesh19" else 1.0
	# Square icons stay at chest level: modest foreshortening is sufficient,
	# with no collapsed far arm or long reach toward the mouth.
	if adaptive: bone.reach_scale = lerpf(1.0,clampf(ray.length()/length,0.66 if far_hold else 0.85,1.0 if far_hold else 1.12),weight)
	bone.upper = wrapf(ray.angle() - (curve_point(palm,bone)-shoulder).angle(), -PI, PI) * weight
	bone.lower *= weight
	return bone

static func curve_point(point: Vector2, bone: Dictionary) -> Vector2:
	var angle: float = bone.lower
	if absf(angle) < 0.00001: return point
	var axis: Vector2 = (bone.palm - bone.elbow).normalized()
	var normal := Vector2(-axis.y,axis.x)
	var at: Vector2 = point - bone.elbow
	var along := at.dot(axis)
	var side := at.dot(normal)
	var start: float = bone.get("curve_start",-95.0)
	var end: float = bone.get("curve_end",85.0)
	if along <= start: return point
	var turn := angle * clampf((along-start)/(end-start),0.0,1.0)
	var radius := (end-start)/angle
	var center: Vector2 = bone.elbow + axis * start \
		+ axis * (radius*sin(turn)) + normal * (radius*(1.0-cos(turn)))
	center += axis.rotated(turn) * maxf(0.0,along-end)
	return center + normal.rotated(turn) * side

static func arm_point(point: Vector2, bone: Dictionary) -> Vector2:
	var local := curve_point(point,bone)
	var rotated: Vector2 = (local-bone.shoulder).rotated(bone.upper)
	var axis: Vector2 = (curve_point(bone.palm,bone)-bone.shoulder).rotated(bone.upper).normalized()
	rotated += axis*rotated.dot(axis)*(bone.get("reach_scale",1.0)-1.0)
	return bone.shoulder + bone.get("root_offset",Vector2.ZERO) + rotated

static func carry_offset(gather: float) -> Vector2:
	return Vector2(-8,4) * (1.0-gather)

static func fit_carry(near: Vector2, far: Vector2, carry: Vector2, dip: float) -> Vector2:
	# Keep both wrists inside their actual projected reach while the icon
	# lifts/tilts. Wide remnants need a smaller lift, not stretched arms.
	var low := -INF
	var high := INF
	for id in ["ArtMesh19","ArtMesh26"]:
		var shoulder := corrected(id,Walking.SHOULDERS[id])
		if id == "ArtMesh26": shoulder += FAR_HOLD_SHOULDER_DROP
		if not hold_radii.has(id):
			var folded := solve(id,1.0,0.0,1.0,1.0,Vector2.ZERO,shoulder+Vector2.DOWN)
			var straight := solve(id,1.0,0.0,1.0,1.0,Vector2.ZERO,shoulder+Vector2.DOWN*10000.0)
			hold_radii[id] = Vector2(arm_point(folded.palm,folded).distance_to(shoulder)+3.0,
				arm_point(straight.palm,straight).distance_to(shoulder)-3.0)
		var radii: Vector2 = hold_radii[id]
		var target := near if id == "ArtMesh19" else far
		var dx := target.x+carry.x-shoulder.x
		var baseline := shoulder.y-target.y-11.0*dip
		low = maxf(low,baseline+sqrt(maxf(0.0,radii.x*radii.x-dx*dx)))
		high = minf(high,baseline+sqrt(maxf(0.0,radii.y*radii.y-dx*dx)))
	return Vector2(carry.x,clampf(carry.y,low,high)) if low<=high else carry

static func food_position(pose: Dictionary) -> Vector2:
	var u: float = pose.get("pickupFlight", 0.0)
	var point := SOURCE.lerp(pose.get("foodHold",FOOD_CENTER) + carry_offset(pose.get("pickupGather",1.0)) \
		+ pose.get("pickupCarry",Vector2.ZERO), u)
	point.y -= 140.0 * sin(u * PI)
	point.y += 11.0 * pose.get("pickupCatch", 0.0)
	return point

static func food_target(body: Transform2D, pose: Dictionary) -> Vector2:
	var target := body * food_position(pose)
	return target.lerp(upper_transform(body,pose) * Spine.upper_transform(body,pose) * target,
		smoothstep(0.55,1.0,pose.get("pickupFlight",0.0)))

func apply_arms(meshes: Dictionary, body: Transform2D, pose: Dictionary) -> void:
	var weight := amount(pose)
	for id in original_order: meshes[id].z_index = original_order[id]
	if weight <= 0.00001: return
	# Far arm stays behind the large food; no wrist or layer-order flip.
	var inverse := body.affine_inverse()
	for id in Walking.SHOULDERS:
		# A small near-arm delay breaks the mechanical perfectly mirrored reach.
		var arm_weight := weight * lerpf(0.82,1.0,weight) if id == "ArtMesh19" else weight
		var bone := solve(id, arm_weight, pose.get("pickupCatch", 0.0),
			pose.get("pickupGrip",1.0),pose.get("pickupGather",1.0),pose.get("pickupCarry",Vector2.ZERO),
			pose.get("foodNear" if id == "ArtMesh19" else "foodFar",Vector2(INF,INF)))
		var points := Secondary.read_points(meshes[id])
		for i in points.size(): points[i] = body * arm_point(inverse * points[i], bone)
		Secondary.write_points(meshes[id], points)
		palms[id] = body * arm_point(bone.palm, bone)

func apply_upper(meshes: Dictionary, body: Transform2D, pose: Dictionary, faces: Array) -> void:
	spine.apply(meshes, body, spine_pose(pose), faces)

func apply_props(body: Transform2D, pose: Dictionary, landing_upper := Transform2D.IDENTITY) -> void:
	refresh_depth()
	gaze_body = body
	var item = pose.get("foodItem")
	if item != active_food:
		active_food = item
		food.texture = item.texture if item != null else Food
		food_scale = item.display_scale if item != null else FOOD_WIDTH/Food.get_image().get_used_rect().size.x
	if item != null: food_scale = pose.foodScale
	food.offset = Vector2(food.texture.get_size())*0.5-(pose.foodSourceCenter if item != null else Vector2(Food.get_image().get_used_rect().get_center()))
	food_material.set_shader_parameter("meal_food",item != null)
	if item != null:
		var meal_cuts: PackedVector4Array = pose.foodCuts.duplicate()
		meal_cuts.resize(12)
		food_material.set_shader_parameter("meal_cuts",meal_cuts)
		food_material.set_shader_parameter("cut_index",pose.foodCutIndex)
		food_material.set_shader_parameter("cut_progress",pose.foodCutProgress)
		food_material.set_shader_parameter("icon_frame",Vector4(item.bounds.position.x/item.pixel_size.x,item.bounds.position.y/item.pixel_size.y,item.bounds.size.x/item.pixel_size.x,item.bounds.size.y/item.pixel_size.y))
	var priority: float = 1.0 if pose.get("bowlHitActive",false) else preload("res://scripts/chewing_pose.gd").priority(pose)
	food.modulate.a = pose.get("pickupAlpha", 0.0) * priority
	bowl.modulate.a = pose.get("pickupBowl", 0.0) * priority
	food.visible = food.modulate.a > 0.00001
	food_material.set_shader_parameter("bite_cut",pose.get("biteCut",0.0))
	bowl.visible = bowl.modulate.a > 0.00001
	if pose.get("desktopBowl",false): bowl.hide()
	near_layers.apply(1.0 if amount(pose) > 0.00001 else 0.0)
	if has_far_palm: far_layers.apply(smoothstep(0.05,0.45,amount(pose)))
	bowl.transform = Transform2D(0.0, Vector2.ONE * bowl_scale, 0.0, BOWL_CENTER)
	if pose.get("mealActive",false):
		# The seated body lowers; the bowl remains on the desktop ground.
		bowl.transform = bowl.get_parent().transform.affine_inverse()*bowl.transform
	var flight: float = pose.get("pickupFlight", 0.0)
	var upper: Transform2D = landing_upper * upper_transform(body, pose) * Spine.upper_transform(body,pose)
	# Blend into the torso's attachment smoothly before contact, with no handoff snap.
	var target := food_target(body,pose)
	food.transform = Transform2D(deg_to_rad(-7.0) * sin(flight * PI) \
		+ upper.get_rotation() * smoothstep(0.55, 1.0, flight),
		Vector2.ONE * food_scale * lerpf(0.65, 1.0, smoothstep(0.0, 0.8, flight)), 0.0, target)
	if item != null:
		# The icon and both grip targets share the same local rotation, body
		# perspective and spine transform. Only hands come forward of the icon.
		var tilt: float = pose.get("pickupIconTilt",0.0)-deg_to_rad(7.0)*sin(flight*PI)
		var alignment := Transform2D.IDENTITY.interpolate_with(upper,smoothstep(0.55,1.0,flight))*body
		food.transform = alignment*Transform2D(tilt,Vector2.ONE*food_scale*lerpf(0.65,1.0,smoothstep(0.0,0.8,flight)),0.0,Vector2.ZERO)
		food.position = target
	hold_rig.apply(depth_meshes,body,upper,pose,food,amount(pose),near_layers,far_layers,original_order.ArtMesh26)
