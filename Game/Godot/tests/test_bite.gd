extends SceneTree
const Motion = preload("res://scripts/pickup_motion.gd")
const Pet = preload("res://scripts/live2d_pet.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("BITE: "+message)

func timing() -> void:
	for fps in [30,60,120]:
		var m = Motion.new()
		m.rng.seed = 20261022
		m.request(100,600)
		check(m.bite_duration >= 0.85 and m.bite_duration <= 1.1,"bite duration outside selected range")
		var events := 0
		var last_cut := 0.0
		for frame in fps*8:
			var p: Dictionary = m.update(1.0/fps)
			check(p.biteCut >= last_cut,"food regenerated between bite frames")
			last_cut = p.biteCut
			var local: float = (m.age-Motion.CATCH_TIME-m.admire_duration)/m.bite_duration
			if local < 0.49: check(p.biteCut == 0.0,"food cut before mouth contact")
			if local > 0.25 and local < 0.45: check(p.biteOpen == 1.0,"mouth did not open ahead of contact")
			if m.take_eat_request():
				events += 1
				check(p.biteOpen == 0.0 and p.biteCut == 1.0,"chewing started before bite closed")
		check(events == 1,"chew handoff duplicated or absent")
		check(m.pose().biteAlpha == 0.0 and m.pose().biteCut == 1.0,"bite did not settle into bitten hold")
		m.state = "holding"
		m.age = Motion.CATCH_TIME+m.admire_duration+m.bite_duration*0.4
		var frozen: Dictionary = m.pose()
		for frame in fps: m.update(1.0/fps,true,true)
		check(m.pose() == frozen,"pause changed contact or mouth")
		m.cancel(true)
		check(m.pose().biteAlpha == 0.0 and m.pose().biteCut == 0.0 and not m.take_eat_request(),"interrupt retained bite")

func run() -> void:
	timing()
	if DisplayServer.get_name() == "headless": finish(); return
	root.size = Vector2i(600,600)
	root.mouse_passthrough = true
	var pet = Pet.new()
	root.add_child(pet)
	check(pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))),pet.failure)
	if not pet.available: finish(); return
	var b = Behavior.new()
	b.automatic_blinks = false
	var base: Dictionary = b.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath = 0.0
	base.motionReset = true
	pet.apply_pose(base,0.0)
	var lower := {}
	for id in ["ArtMesh21","ArtMesh22","ArtMesh23"]: lower[id] = Pet.Secondary.read_points(pet.meshes[id])
	var motion = Motion.new()
	motion.request(100,600)
	motion.state = "holding"
	var max_hand_error := 0.0
	var flipped := 0.0
	for facing in [1.0,-1.0]:
		for size in [240,600,800]:
			pet.fit(Vector2.ONE*size)
			for step in 61:
				motion.age = Motion.CATCH_TIME+motion.admire_duration+motion.bite_duration*step/60.0
				var pose := base.duplicate()
				pose.merge(motion.pose(),true)
				pose.facingScale = facing
				pet.apply_pose(pose,0.0)
				for id in lower: check(Pet.Secondary.read_points(pet.meshes[id]) == lower[id],"bite moved feet/hips")
				var raw: Dictionary = pet.model.call("get_raw_mesh_vertices")
				var body: Transform2D = pet.deformation._affine("ArtMesh24",raw.ArtMesh24)
				var head: Transform2D = pet.deformation._affine("ArtMesh18",raw.ArtMesh18)
				var upper: Transform2D = Pet.PickupPose.upper_transform(body,pose)
				if pet.bite_face.mouth.visible:
					var center: Vector2 = (Pet.BiteFace.ANCHOR+pet.bite_face.closed_center).lerp(Pet.ChewingPose.CENTER,pose.biteSettle)
					check((pet.bite_face.mouth.transform*pet.bite_face.closed_center).distance_to(upper*head*center)<0.002,"W lip detached from face")
				check(pet.food_gaze(pose).distance_to(pet.pickup_pose.food.global_position)<0.01,"food gaze misses raised food")
				for id in Pet.Walking.SHOULDERS:
					var bone: Dictionary = Pet.PickupPose.solve(id,1.0,0.0,1.0,1.0,pose.pickupCarry)
					check(Pet.PickupPose.arm_point(bone.shoulder,bone).distance_to(bone.shoulder)<0.001,"shoulder detached")
					var wanted: Vector2 = Pet.PickupPose.TARGETS[id]+pose.pickupCarry
					max_hand_error = maxf(max_hand_error,Pet.PickupPose.arm_point(bone.palm,bone).distance_to(wanted))
					if facing == 1.0 and size == 600:
						var points := Pet.Secondary.read_points(pet.meshes[id])
						var reference: PackedVector2Array = raw[id]
						var triangles: PackedInt32Array = pet.meshes[id].mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
						for at in range(0,triangles.size(),3):
							var a: int = triangles[at]
							var c: int = triangles[at+1]
							var d: int = triangles[at+2]
							var before := (reference[c]-reference[a]).cross(reference[d]-reference[a])
							var after := (points[c]-points[a]).cross(points[d]-points[a])
							if before*after < -0.01: flipped = maxf(flipped,absf(after))
	check(max_hand_error<7.0,"raised hands lost food grip: "+str(max_hand_error))
	check(flipped<0.1,"bite folded elbow triangles: "+str(flipped))
	check(pet.pickup_pose.food.z_index > pet.meshes.ArtMesh5.z_index and pet.pickup_pose.food.z_index > pet.bite_face.mouth.z_index,"food depth changed across face/scarf")
	for physical in ["dragHeld","fallActive","dizzyActive"]:
		motion.age = Motion.CATCH_TIME+motion.admire_duration+motion.bite_duration*0.4
		var pose := base.duplicate()
		pose.merge(motion.pose(),true)
		pose[physical] = true
		pet.apply_pose(pose,0.0)
		check(not pet.bite_face.mouth.visible and not pet.pickup_pose.food.visible,"physical interruption left bite visible")
	print("BITE maximum palm target error: ",max_hand_error)
	finish()

func finish() -> void:
	print("BITE CHECKS: ",checks," passed: ",checks-failures," failed: ",failures)
	quit(0 if failures == 0 else 1)
