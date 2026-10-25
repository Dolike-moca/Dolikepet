extends RefCounted
## PSD expression and gentle torso tension; no landing bounce or neck scaling.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const DragPose = preload("res://scripts/drag_pose.gd")
const MOUTH = preload("res://assets/falling/surprised_mouth_psd.png")
const MOUTH_CENTER := Vector2(741, 1047) - Vector2(1024, 1024)
const MAX_STRETCH := 0.065
var face := 0.0
var stretch := 0.0
var sprite: Sprite2D

func setup(model: Node2D, meshes: Dictionary) -> void:
	sprite = Sprite2D.new()
	sprite.name = "FallingSurprisedMouth"
	sprite.texture = MOUTH
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = meshes.ArtMesh3.z_index
	sprite.hide()
	model.add_child(sprite)

func update(pose: Dictionary, dt: float, sitting_amount: float) -> Dictionary:
	var active: bool = pose.get("fallActive", false)
	var h := 0.0 if pose.get("fallPaused", false) else clampf(dt, 0.0, 0.1)
	face = move_toward(face, 1.0 if active else 0.0, h / 0.10)
	var target := 0.0
	if active:
		target = MAX_STRETCH * smoothstep(0.0, 2.6, pose.get("fallSpeed", 0.0))
	# No underdamped spring on release: return to neutral without an extra bounce.
	stretch = lerpf(stretch, target, 1.0 - exp(-14.0 * h))
	if absf(stretch - target) < 0.00001: stretch = target
	var result := pose.duplicate()
	result.fallFace = face
	result.fallStretch = stretch * (1.0 - smoothstep(0.0, 0.10, sitting_amount)) \
		* (1.0 - pose.get("dragHang", 0.0))
	var visible_face: float = face * (1.0 - pose.get("dragFace", 0.0))
	# The PSD uses the unchanged normal eye/brow layers. Neutralize the live eye
	# and gaze parameters while surprised, then restore the user's expression.
	for key in ["eyeNear", "eyeFar"]:
		result[key] = lerpf(pose[key], 1.0, visible_face)
	for key in ["gazeX", "gazeY", "mouth"]:
		result[key] = lerpf(pose[key], 0.0, visible_face)
	return result

func apply(meshes: Dictionary, head: Transform2D, body: Transform2D, pose: Dictionary) -> void:
	var fall_face: float = pose.get("fallFace", 0.0)
	# DragPose reset these original mouth alphas this frame; preserve its priority.
	for id in ["ArtMesh3", "ArtMesh4"]:
		meshes[id].self_modulate.a *= 1.0 - fall_face
	sprite.transform = head * Transform2D(0.0, MOUTH_CENTER)
	sprite.modulate.a = fall_face * (1.0 - pose.get("dragFace", 0.0))
	sprite.visible = sprite.modulate.a > 0.0
	var amount: float = pose.get("fallStretch", 0.0)
	if amount <= 0.000001: return
	var inverse := body.affine_inverse()
	for id in meshes:
		var node: MeshInstance2D = meshes[id]
		var points := Secondary.read_points(node)
		for i in points.size():
			points[i] = body * (DragPose.bend_tail_point(inverse * points[i], 0.0, amount) if id == "ArtMesh28" else DragPose.bend_point(inverse * points[i], 0.0, amount))
		Secondary.write_points(node, points)
