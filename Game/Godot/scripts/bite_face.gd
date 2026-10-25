extends RefCounted
## Deform below the artwork's W lip, so the lip and fang stay registered.
const Chewing = preload("res://scripts/chewing_pose.gd")
const ART = preload("res://assets/biting/cat_bite.png")
const WIDTH := 116.0
const OPEN_TILT := -7.0 * PI / 180.0
const ANCHOR := Chewing.CENTER + Vector2(0.0,-12.0)
const COLUMNS := 64
const ROWS := 18
var mouth: MeshInstance2D
var rect := Rect2i()
var source := PackedVector2Array()
var uvs := PackedVector2Array()
var lips := PackedFloat32Array()
var indices := PackedInt32Array()
var last_open := -1.0
var source_anchor := Vector2.ZERO
var art_scale := 1.0
var closed_center := Vector2.ZERO

func setup(model: Node2D, meshes: Dictionary) -> void:
	mouth = MeshInstance2D.new()
	mouth.name = "BiteCatMouth"
	mouth.texture = ART
	# Collapsing the jaw has extreme anisotropy. Isotropic mipmaps erase the
	# W stroke as the lower mouth flattens; retain filtering along the lip.
	mouth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mouth.z_index = meshes.ArtMesh3.z_index
	mouth.hide()
	model.add_child(mouth)
	var image := ART.get_image()
	if image.is_compressed(): image.decompress()
	# Generated PNGs can contain isolated almost-transparent pixels far from
	# the art. Register the visible contour, while retaining the source alpha.
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	var low := image.get_size()
	var high := Vector2i.ZERO
	for y in image.get_height():
		for x in image.get_width():
			if bytes[(y*image.get_width()+x)*4+3] > 24:
				low = low.min(Vector2i(x,y))
				high = high.max(Vector2i(x+1,y+1))
	rect = Rect2i(low,high-low).grow(2)
	art_scale = WIDTH / rect.size.x
	var profile := PackedFloat32Array()
	for column in COLUMNS+1:
		var x := lerpf(rect.position.x,rect.end.x-1,float(column)/COLUMNS)
		# Extend the lip at the extreme rounded sidewalls, avoiding a vertical
		# silhouette edge being mistaken for the upper W when closing.
		var sample_x := int(clampf(x,rect.position.x+rect.size.x*0.035,rect.end.x-rect.size.x*0.035))
		var lip := float(rect.position.y)
		for y in range(rect.position.y,rect.end.y):
			if image.get_pixel(sample_x,y).a > 0.16:
				lip = float(y)
				break
		profile.append(lip)
	source_anchor = Vector2(rect.get_center().x,profile[COLUMNS/2])
	var rim := rect.size.x * 0.024
	for column in COLUMNS+1:
		var x := lerpf(rect.position.x,rect.end.x-1,float(column)/COLUMNS)
		var lip := profile[column]
		for row in ROWS+1:
			var y := lip-5.0 if row == 0 else lerpf(lip+rim,rect.end.y,float(row-1)/(ROWS-1))
			source.append(Vector2(x,y))
			uvs.append(Vector2(x,y)/Vector2(image.get_size()))
			lips.append(lip+rim)
	for column in COLUMNS:
		for row in ROWS:
			var a := column*(ROWS+1)+row
			var b := a+ROWS+1
			indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	deform(0.0)
	var bounds := mouth.mesh.get_aabb()
	closed_center = Vector2(bounds.get_center().x,bounds.get_center().y)

func deform(open: float) -> void:
	open = clampf(open,0.0,1.0)
	if absf(open-last_open)<0.00001: return
	last_open = open
	var points := PackedVector2Array()
	var width := lerpf(Chewing.WIDTH/WIDTH,1.0,smoothstep(0.0,1.0,open))
	for i in source.size():
		var at := source[i]
		if at.y > lips[i]: at.y = lips[i]+(at.y-lips[i])*lerpf(0.012,1.0,open)
		at -= source_anchor
		at.x *= width
		points.append(at*art_scale)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mouth.mesh = mesh

func apply(meshes: Dictionary, head: Transform2D, pose: Dictionary) -> void:
	var alpha: float = pose.get("biteAlpha",0.0) * Chewing.priority(pose)
	# ChewingPose suppresses native mouths once using the combined weights.
	mouth.modulate.a = alpha
	mouth.visible = alpha > 0.00001
	if not mouth.visible: return
	var open: float = pose.get("biteOpen",0.0)
	deform(open)
	var center := (ANCHOR+closed_center).lerp(Chewing.CENTER,pose.get("biteSettle",0.0))
	# Compensate the source lip's downward slant in this three-quarter face.
	# Fade the correction out as the jaw closes, preserving the chew handoff.
	var tilt := OPEN_TILT*smoothstep(0.0,0.65,open)
	mouth.transform = head * Transform2D(pose.get("chewAngle",0.0)+tilt,
		center+pose.get("chewOffset",Vector2.ZERO)) * Transform2D(0.0,-closed_center)
