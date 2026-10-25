extends RefCounted
## Waist-anchored curved spine; the complete neck/head share its rigid tip.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
const Face = preload("res://scripts/chewing_pose.gd")
const COLLAR := Vector2(Sitting.WAIST.x, 1280.0 - 1024.0)
const LENGTH := Sitting.WAIST.y - COLLAR.y
const BEND_DEGREES := 7.0
const SHIVER_DEGREES := 0.76 # About 2.4x the previous trembling amplitude.
const RELIEF_DEGREES := 0.85
const HAIR_GAIN := 4.0 # Keep this small local motion readable at desktop size.
const CURVED := ["ArtMesh24", "ArtMesh5", "ArtMesh20"] # torso, scarf, waist belt

static func angle(pose: Dictionary) -> float:
	return deg_to_rad(-BEND_DEGREES * clampf(pose.get("chewBend", 0.0), 0.0, 1.0)
		+ SHIVER_DEGREES * clampf(pose.get("chewShiver", 0.0), -1.0, 1.0)
		+ RELIEF_DEGREES * clampf(pose.get("chewReliefRock", 0.0), -1.0, 1.0)) * Face.priority(pose)

static func bend_point(point: Vector2, radians: float) -> Vector2:
	var height := Sitting.WAIST.y - point.y
	if height <= 0.0 or absf(radians) < 0.000001: return point
	var along := minf(height, LENGTH)
	var turn := radians * along / LENGTH
	var radius := LENGTH / radians
	var center := Sitting.WAIST + Vector2(radius * (1.0 - cos(turn)), -radius * sin(turn))
	return center + Vector2(point.x - Sitting.WAIST.x, -maxf(0.0, height - LENGTH)).rotated(turn)

static func upper_transform(body: Transform2D, pose: Dictionary) -> Transform2D:
	var radians := angle(pose)
	if absf(radians) < 0.000001: return Transform2D.IDENTITY
	var local := Transform2D(radians, Vector2.ZERO)
	local.origin = bend_point(COLLAR, radians) - local * COLLAR
	return body * local * body.affine_inverse()

func apply(meshes: Dictionary, body: Transform2D, pose: Dictionary, faces: Array) -> void:
	var radians := angle(pose)
	if absf(radians) < 0.000001: return
	var upper := upper_transform(body, pose)
	var inverse := body.affine_inverse()
	for id in meshes:
		# Standing legs, seated replacement, skirt and tail keep their support.
		if id in Sitting.LOWER_IDS or id == "ArtMesh28": continue
		var points := Secondary.read_points(meshes[id])
		for i in points.size():
			points[i] = body * bend_point(inverse * points[i], radians) if id in CURVED else upper * points[i]
		Secondary.write_points(meshes[id], points)
	for sprite in faces:
		if sprite.visible: sprite.transform = upper * sprite.transform
