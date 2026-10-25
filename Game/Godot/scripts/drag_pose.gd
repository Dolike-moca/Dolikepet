extends RefCounted
## Held pose over fresh Live2D meshes; head/neck/scarf top share a rigid root.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Walking = preload("res://scripts/walking_pose.gd")
const Leg = preload("res://scripts/walking_leg.gd")
const FACE_IDS := ["ArtMesh3", "ArtMesh4", "ArtMesh6", "ArtMesh7", "ArtMesh8", "ArtMesh9",
	"ArtMesh10", "ArtMesh11", "ArtMesh12", "ArtMesh13"]
# Baked smart-object pixels and exact bounds from feat/拖拽调整.psd.
# PSD layer L is the near eye, R is the far eye; names are not screen-left/right.
const FEATURES := [
	[preload("res://assets/drag/drag_eye_far_psd.png"), Vector2(585, 914), Vector2(132, 158), "ArtMesh8"],
	[preload("res://assets/drag/drag_eye_near_psd.png"), Vector2(871, 891), Vector2(178, 166), "ArtMesh6"],
	[preload("res://assets/drag/drag_mouth_psd.png"), Vector2(737.5, 1050.5), Vector2(91, 27), "ArtMesh3"],
]
const PIVOT := Vector2(860, 460) - Vector2(1024, 1024)
# Lock the entire neck and scarf top. Curvature starts below the collar and
# becomes a rigid lower-body transform below the hips, preserving boot shapes.
const BEND_ORIGIN := Vector2(870, 1290) - Vector2(1024, 1024)
const BEND_LENGTH := 270.0
const TAIL_ROOT := Vector2(900, 1485) - Vector2(1024, 1024)
var sprites: Array[Sprite2D] = []
var rig_legs = Leg.new()

func setup(model: Node2D, meshes: Dictionary, contours: Dictionary) -> void:
	rig_legs.setup(contours)
	for feature in FEATURES:
		var sprite := Sprite2D.new()
		sprite.texture = feature[0]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.z_index = meshes[feature[3]].z_index
		sprite.hide()
		model.add_child(sprite)
		sprites.append(sprite)

func root_transform(base: Transform2D, pose: Dictionary, facing: float) -> Transform2D:
	var hang: float = pose.get("dragHang", 0.0)
	var tilt: float = pose.get("dragTilt", 0.0) * signf(facing)
	var root := Transform2D(tilt, Vector2.ZERO)
	root.origin = PIVOT - root * PIVOT + Vector2(0.0, 0.0 if pose.get("physicsActive", false) else -14.0 * hang)
	return root * base

static func bend_point(point: Vector2, angle: float, stretch: float) -> Vector2:
	var q := point - BEND_ORIGIN
	if q.y <= 0.0: return point
	var along := minf(q.y, BEND_LENGTH)
	var a := angle * along / BEND_LENGTH
	var center := Vector2(0.0, along)
	if absf(angle) > 0.000001:
		var radius := BEND_LENGTH / angle
		center = Vector2(radius * (cos(a) - 1.0), radius * sin(a))
	# Small axial give lives below the scarf, not between the head and neck.
	center.y += stretch * along
	# Waist narrows slightly under tension, then returns to its original width
	# at the hips. Boots and the neck remain rigid, not scaled with the torso.
	var waist := pow(sin(PI * along / BEND_LENGTH), 2.0)
	var width := 1.0 - stretch * 0.8 * waist
	return BEND_ORIGIN + center + Vector2(q.x * width, maxf(0.0, q.y - BEND_LENGTH)).rotated(a)

static func bend_tail_point(point: Vector2, angle: float, stretch: float) -> Vector2:
	# Tail sections already bend along their own spine. Attach that whole spine
	# rigidly to the hip; an upturned tip must not enter the torso stretch field.
	var hip_angle := angle * clampf((TAIL_ROOT.y - BEND_ORIGIN.y) / BEND_LENGTH, 0.0, 1.0)
	return bend_point(TAIL_ROOT, angle, stretch) + (point - TAIL_ROOT).rotated(hip_angle)

