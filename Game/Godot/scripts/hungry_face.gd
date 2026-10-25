extends RefCounted
## Replace iris colors in their original deforming meshes, retaining lid masks.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Chewing = preload("res://scripts/chewing_pose.gd")
const SHADER = preload("res://shaders/hungry_iris.gdshader")
const MOUTH = preload("res://assets/hungry/mouth.png")
const EYES := {
	"ArtMesh11": [preload("res://assets/hungry/near_eye_base.png"),
		preload("res://assets/hungry/near_eye_star.png"), Rect2(809,826,143,191),
		Vector2(70.0/143.0,98.0/191.0), "pickupStarNear"],
	"ArtMesh10": [preload("res://assets/hungry/far_eye_base.png"),
		preload("res://assets/hungry/far_eye_star.png"), Rect2(561,864,90,165),
		Vector2(49.0/90.0,84.0/165.0), "pickupStarFar"]}
const MOUTH_REGION := Rect2(510,365,760,270)
const MOUTH_ANCHOR := Vector2(886.5,438.5)
const MOUTH_SCALE := 82.0 / 737.0
var mouth: Sprite2D
var materials := {}
var uv_maps := {}

func prepare(pose: Dictionary) -> Dictionary:
	var result := pose.duplicate()
	result.headZ = clampf(pose.headZ + pose.get("pickupHeadTilt",0.0) * Chewing.priority(pose), -30.0,30.0)
	return result

func setup(model: Node2D, meshes: Dictionary) -> void:
	for id in EYES:
		var settings: Array = EYES[id]
		var points := Secondary.read_points(meshes[id])
		var uv: PackedVector2Array = meshes[id].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var sample := Secondary._sample_triangle(points)
		var a: int = sample[0]
		var b: int = sample[1]
		var c: int = sample[2]
		var source := Transform2D(uv[b]-uv[a],uv[c]-uv[a],uv[a])
		var rect: Rect2 = settings[2]
		var at := (points[a]+Vector2(1024,1024)-rect.position)/rect.size
		var target := Transform2D((points[b]-points[a])/rect.size,(points[c]-points[a])/rect.size,at)
		var remap := target * source.affine_inverse()
		uv_maps[id] = remap
		var mat: ShaderMaterial = meshes[id].material
		var previous := {}
		for uniform in mat.shader.get_shader_uniform_list():
			previous[uniform.name] = mat.get_shader_parameter(uniform.name)
		mat.shader = SHADER
		for key in previous: mat.set_shader_parameter(key,previous[key])
		mat.set_shader_parameter("hungry_base",settings[0])
		mat.set_shader_parameter("hungry_star",settings[1])
		mat.set_shader_parameter("art_uv_x",Vector3(remap.x.x,remap.y.x,remap.origin.x))
		mat.set_shader_parameter("art_uv_y",Vector3(remap.x.y,remap.y.y,remap.origin.y))
		mat.set_shader_parameter("star_pivot",settings[3])
		materials[id] = mat
	mouth = Sprite2D.new()
	mouth.name = "HungryMouth"
	mouth.texture = MOUTH
	mouth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouth.region_enabled = true
	mouth.region_rect = MOUTH_REGION
	# Anchor the mouth stroke, not the image canvas or dangling saliva.
	mouth.offset = MOUTH_REGION.size*0.5 - (MOUTH_ANCHOR-MOUTH_REGION.position)
	mouth.z_index = meshes.ArtMesh3.z_index
	mouth.hide()
	model.add_child(mouth)

func apply(meshes: Dictionary, head: Transform2D, pose: Dictionary) -> void:
	var priority := Chewing.priority(pose)
	var eye_weight: float = pose.get("pickupStarEyes",0.0) * priority
	for id in materials:
		var pulse: Vector2 = pose.get(EYES[id][4],Vector2(0.85,1.0))
		materials[id].set_shader_parameter("hungry_weight",eye_weight)
		materials[id].set_shader_parameter("star_alpha",pulse.x)
		materials[id].set_shader_parameter("star_scale",pulse.y)
	var alpha: float = pose.get("pickupHungry",0.0) * priority
	# Earlier face passes already fade the native mouth for chewing/physics.
	var base_visibility: float = meshes.ArtMesh3.self_modulate.a
	for id in ["ArtMesh3","ArtMesh4"]: meshes[id].self_modulate.a *= 1.0-alpha
	mouth.modulate.a = alpha * base_visibility
	mouth.visible = mouth.modulate.a > 0.00001
	mouth.transform = head * Transform2D(0.0,Vector2.ONE*MOUTH_SCALE,0.0,Chewing.CENTER)
