extends RefCounted
## Additional gait over the fresh Cubism vertices, using the existing standing layers.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const WalkingLeg = preload("res://scripts/walking_leg.gd")
const SHOULDERS := {
	"ArtMesh19": Vector2(1056, 1178) - Vector2(1024, 1024),
	"ArtMesh26": Vector2(720, 1190) - Vector2(1024, 1024),
}
const ELBOWS := {
	"ArtMesh19": Vector2(1113, 1368) - Vector2(1024, 1024),
	"ArtMesh26": Vector2(651, 1370) - Vector2(1024, 1024),
}
# Measured against 手臂调整.psd: a slightly smaller, inward-turned far arm.
# Basis columns map original PSD coordinates; see assets/far-arm-reference.json.
const FAR_ARM_BASIS := Transform2D(
	Vector2(0.9527774, -0.0603611), Vector2(0.0680591, 0.9507241), Vector2.ZERO)
const FAR_ARM_SHOULDER_OFFSET := Vector2(1.5, 4.875)
var legs = WalkingLeg.new()

func setup(boot_contours: Dictionary) -> void:
	legs.setup(boot_contours)

func apply(model: Node2D, meshes: Dictionary, raw: Dictionary, body: Transform2D,
		phase: float, weight: float, sitting_amount: float) -> void:
	weight *= 1.0 - smoothstep(0.0, 0.08, sitting_amount)
	# Ease the gait envelope, including the last few frames when coming to rest.
	weight = smoothstep(0.0, 1.0, weight)
	var inverse := body.affine_inverse()
	_apply_arms(meshes, raw, body, inverse, phase, weight)
	if weight <= 0.00001:
		return
	# Move the complete head/torso/scarf together: never lengthen the neck.
	# Rise slightly over the supporting leg; settle when both feet exchange load.
	var bounce := -5.2 * pow(cos(phase), 2.0) * weight
	model.position.y += bounce
	for id in WalkingLeg.HIPS:
		var near_leg: bool = id == "ArtMesh22"
		var leg_phase := phase + (0.0 if near_leg else PI)
		var points: PackedVector2Array = legs.deform_points(id, raw[id], body,
			leg_phase, weight, bounce)
		Secondary.write_points(meshes[id], points)
	var skirt: PackedVector2Array = raw["ArtMesh21"].duplicate()
	for i in skirt.size():
		var local := inverse * skirt[i]
		var hem := smoothstep(1460.0, 1780.0, local.y + 1024.0)
		local.x += 6.5 * sin(phase - 0.35) * hem * hem * weight
		local.y -= 2.6 * pow(sin(phase), 2.0) * hem * weight
		skirt[i] = body * local
	Secondary.write_points(meshes["ArtMesh21"], skirt)

func _apply_arms(meshes: Dictionary, raw: Dictionary, body: Transform2D,
		inverse: Transform2D, phase: float, weight: float) -> void:
	for id in SHOULDERS:
		var near_arm: bool = id == "ArtMesh19"
		# Opposite the corresponding leg, with a small lag through the forearm.
		var arm_phase := phase + (0.0 if near_arm else PI) - 0.10
		var angle := deg_to_rad(-(11.0 if near_arm else 10.0) * sin(arm_phase) * weight)
		var forearm_angle := deg_to_rad(-1.8 * sin(arm_phase - 0.28) * weight)
		var shoulder: Vector2 = SHOULDERS[id]
		var elbow: Vector2 = ELBOWS[id]
		if not near_arm:
			elbow = shoulder + FAR_ARM_SHOULDER_OFFSET + FAR_ARM_BASIS * (elbow - shoulder)
			shoulder += FAR_ARM_SHOULDER_OFFSET
		var points: PackedVector2Array = raw[id].duplicate()
		for i in points.size():
			var local := inverse * points[i]
			# Apply the reference pose before animation, directly from fresh Core
			# vertices. It remains identical when standing, seated or coming to rest.
			if not near_arm:
				local = shoulder + FAR_ARM_BASIS * (local - SHOULDERS[id])
			var forearm := smoothstep(elbow.y - 25.0, elbow.y + 85.0, local.y)
			local = local.lerp(elbow + (local - elbow).rotated(forearm_angle), forearm)
			points[i] = body * (shoulder + (local - shoulder).rotated(angle))
		Secondary.write_points(meshes[id], points)
