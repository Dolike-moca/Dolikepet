extends RefCounted
## Desktop-coordinate ballistics. Continuous silhouette/crown collision and
## wall time-of-impact prevent tunnelling at launch speed or low frame rates.
const GRAVITY := 1700.0
const CHARGE_SECONDS := 0.8
const GroundRoll = preload("res://scripts/bowl_roll.gd")
var ground_roll = GroundRoll.new()
var rng := RandomNumberGenerator.new()
var state := "idle"
var center := Vector2.ZERO
var velocity := Vector2.ZERO
var angle := 0.0
var angular_velocity := 0.0
var hits := 0
var recoil_age := 1.0
var head_velocity := Vector2.ZERO
var wall_contacts := 0
var rolling := false
var shape := Vector2.ONE
var glow := 0.0
var area := Rect2()
var outline := PackedVector2Array()
var pot_size := Vector2.ZERO
var age := 0.0
var time := 0.0
var walls := 0
var boosted := false
var armed := false
var separated := false
var last_cap := PackedVector2Array()
var base_height := 1.0
var height_ratio := 1.0
var special := false
var spin_start := 0.0
var spin_turns := 0.0
var spin_seconds := 1.0
var next_special_override := -1 # Isolated deterministic fixtures only.

func _init() -> void: rng.randomize()
func active() -> bool: return state not in ["idle","settle"]
func animating() -> bool: return state!="idle"
func cancel() -> void:
	state = "idle"; glow = 0.0; shape = Vector2.ONE; velocity = Vector2.ZERO
	angular_velocity = 0.0; head_velocity = Vector2.ZERO; last_cap.clear()
	ground_roll.cancel()
func start(at: Vector2, size: Vector2, polygon: PackedVector2Array, bounds: Rect2, contact := {}) -> void:
	pot_size = size; outline = polygon; area = bounds; center = at
	base_height = maxf(20.0,size.y*0.70); time = 0.0; last_cap.clear()
	hits = 0; wall_contacts = 0; rolling = false
	angle = float(contact.get("angle",0.0)); angular_velocity = float(contact.get("spin",0.0))
	velocity = contact.get("velocity",Vector2.ZERO)
	head_velocity = contact.get("head_velocity",Vector2.ZERO)
	_bounce(contact.get("point",center+Vector2(0,bounds().end.y)),contact.get("normal",Vector2.UP))

func difficulty() -> Dictionary:
	# C: gentle opening, continuous ramp to a bounded aggressive late round.
	var t := clampf((hits-1)/59.0,0.0,1.0)
	return {"progress":t,"chance":lerpf(0.04,0.38,t),"launch":lerpf(1.25,3.0,t),
		"height":lerpf(1.0,1.85,t),"restitution":lerpf(0.55,0.80,t)}

func _inertia() -> float: return maxf(1.0,pot_size.length_squared()*0.14)
func _speed_limit() -> float: return sqrt(2.0*GRAVITY*base_height)*4.0
func _perp(value: Vector2) -> Vector2: return Vector2(-value.y,value.x)

func _impulse(point: Vector2, normal: Vector2, surface: Vector2, restitution: float, lift := 0.0, friction := 0.14) -> void:
	var arm := point-center
	var relative := velocity+_perp(arm)*angular_velocity-surface
	var normal_speed := relative.dot(normal)
	if normal_speed>=0.0 and lift<=0.0: return
	var inertia := _inertia()
	var j := (maxf(lift,-normal_speed*restitution)-normal_speed)/(1.0+pow(arm.cross(normal),2)/inertia)
	j = maxf(0.0,j)
	velocity += normal*j; angular_velocity += arm.cross(normal*j)/inertia
	var tangent := _perp(normal)
	relative = velocity+_perp(arm)*angular_velocity-surface
	var slide := -relative.dot(tangent)/(1.0+pow(arm.cross(tangent),2)/inertia)
	slide = clampf(slide,-j*friction,j*friction)
	velocity += tangent*slide; angular_velocity += arm.cross(tangent*slide)/inertia
	angular_velocity = clampf(angular_velocity,-12.0,12.0)
	velocity = velocity.limit_length(_speed_limit())

func bounds(turn := NAN) -> Rect2:
	if is_nan(turn): turn = angle
	var result := Rect2(outline[0].rotated(turn),Vector2.ZERO)
	for point in outline: result = result.expand(point.rotated(turn))
	return result

