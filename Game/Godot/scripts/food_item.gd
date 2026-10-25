extends RefCounted
## Read-only icon. Rounded nibbles advance across the square, independent of its art.
const DISPLAY_SIDE := 500.0
const MAX_BITES := 12
const PROFILE_COLUMNS := 128
const HOLD := Vector2(-365.0,345.0)
const NEAR_HOLD := Vector2(-190.0,375.0)
const DEMO_TEXTURES := [preload("res://assets/feeding/icon_notes.svg"),preload("res://assets/feeding/icon_photos.svg"),preload("res://assets/feeding/icon_music.svg")]
var texture: Texture2D
var bounds := Rect2()
var pixel_size := Vector2.ONE
var display_scale := 1.0
var label := ""
var error := ""
var source: Dictionary = {} # Bowl identity; ordinary PNG demonstrations remain read-only.

static func from_texture(source: Texture2D, title: String = "食物") -> RefCounted:
	var item = load("res://scripts/food_item.gd").new()
	item.label = title
	item.texture = source
	item.analyze(source.get_image())
	return item

static func from_png(path: String) -> RefCounted:
	var item = load("res://scripts/food_item.gd").new()
	item.label = path.get_file()
	if path.get_extension().to_lower() != "png":
		item.error = "请选择 PNG 图片"
		return item
	var image := Image.new()
	if image.load(path) != OK:
		item.error = "无法读取图片"
		return item
	# Bound runtime upload/analysis cost without ever rewriting the source file.
	if maxi(image.get_width(),image.get_height()) > 1536:
		var ratio := 1536.0/maxi(image.get_width(),image.get_height())
		image.resize(maxi(1,roundi(image.get_width()*ratio)),maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	item.texture = ImageTexture.create_from_image(image)
	item.analyze(image)
	return item

func analyze(image: Image) -> void:
	if image == null or image.is_empty(): error = "空图片"; return
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	pixel_size = Vector2(image.get_size())
	var bytes := image.get_data()
	var peak := 0
	for at in range(3,bytes.size(),4): peak = maxi(peak,bytes[at])
	if peak == 0: error = "全透明图片"; return
	# Transparent padding is part of the icon's canvas, never a grip/crop signal.
	# Non-square input is simply fitted inside the same virtual square.
	var side := maxf(pixel_size.x,pixel_size.y)
	bounds = Rect2((pixel_size-Vector2.ONE*side)*0.5,Vector2.ONE*side)
	display_scale = DISPLAY_SIDE/side

func valid() -> bool: return error.is_empty() and texture != null and bounds.has_area()

static func cut_edge(x: float, cut: Vector4) -> float:
	var dx := x-cut.x
	if absf(dx)>=cut.z: return 0.0
	return clampf(cut.y+sqrt(maxf(0.0,cut.z*cut.z-dx*dx)),0.0,1.0)

static func cut_profile(profile: PackedFloat32Array, cut: Vector4) -> PackedFloat32Array:
	var result := profile.duplicate()
	for i in result.size(): result[i] = maxf(result[i],cut_edge((i+0.5)/result.size(),cut))
	return result

func remaining(profile: PackedFloat32Array) -> Dictionary:
	var top := 1.0
	var mass := 0.0
	for y in profile:
		top = minf(top,y)
		mass += 1.0-y
	mass /= profile.size()
	var visible := Rect2(bounds.position+Vector2(0.0,bounds.size.y*top),bounds.size*Vector2(1.0,1.0-top))
	var gather := smoothstep(0.15,0.85,1.0-mass)
	# Anchor the near wrist in a relaxed diagonal embrace. The remnant moves
	# into that palm; its asymmetric notches never steer the arm or cuff.
	var best := PROFILE_COLUMNS-1
	var distance := INF
	for i in profile.size():
		if 1.0-profile[i] < (1.0-top)*0.50: continue
		# Hold nearer the right edge: the icon sits slightly farther forward
		# while the wrist and the accepted sleeve angle stay in place.
		var gap := absf((i+0.5)/profile.size()-0.90)
		if gap < distance: distance = gap; best = i
	var x := (best+0.5)/profile.size()
	var y := maxf(lerpf(top,1.0,0.50),profile[best]+(1.0-top)*0.16)
	var near := bounds.position+bounds.size*Vector2(x,y)
	var near_world := NEAR_HOLD+Vector2(14.0,-8.0)*gather
	var far_world := Vector2(-455.0,350.0)+Vector2(28.0,-8.0)*gather
	# As only a thin remnant remains, the open far palm cups its underside.
	# This gradual change is based on quantity, not the next bite's side.
	var under := 1.0-smoothstep(0.15,0.45,mass)
	far_world.y = lerpf(far_world.y,near_world.y+(bounds.end.y-near.y)*display_scale+12.0,under)
	var center := near-(near_world-HOLD)/display_scale
	# The far palm supports the back face, not the left border of every icon.
	var far := center+(far_world-HOLD)/display_scale
	# The approved larger icon puts the near hand at 81.25% across and
	# 64.0625% down. Pick a surviving column only when that grip is eaten;
	# interpolation between bite plans makes the remnant settle smoothly.
	var hold_x := 0.8125
	var hold_column := clampi(int(hold_x*profile.size()),0,profile.size()-1)
	if 1.0-profile[hold_column] < (1.0-top)*0.50:
		var gap := INF
		for i in profile.size():
			if 1.0-profile[i] < (1.0-top)*0.50: continue
			var candidate := (i+0.5)/profile.size()
			if absf(candidate-0.8125)<gap:
				gap = absf(candidate-0.8125); hold_x = candidate; hold_column = i
	var hold_y := maxf(lerpf(top,1.0,0.640625),profile[hold_column]+(1.0-top)*0.18)
	var hold_grip := bounds.position+bounds.size*Vector2(hold_x,hold_y)
	return {"bounds":visible,"center":center,"top":top,"mass":mass,
		"near":near,"far":far,"profile":profile,"hold_grip":hold_grip}

static func blend_parts(before: Dictionary, after: Dictionary, weight: float) -> Dictionary:
	return {"center":before.center.lerp(after.center,weight),"near":before.near.lerp(after.near,weight),
		"hold_grip":before.hold_grip.lerp(after.hold_grip,weight),
		"far":before.far.lerp(after.far,weight),"top":lerpf(before.top,after.top,weight),
		"mass":lerpf(before.mass,after.mass,weight),
		"bounds":Rect2(before.bounds.position.lerp(after.bounds.position,weight),before.bounds.size.lerp(after.bounds.size,weight))}

func plan_bites(count: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	count = clampi(count,2,MAX_BITES)
	var result: Array[Dictionary] = []
	var weights := PackedFloat32Array()
	var weight_sum := 0.0
	for bite in count:
		var weight := rng.randf_range(0.88,1.12)*(0.85 if bite == count-1 else 1.0)
		weights.append(weight)
		weight_sum += weight
	var profile := PackedFloat32Array()
	profile.resize(PROFILE_COLUMNS)
	var eaten := 0.0
	for bite in count:
		var before := remaining(profile)
		eaten += weights[bite]/weight_sum
		var center_x := (0.18 if bite%2 == 0 else 0.82)+rng.randf_range(-0.018,0.018)
		var radius := rng.randf_range(0.49,0.53)
		var cut := Vector4(center_x,0.0,radius,radius)
		if bite == count-1:
			# One last rounded bite covers every remaining pixel, including edges.
			cut = Vector4(0.5,1.0,0.72,0.72)
		else:
			# Advance only this circular bite until it removes its small share.
			# The next bite is on the opposite side, progressively clearing rows.
			var low := -radius
			var high := 1.0
			for iteration in 18:
				cut.y = (low+high)*0.5
				var candidate := cut_profile(profile,cut)
				var consumed := 0.0
				for y in candidate: consumed += y/PROFILE_COLUMNS
				if consumed < eaten: low = cut.y
				else: high = cut.y
			cut.y = high
		var next_profile := cut_profile(profile,cut)
		result.append({"before":before,"after":remaining(next_profile),"cut":cut})
		profile = next_profile
	return result

func layout(part: Dictionary, scale_override: float = 0.0) -> Dictionary:
	var scale := scale_override if scale_override > 0.0 else display_scale
	# Keep the remaining portion centered between the hands at chest height.
	# Only crop/reposition the original pixels; never stretch or shrink the art.
	var near: Vector2 = HOLD+(part.near-part.center)*scale
	var far: Vector2 = HOLD+(part.far-part.center)*scale
	return {"hold":HOLD,"near":near,"far":far,"source":part.center}
