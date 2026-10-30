extends RefCounted
## A quiet seated upper body. No new artwork, arm length, or layer-order changes.
const Secondary = preload("res://scripts/secondary_deformation.gd")
const Sitting = preload("res://scripts/sitting_pose.gd")
const COLLAR_Y := 1280.0-1024.0
const CURVED := ["ArtMesh24","ArtMesh5","ArtMesh20"]
const EARS := ["ArtMesh15","ArtMesh16"]
var ear_roots := {}
var decoration_layer: CanvasLayer
var mark: Node2D

class SleepMark extends Node2D:
	const TEXT := "zzz"
	const FONT_SIZE := 144
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_string_outline(font,Vector2.ZERO,TEXT,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,7,Color("3c284f"))
		draw_string(font,Vector2.ZERO,TEXT,HORIZONTAL_ALIGNMENT_LEFT,-1,FONT_SIZE,Color("d6bbf1"))

func setup(owner: Node2D, meshes: Dictionary) -> void:
	for id in EARS:
		var points := Secondary.read_points(meshes[id])
		var bounds := Rect2(points[0],Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		ear_roots[id] = Vector2(bounds.get_center().x,bounds.end.y-12.0)
	# A separate canvas is intentionally absent from the host's shared-world
	# alpha hit viewport. Decorative Z pixels must never become drag targets.
	decoration_layer = CanvasLayer.new()
	decoration_layer.name = "SleepDecorations"
	decoration_layer.layer = 2
	owner.add_child(decoration_layer)
	mark = SleepMark.new(); mark.name = "SleepZ"; mark.hide()
	decoration_layer.add_child(mark)

static func weight(pose: Dictionary) -> float:
	if pose.get("dragHeld",false) or pose.get("fallActive",false) or pose.get("landingActive",false) \
		or pose.get("dizzyActive",false) or pose.get("bowlHitActive",false) or pose.get("mealActive",false) \
		or pose.get("bowlCalling",false) or float(pose.get("bowlReach",0.0))>0.001: return 0.0
	return clampf(float(pose.get("sleepWeight",0.0)),0.0,1.0)

static func prepare(pose: Dictionary) -> Dictionary:
	var amount := weight(pose)
	if amount<=0.0: return pose
	var result := pose.duplicate()
	var phase := float(pose.get("sleepPhase",0.0))
	var eye := clampf(float(pose.get("sleepEye",0.0)),0.0,1.0)
	# sleepEye already describes its full slow blink/reopening. Weight blends
	# the head/body, while the eyes never accidentally blink fully open in sleep.
	result.eyeNear = minf(float(pose.eyeNear),eye)
	result.eyeFar = minf(float(pose.eyeFar),eye)
	result.headZ = lerpf(float(pose.headZ),-4.8+0.25*sin(phase*TAU/4.0),amount)
	result.gazeX = lerpf(float(pose.gazeX),0.0,amount)
	result.gazeY = lerpf(float(pose.gazeY),0.0,amount)
	result.bodyX = lerpf(float(pose.bodyX),0.0,amount)
	# Freeze the model's broader breathing at a neutral value; only the local
	# waist-to-collar field below supplies the slow sleep breath.
	result.breath = lerpf(float(pose.breath),0.35,amount)
	result.mouth = float(pose.mouth)*(1.0-amount)
	for key in Secondary.HAIR.values():
		var name: String = key[0]
		result[name] = float(pose.get(name,0.0))*(1.0-0.82*amount)
		result[name+"Y"] = float(pose.get(name+"Y",0.0))*(1.0-0.82*amount)
	return result

static func upper_offset(pose: Dictionary) -> Vector2:
	var amount := weight(pose)
	var phase := float(pose.get("sleepPhase",0.0))
	var stretch := clampf(float(pose.get("sleepWakeStretch",0.0)),0.0,1.0)
	return Vector2(0.0,(6.5+3.5*sin(phase*TAU/4.0))*amount-7.0*stretch*amount)

func apply_upper(meshes: Dictionary, body: Transform2D, head: Transform2D, pose: Dictionary, faces: Array, rig) -> void:
	var amount := weight(pose)
	if amount<=0.0: return
	var offset := upper_offset(pose)
	var translation := Transform2D(0.0,body.basis_xform(offset))
	var inverse := body.affine_inverse()
	for id in meshes:
		if id in Sitting.LOWER_IDS or id == "ArtMesh28": continue
		var points := Secondary.read_points(meshes[id])
		for i in points.size():
			var influence := 1.0-smoothstep(COLLAR_Y,Sitting.WAIST.y,(inverse*points[i]).y) if id in CURVED else 1.0
			points[i] += translation.origin*influence
		Secondary.write_points(meshes[id],points)
	for sprite in faces:
		if sprite.visible: sprite.transform = translation*sprite.transform
	# The shared whole-arm artwork receives precisely the same rigid shift as
	# its shoulder guides. Its bone lengths and the accepted rest angles stay put.
	for sprite in [rig.near,rig.far,rig.far_rest_overlay]:
		if sprite.visible: sprite.transform = translation*sprite.transform
	rig.update_anchors()
	var phase := float(pose.get("sleepPhase",0.0))
	for index in EARS.size():
		var age := fposmod(phase-(6.0 if index==0 else 9.5),13.0)
		var twitch := sin(age/0.65*TAU)*sin(age/0.65*PI) if age<0.65 else 0.0
		if is_zero_approx(twitch): continue
		var id: String = EARS[index]
		var pivot: Vector2 = translation*(head*ear_roots[id])
		var points := Secondary.read_points(meshes[id])
		for i in points.size(): points[i] = pivot+(points[i]-pivot).rotated(deg_to_rad(1.5)*twitch*amount)
		Secondary.write_points(meshes[id],points)

static func apply_tail(tail, node: MeshInstance2D, raw: PackedVector2Array, body: Transform2D, pose: Dictionary) -> void:
	var amount := weight(pose)
	if amount<=0.0: return
	var saved_angle: float = tail.angle
	var saved_tip: float = tail.tip_angle
	var phase := float(pose.get("sleepPhase",0.0))
	var age := fposmod(phase-7.0,10.5)
	var twitch := sin(age/1.4*TAU)*pow(sin(age/1.4*PI),2.0) if age<1.4 else 0.0
	tail.angle *= 1.0-0.92*amount
	tail.tip_angle = tail.tip_angle*(1.0-0.92*amount)+deg_to_rad(2.0)*twitch*amount
	tail.apply(node,raw,body)
	tail.angle = saved_angle; tail.tip_angle = saved_tip

func update_decoration(owner: Node2D, model: Node2D, head: Transform2D, pose: Dictionary, pixel_scale: float) -> void:
	var amount := weight(pose)
	var closed := 1.0-smoothstep(0.03,0.25,float(pose.get("sleepEye",1.0)))
	var phase := fposmod(float(pose.get("sleepPhase",0.0))-5.0,4.5)
	var progress := clampf(phase/2.6,0.0,1.0)
	var alpha := amount*closed*smoothstep(0.0,0.2,progress)*(1.0-smoothstep(0.65,1.0,progress))
	mark.visible = amount>0.0 and alpha>0.001 and phase<2.6
	if not mark.visible: return
	var anchor := Vector2(1540.0,510.0)-Vector2(1024,1024)
	var direction := -1.0 if owner.get_global_transform().x.x<0.0 else 1.0
	mark.scale = Vector2.ONE*pixel_scale*lerpf(0.75,1.05,progress)
	mark.position = owner.get_global_transform()*(model.transform*(head*anchor)) \
		+ Vector2(22.0*progress*direction,-110.0*progress)*pixel_scale
	# Keep letters readable while anchoring them outside either ear.
	if direction<0.0:
		mark.position.x -= ThemeDB.fallback_font.get_string_size(SleepMark.TEXT,HORIZONTAL_ALIGNMENT_LEFT,-1,SleepMark.FONT_SIZE).x*mark.scale.x
	mark.modulate.a = alpha*0.85
