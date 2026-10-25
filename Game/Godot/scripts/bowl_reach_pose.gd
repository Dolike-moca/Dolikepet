extends RefCounted
## Approved face-side arms and calling mouth; shares drag-release eye recovery.
const Drag = preload("res://scripts/drag_pose.gd")
const Arm = preload("res://scripts/arm_rig.gd")
const Falling = preload("res://scripts/falling_pose.gd")
const EyeTransition = preload("res://scripts/drag_eye_transition.gd")
const Chewing = preload("res://scripts/chewing_pose.gd")
const Behavior = preload("res://scripts/pet_behavior.gd")
const MOUTH = preload("res://assets/bowl/shout_mouth.png")
const EYE_IDS := ["ArtMesh6","ArtMesh7","ArtMesh8","ArtMesh9","ArtMesh10","ArtMesh11","ArtMesh12","ArtMesh13"]
var eyes: Array[Sprite2D] = []
var shout: Sprite2D
var time := 0.0
var use_squeezed_eyes := true
var eye_recovery = EyeTransition.new()
var mouth_open := 0.0
var was_calling := false
var release_open := 0.0
var release_age := 1.0
var summoning := false
var chant_face := 0.0
var chant_mouth := 0.0

static func calling_openness(t: float) -> float:
	# Four unequal syllables, with closed intervals and a breath between calls.
	var phase := fposmod(t,1.65)
	var value := 0.0
	for beat in [Vector3(0.0,0.24,0.8),Vector3(0.28,0.49,0.55),Vector3(0.54,0.82,0.9),Vector3(0.88,1.36,1.0)]:
		value = maxf(value,beat.z*smoothstep(beat.x,beat.x+0.065,phase)*(1.0-smoothstep(beat.y-0.09,beat.y,phase)))
	return value

func prepare(pose: Dictionary, dt: float) -> Dictionary:
	var result := pose.duplicate()
	time = pose.get("bowlTime",0.0)
	summoning = pose.get("bowlSummoning",false)
	if pose.get("bowlHitActive",false):
		chant_face = 0.0; chant_mouth = 0.0
		eye_recovery.was_held = false; eye_recovery.recovering = false
		mouth_open = 0.0; release_open = 0.0; was_calling = false
		result.bowlMouthOpen = 0.0; result.bowlEyeOpenness = 1.0
		return result
	var interrupted: bool = pose.get("dragHeld",false) or pose.get("fallActive",false) or pose.get("dizzyActive",false)
	if interrupted:
		chant_face = 0.0; chant_mouth = 0.0
		result.bowlReach = 0.0; result.bowlTilt = 0.0
		eye_recovery.was_held = false; eye_recovery.recovering = false
		mouth_open = 0.0; release_open = 0.0; was_calling = false; release_age = 1.0
		return result
	var step := 0.0 if pose.get("bowlPaused",false) else clampf(dt,0.0,0.1)
	var weight: float = pose.get("bowlReach",0.0) if use_squeezed_eyes and not summoning else 0.0
	# Use the exact drag-release controller without enabling a drag body pose.
	var eye_pose := eye_recovery.update({
		"eyeNear":pose.eyeNear,"eyeFar":pose.eyeFar,
		"dragHeld":weight>0.00001,"dragFace":weight,
		"fallPaused":pose.get("bowlPaused",false)
	},step)
	result.eyeNear = eye_pose.eyeNear
	result.eyeFar = eye_pose.eyeFar
	result.bowlEyeOpenness = eye_pose.dragEyeOpenness
	# Closed smiling eyes and the normal speaking mouth, with the same timing
	# and smoothing as ordinary speech. Keep the shouting bitmap out of chanting.
	var chanting: bool = summoning and pose.get("bowlCalling",false)
	var face_target := 1.0 if chanting else 0.0
	chant_face = lerpf(chant_face,face_target,1.0-exp(-28.0*step))
	if absf(chant_face-face_target)<0.001: chant_face = face_target
	var jaw_target := Behavior.speaking_openness(time) if chanting else 0.0
	chant_mouth = lerpf(chant_mouth,jaw_target,1.0-exp(-22.0*step))
	if chant_mouth<0.001: chant_mouth = 0.0
	if chant_face>0.0:
		result.eyeNear *= 1.0-chant_face; result.eyeFar *= 1.0-chant_face
		result.mouth = lerpf(pose.mouth,chant_mouth,chant_face)
	var calling: bool = pose.get("bowlCalling",false) and not summoning
	if calling:
		mouth_open = calling_openness(time)*smoothstep(0.0,0.9,pose.get("bowlReach",0.0))
		release_age = 0.0
	else:
		if was_calling: release_open = mouth_open; release_age = 0.0
		release_age += step
		mouth_open = release_open*(1.0-smoothstep(0.0,0.22,release_age))
	was_calling = calling
	result.bowlMouthOpen = mouth_open
	return result

