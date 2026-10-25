extends RefCounted
## A soft knee bend in the existing Cubism ArtMesh; boots move as one piece.
const HIPS := {
	"ArtMesh22": Vector2(1040, 1540) - Vector2(1024, 1024),
	"ArtMesh23": Vector2(765, 1540) - Vector2(1024, 1024),
}
const KNEES := {
	"ArtMesh22": Vector2(1030, 1710) - Vector2(1024, 1024),
	"ArtMesh23": Vector2(795, 1695) - Vector2(1024, 1024),
}
const CUFF_Y := 1760.0 - 1024.0
var soles: Dictionary = {}

func setup(boot_contours: Dictionary) -> void:
	soles.clear()
	for id in HIPS:
		var contour: Dictionary = boot_contours[id]
		var center := Vector2(contour.sourceCenter[0], contour.sourceCenter[1])
		var radii: Array = contour.sourceRadii
		var points := PackedVector2Array()
		# Lower half of the measured boot outline, including both heel and toe.
		for i in range(radii.size() / 2 + 1):
			var angle := TAU * i / radii.size()
			points.append(center + Vector2(cos(angle), sin(angle)) * float(radii[i]))
		soles[id] = points

func _bend(point: Vector2, hip: Vector2, knee: Vector2,
		hip_angle: float, knee_angle: float) -> Vector2:
	# All pixels below the cuff use one rigid transform. Blend only in the leg
	# above it, avoiding a hard hinge or stretched laces/soles.
	var knee_weight := smoothstep(knee.y - 60.0, CUFF_Y, point.y)
	var bent := point.lerp(knee + (point - knee).rotated(knee_angle), knee_weight)
	return hip + (bent - hip).rotated(hip_angle)

func deform_points(id: String, raw: PackedVector2Array, body: Transform2D,
		phase: float, weight: float, body_bounce: float) -> PackedVector2Array:
	if weight <= 0.00001:
		return raw.duplicate()
	var hip: Vector2 = HIPS[id]
	var knee: Vector2 = KNEES[id]
	# The swing leg bends while lifted, then straightens smoothly for contact.
	# The opposite leg has cos(phase) <= 0 and remains extended in support.
	var swing := pow(maxf(0.0, cos(phase)), 2.0)
	var flex := deg_to_rad((8.0 if id == "ArtMesh22" else 7.0) * swing * weight)
	var hip_angle := deg_to_rad(7.2 * sin(phase) * weight) + flex * 0.62
	var knee_angle := -flex # Original artwork faces left: calf folds backward/right.
	var neutral_floor := -INF
	var posed_floor := -INF
	for point in soles[id]:
		neutral_floor = maxf(neutral_floor, (body * point).y)
		posed_floor = maxf(posed_floor,
			(body * _bend(point, hip, knee, hip_angle, knee_angle)).y)
	# Keep the support sole on its own reference plane (far/near perspective),
	# while the swing sole lifts. Account for the whole body's vertical motion.
	var foot_y := neutral_floor - posed_floor - body_bounce - 12.0 * swing * weight
	var inverse := body.affine_inverse()
	var result := raw.duplicate()
	for i in result.size():
		var point := inverse * raw[i]
		var foot_weight := smoothstep(hip.y + 25.0, CUFF_Y, point.y)
		result[i] = body * _bend(point, hip, knee, hip_angle, knee_angle)
		result[i].y += foot_y * foot_weight
	return result
