extends RefCounted
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Leg = preload("res://scripts/walking_leg.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
const COLLAR_Y := 1280.0 - 1024.0
const FACE_IDS := ["ArtMesh3", "ArtMesh4", "ArtMesh6", "ArtMesh7", "ArtMesh8", "ArtMesh9", "ArtMesh10", "ArtMesh11", "ArtMesh12", "ArtMesh13"]
const FEATURES := [
	[preload("res://assets/landing/dizzy_eyeL_psd.png"), Vector2(900.5, 903), Vector2(221, 210)],
	[preload("res://assets/landing/dizzy_eyeR_psd.png"), Vector2(607.5, 921), Vector2(155, 206)],
	[preload("res://assets/landing/dizzy_mouth_psd.png"), Vector2(744, 1049.5), Vector2(116, 25)],
]
var sprites: Array[Sprite2D] = []
var lowering := Vector2.ZERO
var knee_amount := 0.0
var support_weight := 0.0
var upper_tilt := 0.0

func setup(model: Node2D, meshes: Dictionary) -> void:
	for feature in FEATURES:
		var sprite := Sprite2D.new()
		sprite.texture = feature[0]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# PSD order: over sidelocks, under the front hair. These are baked pixels.
		sprite.z_index = meshes.ArtMesh1.z_index - 1
		sprite.hide()
		model.add_child(sprite)
		sprites.append(sprite)

func prepare(pose: Dictionary) -> Dictionary:
	var result := pose.duplicate()
	var influence: float = pose.get("landingInfluence", 0.0)
	if influence > 0.0:
		result.dragHang = pose.get("dragHang", 0.0) * (1.0 - influence)
		result.dragStretch = pose.get("dragStretch", 0.0) * (1.0 - influence)
		result.fallStretch = pose.get("fallStretch", 0.0) * (1.0 - influence)
		result.walkWeight = 0.0
	if pose.get("dizzyActive", false):
		result.bodyX = pose.get("bodyX", 0.0) * (1.0 - influence)
		result.headX = 0.0
		result.headY = -0.12 * pose.get("dizzyRehit", 0.0)
		result.headZ = pose.get("dizzyWobble", 0.0) - 2.0 * pose.get("dizzyRehit", 0.0)
		result.gazeX = 0.0
		result.gazeY = 0.0
		result.mouth = 0.0
	if pose.get("dizzyEyeOverride", false):
		result.eyeNear = pose.get("dizzyOpenness", 1.0)
		result.eyeFar = result.eyeNear
	return result

func deform(raw: Dictionary, body: Transform2D, amount: float, seated_amount: float) -> Dictionary:
	# Apply before Sitting samples the meshes, so bending blends into the same
	# accepted standing-to-seated transition instead of popping at texture swap.
	knee_amount = amount * (1.0 - smoothstep(0.0, 0.22, seated_amount))
	var seated_drop := 154.0 * smoothstep(0.10, 1.0, seated_amount)
	# Keep the initial absorption until the seated root has taken over that
	# height. Otherwise fading the knee first briefly lifts the body back up.
	var drop := maxf(22.0 * knee_amount, 22.0 * amount - seated_drop)
	lowering = body.basis_xform(Vector2(0, drop))
	if drop <= 0.000001: return raw
	var result := raw.duplicate()
	var inverse := body.affine_inverse()
	for id in Leg.HIPS:
		var hip: Vector2 = Leg.HIPS[id]
		var knee: Vector2 = Leg.KNEES[id]
		var ratio := (knee.y - hip.y) / (Leg.CUFF_Y - hip.y)
		var points: PackedVector2Array = raw[id].duplicate()
		for i in points.size():
			var p := inverse * points[i]
			var u := clampf((p.y - hip.y) / (Leg.CUFF_Y - hip.y), 0.0, 1.0)
			var phase := 0.5 * u / ratio if u < ratio else 0.5 + 0.5 * (u - ratio) / (1.0 - ratio)
			p.x -= (40.0 if id == "ArtMesh22" else 34.0) * sin(PI * phase) * knee_amount
			p.y -= drop * smoothstep(0.0, 1.0, u)
			points[i] = body * p
		result[id] = points
		# All boot vertices get the same translation. The root lowers by the
		# opposite amount, fixing heel and toe with no shoe scaling or rotation.
	return result

func root_pose(pose: Dictionary, seated_amount: float) -> Dictionary:
	support_weight = smoothstep(0.05, 0.74, seated_amount) if pose.get("dizzyActive", false) else 0.0
	if not pose.get("dizzyActive", false) and pose.get("floorSupported", false):
		# A soft landing also keeps its feet planted while the native collider
		# rights itself; the remaining roll belongs to the upper body.
		support_weight = pose.get("landingInfluence", 1.0) if pose.get("landingActive", false) else 1.0
	upper_tilt = pose.get("dragTilt", 0.0) * signf(pose.get("facingScale", 1.0)) * support_weight
	upper_tilt += pose.get("dizzyUpperSway", 0.0) * support_weight
	upper_tilt += pose.get("landingUpperTilt", 0.0)
	var result := pose.duplicate()
	result.dragTilt = pose.get("dragTilt", 0.0) * (1.0 - support_weight)
	return result

func apply_root(model: Node2D, placement: Transform2D, pose: Dictionary) -> void:
	model.position += model.transform.basis_xform(lowering)
	# Counter only vertical movement from the already-contacting collider.
	# The native body's floor constraint owns the horizontal support position.
	model.position += placement.affine_inverse().basis_xform(Vector2(0,
		pose.get("landingGroundOffset", 0.0) * support_weight))

func apply_upper(meshes: Dictionary, body: Transform2D, pose: Dictionary, faces: Array) -> void:
	var compression: float = pose.get("landingUpperBounce", 0.0)
	if absf(compression) + absf(upper_tilt) < 0.000001: return
	var waist: Vector2 = Sitting.WAIST
	var depth := waist.y - COLLAR_Y
	var inverse := body.affine_inverse()
	for id in meshes:
		if id in Sitting.LOWER_IDS or id == "ArtMesh28": continue
		var node: MeshInstance2D = meshes[id]
		var points := Secondary.read_points(node)
		for i in points.size():
			var p := inverse * points[i]
			var weight := 1.0 - smoothstep(COLLAR_Y, waist.y, p.y)
			var rotated := waist + (p - waist).rotated(upper_tilt)
			p += (rotated - p) * weight
			p.y += compression * clampf(waist.y - (inverse * points[i]).y, 0.0, depth)
			points[i] = body * p
		Secondary.write_points(node, points)
	# The complete head and scarf top use the same rigid transform; expression
	# centers stay attached and the neck never stretches during the recoil.
	var transformed := upper_transform(body, pose)
	for sprite in faces:
		if sprite.visible: sprite.transform = transformed * sprite.transform

func upper_transform(body: Transform2D, pose: Dictionary) -> Transform2D:
	var waist: Vector2 = Sitting.WAIST
	var compression: float = pose.get("landingUpperBounce", 0.0)
	var head_motion := Transform2D(upper_tilt, Vector2.ZERO)
	head_motion.origin = waist - head_motion * waist + Vector2(0, compression * (waist.y - COLLAR_Y))
	return body * head_motion * body.affine_inverse()

func apply_face(meshes: Dictionary, head: Transform2D, pose: Dictionary, falling_sprite: Sprite2D) -> void:
	var alpha: float = pose.get("dizzyAlpha", 0.0) * (1.0 - pose.get("dragFace", 0.0))
	for id in FACE_IDS: meshes[id].self_modulate.a *= 1.0 - alpha
	falling_sprite.modulate.a *= 1.0 - alpha
	for i in sprites.size():
		var feature: Array = FEATURES[i]
		var angle: float = pose.get("dizzyAngle", 0.0) * (1.0 if i == 0 else -0.96) if i < 2 else 0.0
		# Rotate in normalized eye space, then restore the PSD's far-eye aspect.
		# A narrow eye never turns sideways into a wide horizontal ellipse.
		var placement := Transform2D(0.0, feature[2], 0.0, feature[1] - Vector2(1024, 1024))
		var pixels := Transform2D(0.0, Vector2.ONE / feature[0].get_size(), 0.0, Vector2.ZERO)
		sprites[i].transform = head * placement * Transform2D(angle, Vector2.ZERO) * pixels
		sprites[i].modulate.a = alpha
		sprites[i].visible = alpha > 0.00001
