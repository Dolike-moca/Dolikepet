extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("LANDING SUPPORT: " + message)
func lower_points(pet) -> PackedVector2Array:
	var sprite: Sprite2D = pet.sitting.sprite
	var result := PackedVector2Array()
	for p in [Vector2.ZERO, Vector2(sprite.texture.get_width(), 0), sprite.texture.get_size()]:
		result.append(sprite.global_transform * p)
	return result
func run() -> void:
	root.size = Vector2i(600, 600)
	root.mouse_passthrough = true
	var stage := Node2D.new()
	root.add_child(stage)
	var pet = Pet.new()
	stage.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))), pet.failure)
	if not pet.available: quit(1); return
	pet.fit(Vector2.ONE * 500)
	pet.tail.automatic = false
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var pose: Dictionary = behavior.update(0.0, Vector2.ZERO, Vector2.ZERO, 500, false).duplicate()
	pose.breath = 0.0
	pose.dizzyActive = true
	pose.dizzyAlpha = 1.0
	pose.landingInfluence = 1.0
	pose.motionReset = true
	var max_lower_error := 0.0
	for facing in [1.0, -1.0]:
		pet.set_seated(true, 2.0)
		pet.sitting.amount = 1.0
		pet.sitting.velocity = 0.0
		stage.position = Vector2.ZERO
		pose.facingScale = facing
		pose.dragTilt = 0.0
		pose.landingGroundOffset = 0.0
		pose.landingUpperBounce = 0.0
		pose.landingUpperTilt = 0.0
		pose.dizzyUpperSway = 0.0
		pet.apply_pose(pose, 0.0)
		var fixed_lower := lower_points(pet)
		var neutral_face: Vector2 = pet.landing_pose.sprites[0].global_position
		var neutral_eyes: float = pet.landing_pose.sprites[0].global_position.distance_to(pet.landing_pose.sprites[1].global_position)
		# Independent samples of torso recoil and residual collision rotation.
		# The window can still move vertically as its tilted collider settles.
		for sample in [[0.13, 0.0, 0.0, 0.0, 0.0], [-0.038, 0.0, 0.0, 0.0, 0.0], [0.10, 0.16, 12.0, 0.0, 0.0], [-0.025, -0.08, -5.0, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.0192, 0.0], [0.0, 0.0, 0.0, -0.0192, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0],
			[0.06, 0.0, 0.0, 0.0, -0.22], [-0.02, 0.0, 0.0, 0.0, 0.22], [0.04, 0.06, 8.0, 0.0, -0.18]]:
			pose.landingUpperBounce = sample[0]
			pose.landingUpperTilt = sample[4]
			pose.dizzyUpperSway = sample[3]
			pose.dragTilt = sample[1] * facing
			pose.landingGroundOffset = sample[2]
			stage.position.y = -sample[2]
			pet.apply_pose(pose, 0.0)
			var current := lower_points(pet)
			for i in current.size():
				max_lower_error = maxf(max_lower_error, current[i].distance_to(fixed_lower[i]))
				check(current[i].distance_to(fixed_lower[i]) < 0.002, "seated skirt/boots moved with upper recoil or collider")
			var face: Vector2 = pet.landing_pose.sprites[0].global_position
			if sample[1] == 0.0 and sample[0] != 0.0 and sample[4] == 0.0:
				check((face.y - neutral_face.y) * sample[0] > 0.0 and face.distance_to(neutral_face) > 1.0, "upper body did not absorb/recoil")
			if sample[4] != 0.0 and sample[1] == 0.0:
				check((face.x - neutral_face.x) * facing * sample[4] > 1.0, "visible upper lean opposed model-space direction")
			var eye_distance: float = face.distance_to(pet.landing_pose.sprites[1].global_position)
			check(absf(eye_distance - neutral_eyes) < 0.02, "head/eyes stretched during recoil")
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			var source: PackedVector2Array = raw.ArtMesh18
			var drawn := Secondary.read_points(pet.meshes.ArtMesh18)
			check(absf(drawn[0].distance_to(drawn[-1]) - source[0].distance_to(source[-1])) < 0.02, "head is not rigid")
		# Check the actual shader mapping during the texture replacement, after
		# all support/tilt corrections. Otherwise the hem briefly double-images.
		pet.sitting.amount = 0.68
		pose.dragTilt = 0.15 * facing
		pose.landingGroundOffset = 8.0
		pet.apply_pose(pose, 0.0)
		var pixel := Vector2(300, 200)
		var canvas: Vector2 = pet.sitting.sprite.global_transform * pixel
		var at := Vector3(canvas.x, canvas.y, 1.0)
		var row_x: Vector3 = pet.sitting.lower_materials[0].get_shader_parameter("sit_uv_x")
		var row_y: Vector3 = pet.sitting.lower_materials[0].get_shader_parameter("sit_uv_y")
		check(Vector2(row_x.dot(at), row_y.dot(at)).distance_to(pixel / pet.sitting.sprite.texture.get_size()) < 0.00001, "replacement UV drifted from seated sprite")
		# Regrab must remove support and upper recoil immediately, with the
		# existing reversible sitting spring handling the leg transition.
		pet.set_seated(false)
		pose.dizzyActive = false
		pose.dizzyAlpha = 0.0
		pose.landingUpperBounce = 0.0
		pose.landingUpperTilt = 0.0
		pose.dragTilt = 0.1
		pet.apply_pose(pose, 1.0 / 60)
		check(pet.landing_pose.support_weight == 0.0 and pet.landing_pose.upper_tilt == 0.0, "regrab retained grounded support")
		pose.dizzyActive = true
		pose.dizzyAlpha = 1.0
	print("LANDING SUPPORT: %d checks, %d failures; lower error %.6f pixels" % [checks, failures, max_lower_error])
	quit(1 if failures else 0)
