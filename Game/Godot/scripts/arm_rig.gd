extends RefCounted
## Whole-arm sprites follow the final animation guides. The normal far arm is
## uses the PSD shoulder and the approved 8-degree lower rest orientation;
## feeding supplies its separate palm-facing artwork.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Walking = preload("res://scripts/walking_pose.gd")
const NearArt = preload("res://assets/feeding/arm_near_hold.png")
const FarArt = preload("res://assets/feeding/arm_far_palm.png")
const FarRestArt = preload("res://assets/arms/arm_far_rest.png")
const NEAR_ROOT := Vector2(205,245)
const NEAR_PALM := Vector2(655,1250)
const FAR_ROOT := Vector2(895,200)
const FAR_PALM := Vector2(355,1050)
const FAR_REST_ROOT := Vector2(215,14)
const FAR_REST_PALM := Vector2(80,289)
# Exact 287 x 372 layer at (505,1176) on the 2048 x 2048 PSD canvas.
const FAR_REST := Transform2D(Vector2.RIGHT,Vector2.DOWN,Vector2(505,1176)-Vector2(1024,1024))
const FAR_REST_SOCKET := FAR_REST*FAR_REST_ROOT
# rest-far-arm-lower-8deg-preview: rotate about the PSD socket, never translate
# or stretch the source. Every normal pose adds its motion to this baseline.
const FAR_REST_ANGLE := deg_to_rad(-8.0)
# Approved feeding transforms from far-arm-food-xl-preview. The near shoulder
# remains shared by every pose; the far arm has its own PSD rest placement.
const NEAR_HOLD := Transform2D(Vector2(0.121633,0.243095),Vector2(-0.243095,0.121633),Vector2(19.94774,134.377))
const FAR_HOLD := Transform2D(Vector2(0.220647,0.127828),Vector2(-0.127828,0.220647),Vector2(-474.4136,32.33993))
# Approved far-arm-longer-review: match the PSD shoulder-to-palm distance.
# Apply after the original angle calculation so every existing gesture keeps
# its orientation and shoulder socket, exactly as in the accepted preview.
const FAR_HOLD_ART_SCALE := 1.19298833568046
const SOCKETS := {"ArtMesh19": NEAR_HOLD*NEAR_ROOT, "ArtMesh26": FAR_HOLD*FAR_ROOT}
const GUIDE_PALMS := {"ArtMesh19":Vector2(113,426),"ArtMesh26":Vector2(-439,441)}
var near: Sprite2D
var far: Sprite2D
var far_rest_overlay: Sprite2D
var palms := {}
var shoulders := {}
var guide_samples := {}
var guide_rays := {}
var rest_angles := {}

func setup(model: Node2D, meshes: Dictionary) -> void:
	near = _sprite(model,NearArt,"SharedNearArm")
	far = _sprite(model,FarRestArt,"SharedFarArm")
	far_rest_overlay = _sprite(model,FarRestArt,"FarArmHandTurn")
	for id in SOCKETS:
		var points := Secondary.read_points(meshes[id])
		var a := _closest(points,Walking.SHOULDERS[id])
		var b := _closest(points,GUIDE_PALMS[id])
		guide_samples[id] = Vector2i(a,b)
		var ray := points[b]-points[a]
		var arm_axis: Vector2 = GUIDE_PALMS[id]-Walking.SHOULDERS[id]
		if id == "ArtMesh26":
			ray = Walking.FAR_ARM_BASIS.basis_xform(ray)
			# The native guide still has the earlier calibration. Cancel it in
			# the measured delta, but register the visible arm to the latest PSD.
		guide_rays[id] = ray
		var art_axis := NEAR_PALM-NEAR_ROOT if id == "ArtMesh19" else FAR_PALM-FAR_ROOT
		rest_angles[id] = arm_axis.angle()-art_axis.angle()
		# Feeding's hand-turn overlay must start/end at the same lowered rest
		# angle. Its fully raised pose still uses the approved FAR_HOLD matrix.
		if id == "ArtMesh26": rest_angles[id] += FAR_REST_ANGLE

static func _closest(points: PackedVector2Array, at: Vector2) -> int:
	var best := 0
	for i in points.size():
		if points[i].distance_squared_to(at)<points[best].distance_squared_to(at): best = i
	return best

static func _sprite(model: Node2D, texture: Texture2D, label: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = label
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.hide()
	model.add_child(sprite)
	return sprite

static func anchored(hold: Transform2D, source_root: Vector2, angle: float) -> Transform2D:
	var result := Transform2D(angle,Vector2.ONE*hold.x.length(),0.0,Vector2.ZERO)
	result.origin = hold*source_root-result*source_root
	return result

func apply_rest(meshes: Dictionary, alignment: Transform2D, near_layers, far_layers) -> void:
	# Run after every pose modifier, including drag/fall/landing. Keeping this
	# final pass central prevents a new animation from exposing the old arms.
	for layer in near_layers.pieces+far_layers.pieces: layer.node.hide()
	far_rest_overlay.hide()
	far.texture = FarRestArt
	var inverse := alignment.affine_inverse()
	for id in SOCKETS:
		var sprite: Sprite2D = near if id == "ArtMesh19" else far
		var points := Secondary.read_points(meshes[id])
		var sample: Vector2i = guide_samples[id]
		var ray := inverse.basis_xform(points[sample.y]-points[sample.x])
		var reference: Vector2 = guide_rays[id]
		var turn := reference.angle_to(ray) if ray.length_squared()>0.000001 else 0.0
		var hold := NEAR_HOLD if id == "ArtMesh19" else FAR_REST
		var source_root := NEAR_ROOT if id == "ArtMesh19" else FAR_REST_ROOT
		var angle: float = rest_angles[id]+turn if id == "ArtMesh19" else FAR_REST_ANGLE+turn
		sprite.transform = alignment*anchored(hold,source_root,angle)
		sprite.z_index = meshes[id].z_index
		sprite.modulate.a = 1.0
		sprite.show()
		meshes[id].self_modulate.a = 0.0
	update_anchors()

func update_anchors() -> void:
	var resting := far.texture==FarRestArt
	palms = {"ArtMesh19":near.transform*NEAR_PALM,"ArtMesh26":far.transform*(FAR_REST_PALM if resting else FAR_PALM)}
	shoulders = {"ArtMesh19":near.transform*NEAR_ROOT,"ArtMesh26":far.transform*(FAR_REST_ROOT if resting else FAR_ROOT)}