func _radius() -> float:
	var radius := 0.0
	for point in outline: radius = maxf(radius,point.length())
	return radius+3.0

func _bounce(point := Vector2.INF, normal := Vector2.UP) -> void:
	hits += 1; age = 0.0; recoil_age = 0.0; glow = 0.0; walls = 0; boosted = false
	armed = false; separated = false
	var level := difficulty()
	height_ratio = rng.randf_range(1.0,3.0)
	special = rng.randf()<float(level.chance)
	if next_special_override>=0: special = next_special_override==1; next_special_override = -1
	var rise := base_height*height_ratio*float(level.height)
	var radius := _radius()
	var headroom := center.y-(area.position.y+radius)
	if special and headroom>pot_size.y*0.25 and area.size.x>radius*2.0:
		rise = minf(maxf(rise,base_height*3.5),headroom)
	else: special = false
	var speed := sqrt(2.0*GRAVITY*rise)
	if not point.is_finite(): point = center+Vector2(0,bounds().end.y)
	# A powered cat bounce adds energy only at contact. Its finite, measured
	# head velocity supplies 75% of the moving-surface impulse, never the cursor.
	_impulse(point,normal,head_velocity.limit_length(pot_size.y*8.0)*0.75,float(level.restitution),speed,0.24)
	if special:
		# Reach a position where a full rotation fits, before suspending.
		var goal := clampf(center.x+velocity.x*speed/GRAVITY,area.position.x+radius,area.end.x-radius)
		velocity = Vector2((goal-center.x)/(speed/GRAVITY),-speed)
	state = "rise" if special else "flight"

static func sweep(before: Vector2, after: Vector2, polygon: PackedVector2Array,
		cap: PackedVector2Array, head_delta := Vector2.ZERO, final_polygon := PackedVector2Array()) -> Dictionary:
	if cap.size()<2: return {}
	if final_polygon.is_empty(): final_polygon = polygon
	var first := 2.0
	var point := Vector2.ZERO
	var contact_normal := Vector2.UP
	var contact_count := 0
	for i in cap.size()-1:
		var edge := cap[i+1]-cap[i]
		var normal := Vector2(edge.y,-edge.x).normalized()
		if normal.y>0.0: normal = -normal
		for j in polygon.size():
			var a := before+polygon[j]+head_delta
			var b := after+final_polygon[j]
			if (b-a).dot(normal)>=-0.00001: continue
			if (a-cap[i]).dot(normal)<-1.0: continue
			var crossing = Geometry2D.segment_intersects_segment(a,b,cap[i],cap[i+1])
			if crossing!=null:
				var f := a.distance_to(crossing)/maxf(0.000001,a.distance_to(b))
				if f<first-0.00001: first = f; point = crossing; contact_normal = normal; contact_count = 1
				elif absf(f-first)<=0.00001: point += crossing; contact_normal += normal; contact_count += 1
		# Also sweep crown vertices against the pot edges: a wide pot edge can
		# strike a narrow head without any pot vertex crossing the crown.
		for vertex in [cap[i],cap[i+1]]:
			for j in polygon.size():
				var a := before+polygon[j]+head_delta
				var b := before+polygon[(j+1)%polygon.size()]+head_delta
				if (a-vertex).dot(normal)<-1.0 and (b-vertex).dot(normal)<-1.0: continue
				var end_a := after+final_polygon[j]
				var end_b := after+final_polygon[(j+1)%polygon.size()]
				if ((end_a+end_b-a-b)*0.5).dot(normal)>=-0.00001: continue
				# Rotating edges sweep a quadrilateral. Solve its moving segment
				# crossing too, so a narrow crown cannot slip through a broad base.
				if not Geometry2D.is_point_in_polygon(vertex,PackedVector2Array([a,b,end_b,end_a])): continue
				var initial := (b-a).cross(vertex-a)
				if initial*(end_b-end_a).cross(vertex-end_a)>0.0: continue
				var lo := 0.0; var hi := 1.0
				for step in 14:
					var mid := (lo+hi)*0.5
					var ma := a.lerp(end_a,mid); var mb := b.lerp(end_b,mid)
					if initial*(mb-ma).cross(vertex-ma)>0.0: lo = mid
					else: hi = mid
				if hi<first-0.00001: first = hi; point = vertex; contact_normal = normal; contact_count = 1
				elif absf(hi-first)<=0.00001: point += vertex; contact_normal += normal; contact_count += 1
	if first>1.0: return {}
	return {"fraction":first,"point":point/maxi(1,contact_count),"position":before.lerp(after,first),"normal":contact_normal.normalized()}

