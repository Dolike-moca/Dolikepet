extends RefCounted
## Split at the cuff in the original arm coordinates. Both pieces sample the
## same final Cubism triangles, so the shoulder remains behind hair and scarf
## while only the hand can pass in front of food. No duplicated translucent edge.
const Secondary = preload("res://scripts/secondary_deformation.gd")
var original: MeshInstance2D
var pieces: Array = []
var replacement_material: ShaderMaterial

func setup(model: Node2D, source: MeshInstance2D, wrist_origin: Vector2,
		axis: Vector2, cut: float, hand_order: int, texture: Texture2D = null,
		art_rect: Rect2 = Rect2(), texture_rect: Rect2 = Rect2()) -> void:
	original = source
	var reference := Secondary.read_points(source)
	var arrays := source.mesh.surface_get_arrays(0)
	var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var material: Material = source.material
	if texture != null:
		# Explicit art registration excludes faint generated alpha outside the arm.
		var used := texture_rect if texture_rect.has_area() else Rect2(texture.get_image().get_used_rect())
		for i in uv.size():
			uv[i] = (used.position + (reference[i]-art_rect.position)/art_rect.size * used.size) / texture.get_size()
		material = source.material.duplicate()
		material.set_shader_parameter("tex_main", texture)
		replacement_material = material
	for front in [false,true]:
		var vertices := PackedVector2Array()
		var coords := PackedVector2Array()
		var samples := []
		for triangle in range(0,triangles.size(),3):
			var ids := Vector3i(triangles[triangle],triangles[triangle+1],triangles[triangle+2])
			var polygon: Array[Vector3] = [Vector3(1,0,0),Vector3(0,1,0),Vector3(0,0,1)]
			var clipped: Array[Vector3] = []
			for i in 3:
				var a := polygon[i]
				var b := polygon[(i+1)%3]
				var da := (sample(reference,ids,a)-wrist_origin).dot(axis)-cut
				var db := (sample(reference,ids,b)-wrist_origin).dot(axis)-cut
				if not front:
					da = -da
					db = -db
				if da >= 0.0: clipped.append(a)
				if (da >= 0.0) != (db >= 0.0): clipped.append(a.lerp(b,da/(da-db)))
			for i in range(1,clipped.size()-1):
				for weights in [clipped[0],clipped[i],clipped[i+1]]:
					vertices.append(sample(reference,ids,weights))
					coords.append(sample(uv,ids,weights))
					samples.append([ids,weights])
		var output := []
		output.resize(Mesh.ARRAY_MAX)
		output[Mesh.ARRAY_VERTEX] = vertices
		output[Mesh.ARRAY_TEX_UV] = coords
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,output)
		var node := MeshInstance2D.new()
		node.name = source.name + ("_HeldHand" if front else "_HeldSleeve")
		node.mesh = mesh
		node.material = material
		node.z_index = hand_order if front else source.z_index
		node.hide()
		model.add_child(node)
		pieces.append({"node":node,"samples":samples})

static func sample(points: PackedVector2Array, ids: Vector3i, weights: Vector3) -> Vector2:
	return points[ids.x]*weights.x + points[ids.y]*weights.y + points[ids.z]*weights.z

func apply(weight: float) -> void:
	weight = clampf(weight,0.0,1.0)
	original.self_modulate.a = 1.0-weight
	if replacement_material != null:
		# Core fills tint uniforms when rendering; a setup-time material copy
		# still has black defaults. Track the live drawable's current colors.
		for key in ["color_base","color_screen","color_multiply","channel"]:
			replacement_material.set_shader_parameter(key,original.material.get_shader_parameter(key))
	var points := Secondary.read_points(original)
	for piece in pieces:
		var node: MeshInstance2D = piece.node
		node.visible = weight > 0.00001 and original.visible
		node.modulate.a = weight
		if not node.visible: continue
		var output := PackedVector2Array()
		for entry in piece.samples: output.append(sample(points,entry[0],entry[1]))
		Secondary.write_points(node,output)
