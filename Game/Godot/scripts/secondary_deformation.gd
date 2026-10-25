extends RefCounted
## Same scarf correction and hair bending as secondary-deformation.mjs.
## GDCubism meshes use pixels around the canvas origin, with +Y downward.

const HAIR = {
	"ArtMesh1": ["hairFront", 260.0, 1196.0, 17.0, false],
	"ArtMesh2": ["hairSide", 657.0, 1231.0, 23.0, false],
	"ArtMesh27": ["hairBack", 278.0, 1857.0, 34.0, false],
	"ArtMesh17": ["hairBraidNear", 939.0, 1571.0, 14.0, false],
	"ArtMesh25": ["hairBraidFar", 1012.0, 1471.0, 16.0, false],
	"ArtMesh": ["hairTuft", 78.0, 381.0, 18.0, true],
}
var reference: Dictionary = {}
var samplers: Dictionary = {}
var canvas_origin_y := 1024.0

static func read_points(node: MeshInstance2D) -> PackedVector2Array:
	if node.mesh == null or node.mesh.get_surface_count() == 0:
		return PackedVector2Array()
	var points = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if points is PackedVector2Array:
		return points
	var result := PackedVector2Array()
	for point in points:
		result.append(Vector2(point.x, point.y))
	return result

func capture(meshes: Dictionary, origin_y: float) -> void:
	canvas_origin_y = origin_y
	reference.clear()
	for id in meshes:
		reference[id] = read_points(meshes[id])
	for id in ["ArtMesh18", "ArtMesh24"]:
		samplers[id] = _sample_triangle(reference[id])

static func _sample_triangle(points: PackedVector2Array) -> Array[int]:
	var second := 1
	for i in range(2, points.size()):
		if points[i].distance_squared_to(points[0]) > points[second].distance_squared_to(points[0]):
			second = i
	var third := 0
	var area := 0.0
	var axis := points[second] - points[0]
	for i in points.size():
		var candidate := absf(axis.cross(points[i] - points[0]))
		if candidate > area:
			area = candidate
			third = i
	return [0, second, third]

func _affine(id: String, current: PackedVector2Array) -> Transform2D:
	var indices: Array = samplers[id]
	var source: PackedVector2Array = reference[id]
	var a: int = indices[0]
	var b: int = indices[1]
	var c: int = indices[2]
	var before := Transform2D(source[b] - source[a], source[c] - source[a], source[a])
	if absf(before.determinant()) < 0.00000001:
		return Transform2D.IDENTITY
	var after := Transform2D(current[b] - current[a], current[c] - current[a], current[a])
	return after * before.affine_inverse()

func deform_points(id: String, raw: PackedVector2Array, pose: Dictionary,
		head: Transform2D, body: Transform2D) -> PackedVector2Array:
	var output := raw.duplicate()
	var neutral: PackedVector2Array = reference[id]
	for i in raw.size():
		var point := neutral[i]
		var psd_y := canvas_origin_y + point.y
		if id == "ArtMesh5":
			var weight := 1.0 - smoothstep(0.0, 1.0, clampf((psd_y - 1160.0) / 130.0, 0.0, 1.0))
			output[i] += (head * point - body * point) * weight
		else:
			var layer: Array = HAIR[id]
			var t := clampf((psd_y - layer[1]) / (layer[2] - layer[1]), 0.0, 1.0)
			if layer[4]:
				t = 1.0 - t
			var weight := pow(smoothstep(0.0, 1.0, clampf((t - 0.18) / 0.82, 0.0, 1.0)), 2.0)
			var offset := Vector2(
				clampf(pose.get(layer[0], 0.0), -1.15, 1.15) * layer[3] * weight,
				-clampf(pose.get(layer[0] + "Y", 0.0), -1.15, 1.15) * (6.0 if layer[0] == "hairBack" else 3.0) * weight)
			var gait: Dictionary = pose.get("walkingHair", {})
			offset += Vector2(gait.get(layer[0], Vector2.ZERO)) * weight
			var inertia: Dictionary = pose.get("motionHair", {})
			offset += Vector2(inertia.get(layer[0], Vector2.ZERO)) * weight
			var falling: Dictionary = pose.get("fallingHair", {})
			var asymmetry := 1.0 + 0.045 * clampf((point.x + 1024.0 - 860.0) / 600.0, -1.0, 1.0)
			offset += Vector2(falling.get(layer[0], Vector2.ZERO)) * weight * asymmetry
			output[i] += head.basis_xform(offset)
	return output

func apply(meshes: Dictionary, pose: Dictionary, raw: Dictionary) -> void:
	# advance() restores the fresh Cubism geometry before every call.
	var head := _affine("ArtMesh18", raw["ArtMesh18"])
	var body := _affine("ArtMesh24", raw["ArtMesh24"])
	var ids: Array = HAIR.keys()
	ids.append("ArtMesh5")
	for id in ids:
		var node: MeshInstance2D = meshes[id]
		var points := deform_points(id, raw[id], pose, head, body)
		write_points(node, points)

static func write_points(node: MeshInstance2D, points: PackedVector2Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(points.size() * 8)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for i in points.size():
		bytes.encode_float(i * 8, points[i].x)
		bytes.encode_float(i * 8 + 4, points[i].y)
		bounds = bounds.expand(points[i])
	node.mesh.surface_update_vertex_region(0, 0, bytes)
	node.mesh.custom_aabb = AABB(
		Vector3(bounds.position.x, bounds.position.y, 0),
		Vector3(bounds.size.x, bounds.size.y, 0))
	RenderingServer.canvas_item_set_custom_rect(node.get_canvas_item(), true, bounds)
