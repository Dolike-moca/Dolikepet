extends RefCounted
## Continuous pot-foot / crown collision, in desktop coordinates.
const GRAVITY := 1700.0
const MIN_DROP := 0.035
const HIGH_DROP := 0.65
const MAX_DROP := 1.8

static func intensity(height: float) -> float:
	return smoothstep(MIN_DROP,MAX_DROP,maxf(0.0,height))

static func dizzy_seconds(height: float) -> float:
	return lerpf(3.0,6.0,smoothstep(HIGH_DROP,MAX_DROP,maxf(0.0,height)))

static func classify(distance: float, speed: float, extent: float) -> String:
	if extent<=0.0 or speed<=0.0 or distance<extent*MIN_DROP: return ""
	var energy_height := speed*speed/(2.0*GRAVITY)
	return "hard" if maxf(distance,energy_height)>=extent*HIGH_DROP else "light"

static func sweep(before: Vector2, after: Vector2, feet: PackedVector2Array,
		cap: PackedVector2Array, head_delta := Vector2.ZERO) -> Dictionary:
	if after.y<=before.y or cap.size()<2: return {}
	var earliest := 2.0
	var contact := Vector2.ZERO
	for foot in feet:
		var start := before+foot+head_delta
		var end := after+foot
		if end.y<=start.y: continue
		for i in cap.size()-1:
			var point = Geometry2D.segment_intersects_segment(start,end,cap[i],cap[i+1])
			if point==null: continue
			var fraction := start.distance_to(point)/maxf(0.00001,start.distance_to(end))
			if fraction<earliest:
				earliest = fraction; contact = point
	if earliest>1.0: return {}
	return {"fraction":earliest,"point":contact,"position":before.lerp(after,earliest)}

static func deflection(at: Vector2, size: Vector2, cap: PackedVector2Array, area: Rect2) -> Vector2:
	var bounds := Rect2(cap[0],Vector2.ZERO)
	for point in cap: bounds = bounds.expand(point)
	var left := clampf(bounds.position.x-size.x-8.0,area.position.x,area.end.x-size.x)
	var right := clampf(bounds.end.x+8.0,area.position.x,area.end.x-size.x)
	var left_clear := left+size.x<=bounds.position.x
	var right_clear := right>=bounds.end.x
	var choose_left := at.x+size.x*0.5<bounds.get_center().x
	if left_clear!=right_clear: choose_left = left_clear
	return Vector2(left if choose_left else right,clampf(at.y,area.position.y,area.end.y-size.y))
