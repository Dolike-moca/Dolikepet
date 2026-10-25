extends RefCounted
## Barycentric subdivision of the original Cubism triangles and atlas UVs.
## Core keeps its original meshes; these denser copies are used only in transition.

const Secondary = preload("res://scripts/secondary_deformation.gd")
const DIVISIONS := 4
var node: MeshInstance2D
var source_indices: Array[Vector3i] = []
var weights := PackedVector3Array()

func setup(original: MeshInstance2D) -> void:
	var surface: Array = original.mesh.surface_get_arrays(0)
	var source := Secondary.read_points(original)
	var uv: PackedVector2Array = surface[Mesh.ARRAY_TEX_UV]
	var triangles: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	var points := PackedVector2Array()
	var texcoords := PackedVector2Array()
	var indices := PackedInt32Array()
	for t in range(0, triangles.size(), 3):
		var abc := Vector3i(triangles[t], triangles[t + 1], triangles[t + 2])
		var grid := {}
		for i in range(DIVISIONS + 1):
			for j in range(DIVISIONS + 1 - i):
				var w := Vector3(1.0 - float(i + j) / DIVISIONS,
					float(i) / DIVISIONS, float(j) / DIVISIONS)
				grid[Vector2i(i, j)] = points.size()
				source_indices.append(abc)
				weights.append(w)
				points.append(source[abc.x] * w.x + source[abc.y] * w.y + source[abc.z] * w.z)
				texcoords.append(uv[abc.x] * w.x + uv[abc.y] * w.y + uv[abc.z] * w.z)
		for i in range(DIVISIONS):
			for j in range(DIVISIONS - i):
				indices.append_array(PackedInt32Array([
					grid[Vector2i(i, j)], grid[Vector2i(i + 1, j)], grid[Vector2i(i, j + 1)]]))
				if i + j < DIVISIONS - 1:
					indices.append_array(PackedInt32Array([
						grid[Vector2i(i + 1, j)], grid[Vector2i(i + 1, j + 1)], grid[Vector2i(i, j + 1)]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = texcoords
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_FLAG_USE_2D_VERTICES | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	node = MeshInstance2D.new()
	node.name = original.name + "_SittingTransition"
	node.mesh = mesh
	node.material = original.material
	node.z_index = original.z_index
	node.texture_filter = original.texture_filter
	node.hide()
	original.get_parent().add_child(node)

func sample(raw: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(weights.size())
	for i in weights.size():
		var abc := source_indices[i]
		var w := weights[i]
		result[i] = raw[abc.x] * w.x + raw[abc.y] * w.y + raw[abc.z] * w.z
	return result
