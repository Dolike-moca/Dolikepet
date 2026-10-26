extends "res://scripts/arm_rig.gd"
## Approved seated embrace. Whole arms rotate about fixed shoulder sockets;
## their artwork is never bent or stretched to chase an icon or a bite.
const FOOD_SIDE := 495.05664
const FOOD_ANGLE := -0.0085073
const REFERENCE_CARRY := Vector2(9.149177,-6.403062)
const SOURCE := Vector2(-754,726)
const DepthLayers = preload("res://scripts/pickup_arm_layers.gd")
# The diagonal seam follows the sidelock's lower edge: it stays beneath the
# lock but above the bare shoulder. Both halves sample the same live triangles.
const BRAID_DEPTH_SEAM := Vector2(80,1210.0-1024.0)
const BRAID_DEPTH_NORMAL := Vector2(-0.6,1.0)
var braid_layers = DepthLayers.new()
var enabled := false
var food_source := Vector2.ZERO
var gaze_point := Vector2.ZERO

func setup(model: Node2D, meshes: Dictionary) -> void:
	super.setup(model,meshes)
	braid_layers.setup(model,meshes.ArtMesh17,BRAID_DEPTH_SEAM,BRAID_DEPTH_NORMAL,0.0,meshes.ArtMesh17.z_index)
	braid_layers.pieces[0].node.name = "NearBraidRoot"
	braid_layers.pieces[1].node.name = "NearBraidOverArm"

static func arm_transform(hold: Transform2D, source_root: Vector2, source_palm: Vector2,
		start_angle: float, weight: float, carry: Vector2, turn: float) -> Transform2D:
	var root := hold*source_root
	var ray := hold*source_palm-root
	var carry_turn := clampf(ray.angle_to(ray+carry),-deg_to_rad(6.0),deg_to_rad(6.0))
	var angle := lerp_angle(start_angle,hold.get_rotation()+carry_turn+turn,weight)
	return anchored(hold,source_root,angle)

func apply(meshes: Dictionary, body: Transform2D, upper: Transform2D, pose: Dictionary,
		food: Sprite2D, weight: float, near_layers, far_layers, far_order: int) -> void:
	var alignment := upper*body
	var mushroom:bool=pose.get("sizeMushroom",false)
	var small_piece:=1.0-smoothstep(0.12,0.35,float(pose.get("foodRemaining",1.0)))
	apply_rest(meshes,alignment,near_layers,far_layers)
	enabled = weight>0.00001
	braid_layers.pieces[0].node.z_index = meshes.ArtMesh17.z_index
	braid_layers.pieces[1].node.z_index = food.z_index+2
	braid_layers.apply(1.0 if enabled else 0.0)
	if not enabled: return
	near.z_index = food.z_index+1
	far.z_index = far_order
	# Only the hanging braid covers the raised arm. Its root stays behind
	# sidelocks/scarf; the far braid already covers the far arm at native depth.
	var carry: Vector2 = pose.get("pickupCarry",Vector2.ZERO)-REFERENCE_CARRY
	carry.y += 11.0*pose.get("pickupCatch",0.0)
	var tilt: float = pose.get("pickupIconTilt",0.0)
	var release: float = pose.get("holdRelease",0.0)
	# The growth prop lifts to the mouth by rotating these same rigid arms.
	# Smaller remnants rise farther; shoulder sockets and bone lengths stay fixed.
	var mushroom_lift: float = pose.get("sizeFoodLift",0.0)
	var mushroom_turn := deg_to_rad(30.0+35.0*(1.0-pose.get("foodRemaining",1.0)))*mushroom_lift
	# Same sockets before, during and after reaching; only rotate the arms.
	# Use the shared lowered rest orientation for reach/release. The 8-degree
	# correction blends out as weight reaches one, keeping the held pose intact.
	var near_local := arm_transform(NEAR_HOLD,NEAR_ROOT,NEAR_PALM,
		rest_angles.ArtMesh19,weight,carry,tilt*0.35+mushroom_turn)
	var far_local := arm_transform(FAR_HOLD,FAR_ROOT,FAR_PALM,
		rest_angles.ArtMesh26,weight,carry*0.65,-deg_to_rad(24.0)*release+mushroom_turn)
	# Move between the PSD rest shoulder and the approved feeding socket.
	# Turn the hand as the arm lifts; never expose the palm artwork at idle.
	var far_socket := FAR_REST_SOCKET.lerp(SOCKETS.ArtMesh26,weight)
	far_local.x *= FAR_HOLD_ART_SCALE
	far_local.y *= FAR_HOLD_ART_SCALE
	far_local.origin = far_socket-far_local.basis_xform(FAR_ROOT)
	var hand_turn := smoothstep(0.10,0.65,weight)
	var open_axis := FAR_PALM-FAR_ROOT
	var closed_axis := FAR_REST_PALM-FAR_REST_ROOT
	var closed_angle := far_local.get_rotation()+open_axis.angle()-closed_axis.angle()
	var closed_scale := lerpf(1.0,open_axis.length()*FAR_HOLD.x.length()*FAR_HOLD_ART_SCALE/closed_axis.length(),weight)
	var closed_local := Transform2D(closed_angle,Vector2.ONE*closed_scale,0.0,Vector2.ZERO)
	closed_local.origin = far_socket-closed_local*FAR_REST_ROOT
	far_rest_overlay.transform = alignment*closed_local
	far_rest_overlay.z_index = far_order
	far_rest_overlay.modulate.a = 1.0-hand_turn
	far_rest_overlay.visible = hand_turn<0.99999
	far.texture = FarArt
	far.modulate.a = hand_turn
	near.transform = alignment*near_local
	far.transform = alignment*far_local
	update_anchors()
	var item = pose.get("foodItem")
	if item == null: return
	# A content-independent square grip moves the remaining icon into the
	# same palm. It does not resize the food or force an arm to chase its cuts.
	var part: Dictionary = pose.foodPart
	food_source = part.hold_grip
	if mushroom:
		food_source=item.bounds.position+item.bounds.size*Vector2(lerpf(0.82,0.54,small_piece),lerpf(0.72,0.96,small_piece))
	food.offset = item.pixel_size*0.5-food_source
	var flight: float = pose.get("pickupFlight",0.0)
	var scale: float = FOOD_SIDE/item.bounds.size.x*lerpf(0.65,1.0,smoothstep(0.0,0.8,flight))
	var angle := FOOD_ANGLE+tilt-deg_to_rad(7.0)*sin(flight*PI)
	# Tip the small mushroom remnant toward the mouth around the gripping palm.
	# File icons retain their existing orientation and grip.
	angle += deg_to_rad(25.0)*(1.0-pose.get("foodRemaining",1.0))*mushroom_lift
	if mushroom:
		scale=item.display_scale
		angle=deg_to_rad(3.0+13.0*(1.0-pose.get("foodRemaining",1.0)))*pose.get("sizeFoodApproach",0.0)
	var basis := Transform2D.IDENTITY.interpolate_with(upper,smoothstep(0.55,1.0,flight))*body
	food.transform = basis*Transform2D(angle,Vector2.ONE*scale,0.0,Vector2.ZERO)
	var launch: Vector2 = food.get_parent().transform.affine_inverse()*SOURCE \
		+ food.transform.basis_xform(food_source-item.pixel_size*0.5)
	if pose.has("bowlSource"):
		launch = food.get_parent().global_transform.affine_inverse()*pose.bowlSource \
			+ food.transform.basis_xform(food_source-item.pixel_size*0.5)
	food.position = launch.lerp(palms.ArtMesh19,flight)-body.basis_xform(Vector2(0,140.0*sin(flight*PI)))
	if mushroom: _apply_mushroom_support(alignment,pose,food,weight)
	gaze_point = food.transform*(part.bounds.get_center()-food_source)

