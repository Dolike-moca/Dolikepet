extends RefCounted
## The selected B3 silhouette remains rigid and follows the current head affine.
const MOUTH = preload("res://assets/chewing/chewing_mouth.png")
const SWALLOW_MOUTH = preload("res://assets/chewing/swallow_mouth.png")
const CENTER := Vector2(745.0, 1055.5) - Vector2(1024, 1024)
const WIDTH := 74.0
const SWALLOW_WIDTH := 48.0
const DragPose = preload("res://scripts/drag_pose.gd")
const EYE_IDS := ["ArtMesh6", "ArtMesh7", "ArtMesh8", "ArtMesh9", "ArtMesh10", "ArtMesh11", "ArtMesh12", "ArtMesh13"]
var sprite: Sprite2D
var swallow_sprite: Sprite2D
var eyes: Array[Sprite2D] = []
var texture_scale := 1.0
var swallow_scale := 1.0
var bite_origin := CENTER

static func priority(pose: Dictionary) -> float:
	if pose.get("bowlHitActive",false): return 0.0
	if pose.get("dragHeld", false) or pose.get("fallActive", false) or pose.get("dizzyActive", false): return 0.0
	return (1.0 - pose.get("dragFace", 0.0)) * (1.0 - pose.get("fallFace", 0.0)) * (1.0 - pose.get("dizzyAlpha", 0.0))

func prepare(pose: Dictionary) -> Dictionary:
	var result := pose.duplicate()
	var weight := priority(pose)
	if weight <= 0.0: return result
	# In this accepted rig, 12 ParamAngleZ units = 1.2 degrees. Its existing
	# pivot/affine and scarf correction provide a nod with no neck translation.
	result.headZ = clampf(pose.headZ + (-12.0 * pose.get("chewNod", 0.0) \
		+ 6.0 * pose.get("chewReliefLift", 0.0)) * weight, -30.0, 30.0)
	result.mouth = lerpf(pose.mouth, 0.0, pose.get("chewSwallow", 0.0) * weight)
	# Reuse the existing closed-happy expression's native mouth, as referenced.
	result.mouth = lerpf(result.mouth, 1.0, pose.get("chewReliefSmile", 0.0) * weight)
	# Multiplying openness preserves a complete automatic/manual blink and
	# never reopens an eye that another expression has already closed.
	var openness := (1.0 - clampf(pose.get("chewSquint", 0.0), 0.0, 1.0) * weight) \
		* (1.0 - clampf(pose.get("chewEyeClose", 0.0), 0.0, 1.0) * weight)
	result.eyeNear = pose.eyeNear * openness
	result.eyeFar = pose.eyeFar * openness
	return result

func setup(model: Node2D, meshes: Dictionary) -> void:
	sprite = Sprite2D.new()
	sprite.name = "ChewingMouth"
	sprite.texture = MOUTH
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = meshes.ArtMesh3.z_index
	texture_scale = WIDTH / MOUTH.get_image().get_used_rect().size.x
	sprite.hide()
	model.add_child(sprite)
	swallow_sprite = Sprite2D.new()
	swallow_sprite.name = "SwallowMouth"
	swallow_sprite.texture = SWALLOW_MOUTH
	swallow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	swallow_sprite.z_index = sprite.z_index
	swallow_scale = SWALLOW_WIDTH / SWALLOW_MOUTH.get_image().get_used_rect().size.x
	# The supplied artwork needs one local horizontal flip. Whole-pet facing
	# still mirrors the complete face, so do not change this during a turn.
	swallow_sprite.flip_h = true
	swallow_sprite.hide()
	model.add_child(swallow_sprite)
	# Reuse the PSD-baked eyes and their near/far bounds exactly; no extra flip.
	for i in 2:
		var feature: Array = DragPose.FEATURES[i]
		var eye := Sprite2D.new()
		eye.name = "ChewingSqueezeEye%d" % i
		eye.texture = feature[0]
		eye.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		eye.z_index = meshes[feature[3]].z_index
		eye.hide()
		model.add_child(eye)
		eyes.append(eye)

func apply(meshes: Dictionary, head: Transform2D, pose: Dictionary) -> void:
	var alpha: float = clampf(pose.get("chewAlpha", 0.0), 0.0, 1.0)
	var swallow_alpha: float = clampf(pose.get("chewSwallowMouth", 0.0), 0.0, 1.0)
	var bite_alpha: float = clampf(pose.get("biteAlpha",0.0),0.0,1.0) * priority(pose)
	if priority(pose) <= 0.0:
		alpha = 0.0
		swallow_alpha = 0.0
	# Existing face passes already set their own priority. Preserve their fades.
	var base_visibility: float = meshes.ArtMesh3.self_modulate.a
	# Complementary bite/chew weights must keep the default mouth fully hidden.
	# Multiplying two independent fades used to reveal it during the handoff.
	for id in ["ArtMesh3", "ArtMesh4"]: meshes[id].self_modulate.a *= 1.0 - minf(1.0, alpha + swallow_alpha + bite_alpha)
	alpha *= base_visibility
	var center := bite_origin.lerp(CENTER,pose.get("biteSettle",1.0))
	sprite.transform = head * Transform2D(pose.get("chewAngle", 0.0),
		Vector2.ONE * texture_scale, 0.0, center + pose.get("chewOffset", Vector2.ZERO))
	sprite.modulate.a = alpha
	sprite.visible = alpha > 0.00001
	swallow_sprite.transform = head * Transform2D(0.0, Vector2.ONE * swallow_scale, 0.0, CENTER)
	swallow_sprite.modulate.a = swallow_alpha * base_visibility
	swallow_sprite.visible = swallow_sprite.modulate.a > 0.00001
	var squeeze: float = clampf(pose.get("chewSqueeze", 0.0), 0.0, 1.0) * priority(pose)
	for id in EYE_IDS: meshes[id].self_modulate.a *= 1.0 - squeeze
	for i in eyes.size():
		var feature: Array = DragPose.FEATURES[i]
		eyes[i].transform = head * Transform2D(0.0, feature[2] / feature[0].get_size(), 0.0,
			feature[1] - Vector2(1024, 1024))
		eyes[i].modulate.a = squeeze
		eyes[i].visible = squeeze > 0.00001