func _rotated(turn := NAN) -> PackedVector2Array:
	if is_nan(turn): turn = angle
	var result := PackedVector2Array()
	for point in outline: result.append(point.rotated(turn))
	return result

func _clear_of(cap: PackedVector2Array) -> bool:
	if cap.size()<2: return true
	# Require visible separation before another head contact can score.
	var crown := Rect2(cap[0],Vector2.ZERO)
	for point in cap: crown = crown.expand(point)
	var pot := bounds(); pot.position += center
	return pot.end.y<crown.position.y-3.0 or pot.end.x<crown.position.x-3.0 or pot.position.x>crown.end.x+3.0

func _start_spin() -> void:
	var radius := _radius()
	# A prior wall hit may have changed the ascent. Do not teleport into a
	# safe spin position; continue ordinary flight when the full turn won't fit.
	if not area.grow(-radius+0.05).has_point(center):
		state = "flight"; special = false; return
	state = "spin"; age = 0.0; velocity = Vector2.ZERO; angular_velocity = 0.0
	spin_start = angle; spin_turns = rng.randf_range(1.0,5.0)*(-1.0 if rng.randf()<0.5 else 1.0)
	spin_seconds = rng.randf_range(1.25,2.8)

func _support(normal: Vector2) -> Vector2:
	var projection := INF; var result := Vector2.ZERO; var count := 0
	for point in _rotated(): projection = minf(projection,point.dot(normal))
	for point in _rotated():
		if point.dot(normal)<=projection+0.5: result += point; count += 1
	return center+result/maxi(1,count)

func _confine() -> void:
	var box := bounds()
	center.x = clampf(center.x,area.position.x-box.position.x,area.end.x-box.end.x)
	center.y = clampf(center.y,area.position.y-box.position.y,area.end.y-box.end.y)

func _land(events: Array) -> void:
	state = "settle"; age = 0.0; rolling = false; glow = 0.0; shape = Vector2.ONE
	_confine()
	var incoming := velocity; var incoming_spin := angular_velocity
	_impulse(_support(Vector2.UP),Vector2.UP,Vector2.ZERO,0.2)
	ground_roll.start(center,incoming,angle,incoming_spin,pot_size,outline,area,{"velocity":velocity,"spin":angular_velocity})
	velocity = ground_roll.velocity; angular_velocity = ground_roll.spin
	events.append({"type":"floor"})

func _settle(h: float, events: Array) -> void:
	ground_roll.area = area; ground_roll.advance(h)
	center = ground_roll.center; velocity = ground_roll.velocity
	angle = ground_roll.angle; angular_velocity = ground_roll.spin
	rolling = ground_roll.phase!="hop"
	if not ground_roll.active():
		angle = 0.0; state = "idle"
		events.append({"type":"rest"})