func setup(model: Node2D, meshes: Dictionary) -> void:
	for i in 2:
		var sprite := Sprite2D.new()
		sprite.texture = Drag.FEATURES[i][0]
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.z_index = meshes[Drag.FEATURES[i][3]].z_index
		sprite.hide(); model.add_child(sprite); eyes.append(sprite)
	shout = Sprite2D.new()
	shout.name = "BowlCallingMouth"
	shout.texture = MOUTH
	shout.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shout.z_index = meshes.ArtMesh3.z_index
	shout.hide(); model.add_child(shout)

func apply(meshes: Dictionary, head: Transform2D, rig, weight: float, hit_active: bool = false) -> void:
	var eye_weight := weight if use_squeezed_eyes and not hit_active and not summoning else 0.0
	for i in eyes.size():
		var feature: Array = Drag.FEATURES[i]
		eyes[i].transform = head*Transform2D(0.0,feature[2]/feature[0].get_size(),0.0,feature[1]-Vector2(1024,1024))
		eyes[i].visible = eye_weight>0.00001
		eyes[i].modulate.a = eye_weight
	for id in EYE_IDS: meshes[id].self_modulate.a *= 1.0-eye_weight
	# Reveal the normal mouth only once the custom jaw has almost closed.
	var mouth_alpha := smoothstep(0.025,0.16,mouth_open)
	shout.visible = mouth_alpha>0.00001; shout.modulate.a = mouth_alpha
	var scale_value := Vector2(lerpf(0.20,1.35,smoothstep(0.0,1.0,mouth_open)),lerpf(0.06,1.42,mouth_open))
	var mouth_center := Chewing.CENTER.lerp(Falling.MOUTH_CENTER,smoothstep(0.05,0.7,mouth_open))
	# Original bitmap orientation: no local horizontal mirror.
	shout.transform = head*Transform2D(0.0,scale_value,0.0,mouth_center)
	for id in ["ArtMesh3","ArtMesh4"]: meshes[id].self_modulate.a *= 1.0-mouth_alpha
	if weight<=0.00001: return
	var front: int = maxi(meshes.ArtMesh18.z_index,meshes.ArtMesh5.z_index)+4
	rig.near.z_index = front+1
	# As in the reference, the far arm is behind the far cheek, not across the eye.
	rig.far.z_index = meshes.ArtMesh26.z_index
	rig.braid_layers.pieces[0].node.z_index = meshes.ArtMesh17.z_index
	rig.braid_layers.pieces[1].node.z_index = front+2
	rig.braid_layers.apply(1.0)
	for i in 2:
		var sprite: Sprite2D = rig.near if i==0 else rig.far
		var anchor := Arm.NEAR_ROOT if i==0 else Arm.FAR_REST_ROOT
		var palm := Arm.NEAR_PALM if i==0 else Arm.FAR_REST_PALM
		var original := sprite.transform
		var socket := original*anchor
		var ray := original.basis_xform(palm-anchor)
		var wave := sin(time*TAU*1.2+(0.0 if i==0 else 0.35))
		if summoning:
			wave = 0.65*wave+0.35*sin(time*TAU*1.87+(0.0 if i==0 else 1.1))
		var target := deg_to_rad((-77.0 if i==0 else -125.0)+wave*(7.0 if i==0 else 5.0))
		var turn := ray.angle_to(Vector2.from_angle(target))*weight
		var changed := Transform2D(turn,Vector2.ZERO)*original
		changed.origin = socket-changed.basis_xform(anchor)
		sprite.transform = changed
	rig.update_anchors()

