extends SceneTree
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const Roaming = preload("res://scripts/roaming.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures < 15:
			printerr("WALK RENDER: " + message)

func _run() -> void:
	root.size = Vector2i(1040, 650)
	root.position = Vector2i(30, 30)
	root.mouse_passthrough = true
	root.transparent_bg = true
	var stage := Node2D.new()
	root.add_child(stage)
	var pet = Pet.new()
	stage.add_child(pet)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))
	_check(pet.load_pet(config), pet.failure)
	if not pet.available:
		quit(1)
		return
	pet.fit(Vector2(420, 420))
	var behavior = Behavior.new()
	behavior.automatic_blinks = false
	var roam = Roaming.new()
	roam.configure("free")
	roam.rng.seed = 3
	roam.wait_remaining = 0.0
	var position := Vector2(270, 20)
	var area := Rect2(0, 0, 1040, 650)
	var automatic_seat := false
	var output := ProjectSettings.globalize_path("res://../../_work/tests/walking-frames")
	DirAccess.make_dir_recursive_absolute(output)
	var walked_left := false
	var walked_right := false
	var previous_state := ""
	var trips := 0
	var requested_rest := false
	for frame in 900:
		# A reproducible demonstration: rightward walk, rest, rise and leftward walk.
		var move: Dictionary = roam.update(1.0 / 60.0, position, Vector2(420, 420), area,
			pet.sitting.amount, pet.sitting.seated, automatic_seat, false)
		if roam.state == "landing" and trips == 0:
			roam.target_x = 600.0
			roam.direction = 1
		if move.move:
			position = move.position
		if move.sit >= 0:
			pet.set_seated(move.sit == 1)
		if roam.state == "walking" and previous_state != "walking":
			trips += 1
		if roam.state == "idle" and trips == 1 and not requested_rest:
			automatic_seat = true
			roam.request_rest()
			requested_rest = true
		if pet.sitting.amount == 1.0:
			roam.rest_remaining = minf(roam.rest_remaining, 0.8) if roam.rest_remaining > 0.0 else 0.8
		if roam.state == "turning" and trips == 1:
			roam.target_x = 180.0
			roam.direction = -1
		var pose: Dictionary = behavior.update(1.0 / 60.0, Vector2.ZERO, Vector2.ZERO, 420, false).duplicate()
		pose.walkPhase = roam.phase
		pose.walkWeight = roam.weight
		pose.facingScale = roam.facing_scale
		pose.motionOrigin = position
		pet.apply_pose(pose, 1.0 / 60.0)
		stage.position = position
		if roam.state == "walking":
			walked_left = walked_left or roam.direction < 0
			walked_right = walked_right or roam.direction > 0
			_check(pet.sitting.amount <= 0.0001, "walking before fully standing")
			var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
			for id in ["ArtMesh22", "ArtMesh23", "ArtMesh19", "ArtMesh26", "ArtMesh21", "ArtMesh28"] + Secondary.HAIR.keys():
				var points := Secondary.read_points(pet.meshes[id])
				var indices: PackedInt32Array = pet.meshes[id].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var valid := true
				for n in range(0, indices.size(), 3):
					var a := indices[n]
					var b := indices[n + 1]
					var c := indices[n + 2]
					var before: float = (raw[id][b] - raw[id][a]).cross(raw[id][c] - raw[id][a])
					var after := (points[b] - points[a]).cross(points[c] - points[a])
					valid = valid and points[a].is_finite() and (absf(before) < 0.01 or before * after > 0.0)
				_check(valid, "folded gait mesh " + id)
		previous_state = roam.state
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0:
			var picture := root.get_texture().get_image()
			var used := picture.get_used_rect()
			_check(used.position.x > 0 and used.end.x < 1040 and used.end.y < 650, "pet clipped")
			picture.save_png(output.path_join("%04d.png" % (frame / 2)))
	_check(walked_left and walked_right, "missing a travel direction")
	_check(requested_rest, "no walk-to-sit transition rendered")
	print("WALK RENDER: 900 frames; %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