func _apply_mushroom_support(alignment:Transform2D,pose:Dictionary,food:Sprite2D,weight:float) -> void:
	var item=pose.foodItem
	# The far hand supports the underside, then turns back before lowering.
	# Its timed handoff is independent of the sharp cuts made by each bite.
	var support:float=pose.get("sizeFarSupport",1.0)
	var hold_weight:=weight*support
	var point:Vector2=item.bounds.position+item.bounds.size*Vector2(0.22,0.88)
	var local:Vector2=point-food_source
	local.y*=lerpf(0.86,1.0,point.x/item.pixel_size.x)
	var target:Vector2=alignment.affine_inverse()*(food.transform*local)
	var socket:=FAR_REST_SOCKET.lerp(SOCKETS.ArtMesh26,weight)
	var axis:=FAR_PALM-FAR_ROOT
	# Keep angular subtraction continuous at the left-facing atan2 seam.
	# The upper bound keeps the supporting palm below the face.
	var desired:=clampf(wrapf((target-socket).angle()-axis.angle(),-PI,PI),deg_to_rad(-25),deg_to_rad(42))
	var angle:=lerp_angle(rest_angles.ArtMesh26,desired,hold_weight)
	var scale:=FAR_HOLD.x.length()*FAR_HOLD_ART_SCALE
	var held:=Transform2D(angle,Vector2.ONE*scale,0.0,Vector2.ZERO)
	held.origin=socket-held*FAR_ROOT
	far.transform=alignment*held
	var back_axis:=FAR_REST_PALM-FAR_REST_ROOT
	var back:=Transform2D(angle+axis.angle()-back_axis.angle(),Vector2.ONE*(axis.length()*scale/back_axis.length()),0.0,Vector2.ZERO)
	back.origin=socket-back*FAR_REST_ROOT
	far_rest_overlay.transform=alignment*back
	var hand_turn:=smoothstep(0.05,0.85,weight)*float(pose.get("sizeFarHandOpen",1.0))
	far.modulate.a=hand_turn
	far_rest_overlay.modulate.a=1.0-hand_turn
	far_rest_overlay.visible=hand_turn<0.99999
	update_anchors()
