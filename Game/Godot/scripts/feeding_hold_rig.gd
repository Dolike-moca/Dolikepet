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
	# Same sockets before, during and after reaching; only rotate the arms.
	# Use the shared lowered rest orientation for reach/release. The 8-degree
	# correction blends out as weight reaches one, keeping the held pose intact.
	var near_local := arm_transform(NEAR_HOLD,NEAR_ROOT,NEAR_PALM,
		rest_angles.ArtMesh19,weight,carry,tilt*0.35)
	var far_local := arm_transform(FAR_HOLD,FAR_ROOT,FAR_PALM,
		rest_angles.ArtMesh26,weight,carry*0.65,-deg_to_rad(24.0)*release)
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
	food.offset = item.pixel_size*0.5-food_source
	var flight: float = pose.get("pickupFlight",0.0)
	var scale: float = FOOD_SIDE/item.bounds.size.x*lerpf(0.65,1.0,smoothstep(0.0,0.8,flight))
	var angle := FOOD_ANGLE+tilt-deg_to_rad(7.0)*sin(flight*PI)
	var basis := Transform2D.IDENTITY.interpolate_with(upper,smoothstep(0.55,1.0,flight))*body
	food.transform = basis*Transform2D(angle,Vector2.ONE*scale,0.0,Vector2.ZERO)
	var launch: Vector2 = food.get_parent().transform.affine_inverse()*SOURCE \
		+ food.transform.basis_xform(food_source-item.pixel_size*0.5)
	if pose.has("bowlSource"):
		launch = food.get_parent().global_transform.affine_inverse()*pose.bowlSource \
			+ food.transform.basis_xform(food_source-item.pixel_size*0.5)
	food.position = launch.lerp(palms.ArtMesh19,flight)-body.basis_xform(Vector2(0,140.0*sin(flight*PI)))
	gaze_point = food.transform*(part.bounds.get_center()-food_source)