func _move(h: float, cap: PackedVector2Array, head_delta: Vector2, events: Array) -> void:
	var remaining := h
	var head_rest := head_delta
	for iteration in 6:
		if remaining<0.000001 or state not in ["flight","rise"]: return
		var before := center
		var after := center+velocity*remaining+Vector2(0,0.5*GRAVITY*remaining*remaining)
		var turn := angle; var end_turn := angle+angular_velocity*remaining
		var box := bounds(); var end_box := bounds(end_turn)
		var fraction := 1.0; var faces := Vector2.ZERO; var ground := false
		var distances := [before.x+box.position.x-area.position.x,area.end.x-before.x-box.end.x,before.y+box.position.y-area.position.y,area.end.y-before.y-box.end.y]
		var end_distances := [after.x+end_box.position.x-area.position.x,area.end.x-after.x-end_box.end.x,after.y+end_box.position.y-area.position.y,area.end.y-after.y-end_box.end.y]
		var normals := [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]
		var candidates := []
		for side in 4:
			if float(distances[side])>3.0: wall_contacts &= ~(1<<side)
			if float(end_distances[side])<=0.0 and float(end_distances[side])<float(distances[side]):
				candidates.append([clampf(float(distances[side])/maxf(0.000001,float(distances[side])-float(end_distances[side])),0,1),normals[side],side==3])
		for candidate in candidates:
			if candidate[0]<fraction-0.000001: fraction = candidate[0]; faces = candidate[1]; ground = candidate[2]
			elif absf(candidate[0]-fraction)<0.000001: faces += candidate[1]; ground = ground or candidate[2]
		if not armed and _clear_of(cap): separated = true
		if separated: armed = true
		# The score gate must not disable collision response: another corner of
		# a spinning pot can still contact the crown before complete separation.
		var hit := sweep(before,after,_rotated(),cap,head_rest,_rotated(end_turn))
		if not hit.is_empty() and float(hit.fraction)<fraction-0.000001:
			center = hit.position; angle = lerpf(turn,end_turn,float(hit.fraction))
			velocity.y += GRAVITY*remaining*float(hit.fraction)
			if armed:
				events.append({"type":"head","walls":walls,"boosted":boosted,"point":hit.point})
				_bounce(hit.point,hit.normal); return
			_impulse(hit.point,hit.normal,head_velocity*0.75,0.15)
			center += Vector2(hit.normal)*0.05
			remaining *= 1.0-float(hit.fraction); head_rest *= 1.0-float(hit.fraction)
			continue
		center = before.lerp(after,fraction)
		angle = lerpf(turn,end_turn,fraction)
		velocity.y += GRAVITY*remaining*fraction
		if ground:
			_land(events); return
		if faces==Vector2.ZERO: return
		var fresh := false
		for side in 3:
			if faces.dot(normals[side])<0.5: continue
			_impulse(_support(normals[side]),normals[side],Vector2.ZERO,0.86,0.0,0.10)
			if (wall_contacts & (1<<side))==0: fresh = true
			wall_contacts |= 1<<side
		_confine()
		center += faces*0.02
		if fresh: walls += 1; events.append({"type":"wall","count":walls})
		remaining *= 1.0-fraction; head_rest *= 1.0-fraction

func advance(dt: float, target: Dictionary) -> Array:
	var events: Array = []
	if not animating() or dt<=0.0 or not is_finite(dt): return events
	var elapsed := minf(dt,0.1)
	var cap: PackedVector2Array = target.get("cap",PackedVector2Array())
	var delta := Vector2.ZERO
	if cap.size()==last_cap.size() and not cap.is_empty():
		for i in cap.size(): delta += (cap[i]-last_cap[i])/cap.size()
		if delta.length()>float(target.get("extent",420))*0.8: delta = Vector2.ZERO
	head_velocity = target.get("velocity",delta/elapsed)
	if not head_velocity.is_finite(): head_velocity = Vector2.ZERO
	head_velocity = head_velocity.limit_length(pot_size.y*8.0)
	last_cap = cap.duplicate()
	var steps := maxi(1,ceili(elapsed*maxf(240.0,absf(angular_velocity)/0.025))); var h := elapsed/steps
	for i in steps:
		time += h; age += h; recoil_age += h
		var squeeze := sin(PI*clampf(recoil_age/0.10,0,1)) if active() else 0.0
		shape = Vector2(1.0+0.045*squeeze,1.0-0.055*squeeze)
		var sample := cap.duplicate()
		for j in sample.size(): sample[j] -= delta*(1.0-float(i+1)/steps)
		match state:
			"settle": _settle(h,events)
			"rise", "flight":
				if state=="rise" and velocity.y<0.0 and velocity.y+GRAVITY*h>=0.0:
					_move(-velocity.y/GRAVITY,sample,delta/steps,events)
					if state=="rise": _start_spin()
				else:
					_move(h,sample,delta/steps,events)
					if state=="rise" and velocity.y>=0.0: _start_spin()
			"spin":
				angle = spin_start+spin_turns*TAU*smoothstep(0,spin_seconds,age)
				if age>=spin_seconds: angle = wrapf(angle,-PI,PI); state = "charge"; age = 0.0
			"charge":
				glow = clampf(age/CHARGE_SECONDS,0,1)
				if age+0.000001>=CHARGE_SECONDS:
					velocity = Vector2.DOWN.rotated(angle)*sqrt(2.0*GRAVITY*base_height)*float(difficulty().launch)
					angular_velocity = signf(spin_turns)*1.8
					boosted = true; special = false; state = "flight"; age = 0.0; glow = 0.0
					events.append({"type":"launch","direction":velocity.normalized(),"angle":angle})
		if not animating(): break
	return events
