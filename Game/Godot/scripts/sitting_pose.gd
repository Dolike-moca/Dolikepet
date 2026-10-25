extends RefCounted
## Runtime choreography in original PSD pixels. Source artwork is never rewritten.
## The live Cubism torso affine is shared by the replacement, so the waist breathes together.

const Secondary = preload("res://scripts/secondary_deformation.gd")
const TransitionMesh = preload("res://scripts/sitting_mesh.gd")
const SIT_TEXTURE = preload("res://assets/skirt_sit.png")
const LOWER_MIX = preload("res://shaders/sitting_lower_mix.gdshader")
const SEATED_SHADER = preload("res://shaders/sitting_sprite.gdshader")
const ORIGIN := Vector2(1024, 1024)
const SIT_TOP_LEFT := Vector2(326, 1429) - ORIGIN
const WAIST := Vector2(870, 1460) - ORIGIN
const LOWER_IDS := ["ArtMesh23", "ArtMesh22", "ArtMesh21"]
const HIPS := {
	"ArtMesh23": Vector2(765, 1540) - ORIGIN,
	"ArtMesh22": Vector2(1040, 1540) - ORIGIN,
}
const DROP := 154.0 # Standing sole 2032 minus seated sole 1878 in the PSD.

var seated := false
var amount := 0.0
var velocity := 0.0
var sit_speed := 1.0
var sprite: Sprite2D
var blend := 0.0
var root_transform := Transform2D.IDENTITY
var lower_materials: Array[ShaderMaterial] = []
var boot_contours: Dictionary = {}
var transition_meshes: Dictionary = {}

func setup(model: Node2D, meshes: Dictionary) -> void:
	sprite = Sprite2D.new()
	sprite.name = "SeatedLowerBody"
	sprite.texture = SIT_TEXTURE
	sprite.centered = false
	sprite.position = SIT_TOP_LEFT
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = meshes["ArtMesh21"].z_index
	var seated_material := ShaderMaterial.new()
	seated_material.shader = SEATED_SHADER
	sprite.material = seated_material
	sprite.hide()
	model.add_child(sprite)
	for id in LOWER_IDS:
		var material: ShaderMaterial = meshes[id].material
		material.shader = LOWER_MIX
		material.set_shader_parameter("sit_texture", SIT_TEXTURE)
		lower_materials.append(material)
		var dense = TransitionMesh.new()
		dense.setup(meshes[id])
		transition_meshes[id] = dense
	# The seated sprite must composite AFTER the transition skirt at the same z.
	# Otherwise the alpha correction would leave the old skirt fully on top.
	model.move_child(sprite, -1)
	boot_contours = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sitting-boot-contours.json")).boots

func _radius(radii: Array, angle: float) -> float:
	var at := fposmod(angle, TAU) / TAU * radii.size()
	var lower := int(floor(at))
	return lerpf(radii[lower], radii[(lower + 1) % radii.size()], at - lower)

func _boot_target(id: String, point: Vector2, angle: float) -> Vector2:
	var contour: Dictionary = boot_contours[id]
	var center := Vector2(contour.sourceCenter[0], contour.sourceCenter[1])
	var target := Vector2(contour.targetCenter[0], contour.targetCenter[1])
	var vector := point - center
	if vector.length_squared() < 0.00001:
		return target
	var a := vector.angle()
	var radial_scale := _radius(contour.targetRadii, a + angle) / _radius(contour.sourceRadii, a)
	return target + vector.rotated(angle) * radial_scale

func set_seated(value: bool, speed: float = 1.0) -> void:
	seated = value
	sit_speed = clampf(speed, 0.25, 3.0)

func update(dt: float) -> void:
	# Analytic critically damped spring: reversible even during the descent.
	var target := 1.0 if seated else 0.0
	# Impact entry is quicker; normal sitting and standing retain their tempo.
	var omega := 9.0 * sit_speed if seated else 8.5
	var elapsed := clampf(dt, 0.0, 0.1)
	var offset := amount - target
	var impulse := velocity + omega * offset
	var decay := exp(-omega * elapsed)
	amount = target + (offset + impulse * elapsed) * decay
	velocity = (velocity - omega * impulse * elapsed) * decay
	if absf(amount - target) < 0.0001 and absf(velocity) < 0.002:
		amount = target
		velocity = 0.0

