extends SceneTree
## Mushroom-specific support/release; ordinary file-feeding geometry stays in
## test_feeding_hold_rig. This fixture creates no host or user-data worker.
const Pet = preload("res://scripts/live2d_pet.gd")
const Change = preload("res://scripts/size_change.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not message in failures: failures.append(message)

func _initialize() -> void: call_deferred("run")

func local_inverse(pet, pose: Dictionary) -> Transform2D:
	var body: Transform2D = pet.pickup_pose.gaze_body
	var upper: Transform2D = Pet.PickupPose.upper_transform(body,pose)*Pet.PickupPose.Spine.upper_transform(body,pose)
	return (upper*body).affine_inverse()

func check_geometry(pet, pose: Dictionary) -> Transform2D:
	var rig = pet.pickup_pose.hold_rig
	var inverse := local_inverse(pet,pose)
	var arm: Transform2D = inverse*rig.far.transform
	var weight: float = Pet.PickupPose.amount(pose)
	var shoulder: Vector2 = rig.FAR_REST_SOCKET.lerp(Vector2(-302.500135,190.87539),weight)
	check((arm*rig.FAR_ROOT).distance_to(shoulder)<0.005,"far shoulder wanders during support or release")
	var accepted_scale: float = rig.FAR_HOLD.x.length()*rig.FAR_HOLD_ART_SCALE
	check(absf(arm.x.length()-accepted_scale)<0.00001 and absf(arm.y.length()-accepted_scale)<0.00001,"far arm changes its approved uniform scale")
	check(absf(arm.x.dot(arm.y))<0.00001 and arm.determinant()>0.0,"far arm shears or flips")
	check(absf((arm.basis_xform(rig.FAR_PALM-rig.FAR_ROOT)).length()-306.349487)<0.005,"far arm changes shoulder-to-palm length")
	var near: Transform2D = inverse*rig.near.transform
	check((near*rig.NEAR_ROOT).distance_to(Vector2(-14.67577,214.01156))<0.005,"mushroom correction moves the near shoulder")
	check(absf(near.x.length()-rig.NEAR_HOLD.x.length())<0.00001 and absf(near.y.length()-rig.NEAR_HOLD.y.length())<0.00001,"mushroom correction stretches the near arm")
	if rig.far_rest_overlay.visible:
		var back: Transform2D = inverse*rig.far_rest_overlay.transform
		check((back*rig.FAR_REST_ROOT).distance_to(shoulder)<0.005,"turning palm leaves its shoulder")
		check((back*rig.FAR_REST_PALM).distance_to(arm*rig.FAR_PALM)<0.005,"turning palm separates from the held palm")
		check(absf(back.x.length()-back.y.length())<0.00001 and absf(back.x.dot(back.y))<0.00001,"turning palm artwork stretches or shears")
		check(absf(rig.far.modulate.a+rig.far_rest_overlay.modulate.a-1.0)<0.00001,"palm transition loses its opacity envelope")
	return arm

func run() -> void:
	root.size=Vector2i(600,600);root.position=Vector2i(-1600,-1600)
	root.mouse_passthrough=true
	var pet=Pet.new();root.add_child(pet)
	if not pet.load_pet(JSON.parse_string(FileAccess.get_file_as_string("res://config/pet.json"))):
		printerr(pet.failure);quit(1);return
	pet.fit(Vector2.ONE*600)
	var behavior=Behavior.new();behavior.automatic_blinks=false
	var base:Dictionary=behavior.update(0.0,Vector2.ZERO,Vector2.ZERO,600,false).duplicate()
	base.breath=0.0;base.motionReset=true
	var rig=pet.pickup_pose.hold_rig
	for facing in [1.0,-1.0]:
		var change=Change.new();change.initialize(300);change.request(375,300)
		var bites:Dictionary={}
		var previous_angle:=NAN
		var previous_alpha:=NAN
		var closing_samples:=0
		var last_bite_samples:=0
		var full_support_samples:=0
		for frame in 720:
			change.update(1.0/120.0,roundi(change.value),false)
			var pose:=base.duplicate();pose.facingScale=facing;pose.merge(change.pose(),true)
			pet.apply_pose(pose,1.0/120.0)
			if rig.enabled and pose.get("sizeMushroom",false):
				var arm:=check_geometry(pet,pose)
				var angle:=arm.get_rotation()
				var alpha:float=rig.far.modulate.a
				if not is_nan(previous_angle):
					check(absf(wrapf(angle-previous_angle,-PI,PI))<deg_to_rad(12.0),"far arm jumps or reverses at a bite/angle boundary")
				if not is_nan(previous_alpha):
					if absf(alpha-previous_alpha)>=0.09:
						printerr("PALM FADE DETAIL facing=",facing," frame=",frame," state=",change.state," age=",change.age," weight=",Pet.PickupPose.amount(pose)," alpha=",previous_alpha," -> ",alpha," handOpen=",pose.get("sizeFarHandOpen",-1.0)," support=",pose.get("sizeFarSupport",-1.0))
					check(absf(alpha-previous_alpha)<0.09,"far palm artwork switches abruptly")
				previous_angle=angle;previous_alpha=alpha
				var bite:int=pose.get("foodCutIndex",-1)
				if bite>=0: bites[bite]=true
				if bite in [0,1] and alpha>0.999: full_support_samples+=1
				if bite>=2 and alpha>0.0 and alpha<1.0: closing_samples+=1
				if bite==4:
					last_bite_samples+=1
					check(alpha<0.00001 and rig.far_rest_overlay.visible,"last mouthful still has an open hovering far palm")
					check((arm*rig.FAR_PALM).y-(arm*rig.FAR_ROOT).y>230.0,"far arm has not settled down by the last mouthful")
			else:
				previous_angle=NAN;previous_alpha=NAN
		check(bites.size()==5 and last_bite_samples>30,"fixture did not exercise all five mouthfuls")
		check(full_support_samples>60 and closing_samples>15,"two-hand support or gradual palm return is missing")
		check(not change.pending() and rig.far.texture==rig.FarRestArt and not rig.far_rest_overlay.visible,"completed mushroom does not restore the normal far arm")
	# Keep the hand supporting while continuously sweeping the smaller remnants.
	# Their target passes behind the shoulder: an unwrapped bearing would jump
	# between opposite angle limits around the negative horizontal axis.
	var sweep=Change.new();sweep.initialize(300);sweep.request(375,300)
	for frame in 20: sweep.update(0.02,300,false)
	var sample:=base.duplicate();sample.merge(sweep.pose(),true)
	sample.pickupArms=1.0;sample.sizeFoodLift=1.0;sample.sizeFoodApproach=1.0
	sample.sizeFarSupport=1.0;sample.sizeFarHandOpen=1.0;sample.pickupCarry=Vector2.ZERO
	var previous:=NAN
	var lowest:=INF;var highest:=-INF
	for step in 401:
		sample.foodRemaining=1.0-float(step)/400.0
		pet.apply_pose(sample,0.0)
		var arm:=check_geometry(pet,sample)
		var angle:=arm.get_rotation()
		lowest=minf(lowest,angle);highest=maxf(highest,angle)
		if not is_nan(previous):
			check(absf(wrapf(angle-previous,-PI,PI))<deg_to_rad(3.0),"continuous remnant sweep jumps across the bearing wrap")
		previous=angle
	check(highest-lowest>deg_to_rad(8.0),"remnant sweep did not exercise a changing support direction")
	for message in failures: printerr("MUSHROOM HOLD: "+message)
	print("MUSHROOM HOLD: ","PASS" if failures.is_empty() else "FAIL"," (",checks," checks)")
	quit(0 if failures.is_empty() else 1)
