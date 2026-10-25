extends RefCounted
## GDCubism shares each drawable's ArrayMesh with its clipping viewport.
## Refit that viewport after our runtime deformations, using the final bounds.
var groups: Array = []
var size_limit := 0

func setup(model: Node2D, meshes: Dictionary) -> void:
	groups.clear()
	size_limit = model.get("mask_viewport_size")
	for child in model.get_children():
		if not child is SubViewport or not str(child.name).ends_with("__mask"): continue
		var sources: Array = []
		for source in child.get_children():
			if source is MeshInstance2D: sources.append(source)
		var materials: Array = []
		for mesh in meshes.values():
			var material: ShaderMaterial = mesh.material
			var texture = material.get_shader_parameter("tex_mask")
			if texture is ViewportTexture and texture.get_rid() == child.get_texture().get_rid():
				materials.append(material)
		if not sources.is_empty() and not materials.is_empty():
			groups.append({"viewport": child, "sources": sources, "materials": materials})

func refresh() -> void:
	for group in groups:
		var bounds := Rect2()
		var first := true
		for source in group.sources:
			var aabb: AABB = source.mesh.custom_aabb
			var rect := Rect2(Vector2(aabb.position.x, aabb.position.y), Vector2(aabb.size.x, aabb.size.y))
			RenderingServer.canvas_item_set_custom_rect(source.get_canvas_item(), true, rect)
			bounds = rect if first else bounds.merge(rect)
			first = false
		bounds = bounds.grow(4.0)
		var scalar := 1.0
		if size_limit > 0: scalar = minf(1.0, float(size_limit) / maxf(bounds.size.x, bounds.size.y))
		var viewport: SubViewport = group.viewport
		viewport.size = Vector2i(maxi(2, ceili(bounds.size.x * scalar)), maxi(2, ceili(bounds.size.y * scalar)))
		viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scalar, 0.0, -bounds.position * scalar)
		for material in group.materials:
			material.set_shader_parameter("mask_scale", scalar)
			material.set_shader_parameter("mesh_offset", bounds.position)