func apply(model: Node2D, meshes: Dictionary, raw: Dictionary, body: Transform2D) -> void:
	var k := clampf(amount, 0.0, 1.0)
	# Match the shapes before dissolving. The shader preserves opacity in overlap.
	blend = smoothstep(0.62, 0.74, k)
	# The downward motion peaks during the short replacement, hiding the texture hand-off.
	var settle := sin(PI * smoothstep(0.46, 1.0, k))
	# Fast impact entry has its own waist-up absorption. Scaling this root
	# would also lift the seated pelvis, hem and soles off their support.
	if seated and sit_speed > 1.0: settle = 0.0
	var body_scale := Vector2(1.0 + 0.009 * settle, 1.0 - 0.018 * settle)
	var lowering := DROP * smoothstep(0.10, 1.0, k)
	root_transform = Transform2D(0.0, body_scale, 0.0,
		WAIST - WAIST * body_scale + Vector2(0, lowering))
	model.transform = root_transform
	for id in HIPS:
		var far: bool = id == "ArtMesh23"
		var reach := smoothstep(0.02 if far else 0.06, 0.58, k)
		var angle := deg_to_rad((54.0 if far else 42.0) * reach)
		var leg_scale := Vector2(1.0, lerpf(1.0, 0.91 if far else 0.83, reach))
		var hip: Vector2 = HIPS[id]
		var leg := Transform2D(angle, leg_scale, 0.0, Vector2.ZERO)
		leg.origin = hip - leg * hip
		var dense = transition_meshes[id]
		meshes[id].visible = k == 0.0
		dense.node.visible = k > 0.0 and blend < 1.0
		dense.node.z_index = meshes[id].z_index
		if k > 0.0 and blend < 1.0:
			# The measured toe/cuff outline converges to the seated boot outline.
			# Its texture turns first, then the front-facing sole is revealed.
			var leg_points: PackedVector2Array = dense.sample(raw[id])
			var inv_body := body.affine_inverse()
			for i in leg_points.size():
				var local: Vector2 = inv_body * leg_points[i]
				var foot_weight := smoothstep(1530.0, 1800.0, local.y + ORIGIN.y) * smoothstep(0.10, 0.58, k)
				var projected: Vector2 = (leg * local).lerp(_boot_target(id, local, angle), foot_weight)
				leg_points[i] = body * projected
			Secondary.write_points(dense.node, leg_points)
	var skirt: MeshInstance2D = transition_meshes["ArtMesh21"].node
	meshes["ArtMesh21"].visible = k == 0.0
	skirt.z_index = meshes["ArtMesh21"].z_index
	skirt.modulate.a = 1.0
	skirt.visible = k > 0.0 and blend < 1.0
	# Lift the skirt off the knees before revealing the seated drawing. The old
	# symmetric flare left white cloth across the incoming exposed knees.
	if k > 0.0 and blend < 1.0:
		var points: PackedVector2Array = transition_meshes["ArtMesh21"].sample(raw["ArtMesh21"])
		var inverse := body.affine_inverse()
		for i in points.size():
			var local: Vector2 = inverse * points[i]
			var psd := local + ORIGIN
			var weight := smoothstep(1460.0, 1780.0, psd.y)
			var lift := smoothstep(0.10, 0.60, k)
			var across := clampf((psd.x - 575.0) / 570.0, 0.0, 1.0)
			# The right edge no longer drops below the old hem during the hand-off.
			local.x += lerpf(-90.0, 65.0, across) * lift * weight
			local.y -= ((20.0 + 35.0 * sin(PI * across)) * weight
				+ 25.0 * (1.0 - weight)) * lift
			points[i] = body * local
		Secondary.write_points(skirt, points)
	sprite.z_index = skirt.z_index
	sprite.transform = body * Transform2D(0.0, SIT_TOP_LEFT)
	sprite.modulate.a = blend
	sprite.visible = blend > 0.0

func update_composite_coordinates() -> void:
	# Call after landing/drag root adjustments; the dissolve is in canvas space.
	var inverse := sprite.global_transform.affine_inverse()
	var row_x := Vector3(inverse.x.x, inverse.y.x, inverse.origin.x) / SIT_TEXTURE.get_width()
	var row_y := Vector3(inverse.x.y, inverse.y.y, inverse.origin.y) / SIT_TEXTURE.get_height()
	for material in lower_materials:
		material.set_shader_parameter("sit_blend", blend)
		material.set_shader_parameter("sit_uv_x", row_x)
		material.set_shader_parameter("sit_uv_y", row_y)