func apply(model: Node2D, meshes: Dictionary, raw: Dictionary, head: Transform2D,
		body: Transform2D, pose: Dictionary, sitting_amount: float) -> void:
	var face: float = pose.get("dragFace", 0.0)
	for id in FACE_IDS:
		meshes[id].self_modulate.a = 1.0 - face
	for i in sprites.size():
		var feature: Array = FEATURES[i]
		var scale: Vector2 = feature[2] / feature[0].get_size()
		sprites[i].transform = head * Transform2D(0.0, scale, 0.0, feature[1] - Vector2(1024, 1024))
		sprites[i].modulate.a = face
		sprites[i].visible = face > 0.0
	var hang: float = pose.get("dragHang", 0.0)
	if hang <= 0.00001:
		return
	var t: float = pose.get("dragTime", 0.0)
	var facing: float = signf(pose.get("facingScale", 1.0))
	var swing: float = clampf(pose.get("dragSwingSpeed", 0.0) * facing, -2.5, 2.5)
	var tension := clampf(pose.get("dragStretch", 0.0) / 0.12, 0.0, 1.0)
	var inverse := body.affine_inverse()
	var limp: float = pose.get("juggleWeight",0.0)
	var lag: float = pose.get("juggleLimbs",0.0)*facing
	for id in Walking.SHOULDERS:
		var near: bool = id == "ArtMesh19"
		var shoulder: Vector2 = Walking.SHOULDERS[id]
		if not near:
			shoulder += Walking.FAR_ARM_SHOULDER_OFFSET
		# The far hand stays smaller and lower, as in the accepted PSD reference.
		var angle := deg_to_rad((-25.0 - 5.0 * sin(t * 11.0)) if near else (18.0 + 4.0 * sin(t * 11.0 + 1.3)))
		angle += swing * (0.11 if near else 0.08)
		angle += deg_to_rad(-5.0 if near else 4.0) * tension
		if limp>0.0:
			# Rotate complete arms at the confirmed sockets. No length scaling,
			# no z-order swaps; a small outward gap keeps sleeves off braids.
			angle = lerpf(angle,deg_to_rad(9.0 if near else -7.0)+lag*(1.0 if near else 0.8),limp)
		var points := Secondary.read_points(meshes[id]) # Includes the reference far-arm pose and fading gait.
		for i in points.size():
			var local := inverse * points[i]
			points[i] = body * (shoulder + (local - shoulder).rotated(angle * hang))
		Secondary.write_points(meshes[id], points)
	var leg_weight := hang * (1.0 - smoothstep(0.0, 0.10, sitting_amount))
	for id in Leg.HIPS:
		if leg_weight <= 0.00001:
			continue
		var near: bool = id == "ArtMesh22"
		var phase := t * 9.0 + (0.0 if near else 2.3)
		var flex := deg_to_rad(5.0 + 3.0 * sin(phase) - tension * 1.8) * leg_weight
		var hip_angle := deg_to_rad(4.0 * sin(phase)) * leg_weight + flex * 0.62
		hip_angle += swing * (0.045 if near else 0.035) * leg_weight
		if limp>0.0:
			flex = lerpf(flex,deg_to_rad(10.0 if near else 8.0)*leg_weight,limp)
			hip_angle = lerpf(hip_angle,lag*0.45*leg_weight+flex*0.55,limp)
		var hip: Vector2 = Leg.HIPS[id]
		var knee: Vector2 = Leg.KNEES[id]
		var points := Secondary.read_points(meshes[id])
		for i in points.size():
			var local := inverse * points[i]
			points[i] = body * rig_legs._bend(local, hip, knee, hip_angle, -flex)
		Secondary.write_points(meshes[id], points)
	# Only the hem follows the suspended body; the belt/waist attachment stays put.
	if sitting_amount == 0.0 and hang > 0.0:
		var skirt := Secondary.read_points(meshes["ArtMesh21"])
		for i in skirt.size():
			var local := inverse * skirt[i]
			var hem := smoothstep(1460.0, 1790.0, local.y + 1024.0)
			local.x += sin(t * 4.5 - 0.5) * 4.0 * hem * hang
			skirt[i] = body * local
		Secondary.write_points(meshes["ArtMesh21"], skirt)
	# Do not bend while the seated replacement is visible: let the existing
	# matched transition unfold first. All layers then use the same smooth map.
	var weight := 1.0 - smoothstep(0.0, 0.10, sitting_amount)
	var bend: float = pose.get("dragBend", 0.0) * facing * weight
	var stretch: float = pose.get("dragStretch", 0.0) * weight
	if absf(bend) + absf(stretch) > 0.000001:
		for id in meshes:
			var node: MeshInstance2D = meshes[id]
			var points := Secondary.read_points(node)
			for i in points.size():
				points[i] = body * (bend_tail_point(inverse * points[i], bend, stretch) if id == "ArtMesh28" else bend_point(inverse * points[i], bend, stretch))
			Secondary.write_points(node, points)
