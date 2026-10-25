extends RefCounted
## Post-game landing: residual hop, dissipative rolling, then a quiet rock.
## Screen-space clockwise rotation rolls to the right. The actual convex
## outline determines support height, so handles and feet never sink below it.
const GRAVITY := 1700.0
var phase := "idle"
var center := Vector2.ZERO
var velocity := Vector2.ZERO
var angle := 0.0
var spin := 0.0
var area := Rect2()
var size := Vector2.ZERO
var outline := PackedVector2Array()
var inertia := 1.0
var target := 0.0
var direction := 1.0
var roll_speed := 0.0
var roll_duration := 0.0
var roll_age := 0.0
var slide_age := 0.0
var travelled := 0.0
var wall_hits := 0
var wall_contacts := 0
var elapsed := 0.0

func active() -> bool: return phase!="idle"
func cancel() -> void: phase = "idle"; velocity = Vector2.ZERO; spin = 0.0

func bounds(turn := NAN) -> Rect2:
	if is_nan(turn): turn = angle
	var box := Rect2(outline[0].rotated(turn),Vector2.ZERO)
	for point in outline: box = box.expand(point.rotated(turn))
	return box

func start(at: Vector2, incoming: Vector2, turn: float, angular: float,
		pot_size: Vector2, polygon: PackedVector2Array, screen: Rect2, contact := {}) -> void:
	center = at; angle = turn; size = pot_size; outline = polygon; area = screen
	inertia = maxf(1.0,size.length_squared()*0.14)
	phase = "hop"; elapsed = 0.0; travelled = 0.0; wall_hits = 0; wall_contacts = 0
	# The first impact may make a small hop. Its vertical energy is NOT saved
	# for a later launch: subsequent rolling only uses the remaining motion.
	var impact_energy := incoming.length_squared()+inertia*angular*angular
	spin = float(contact.get("spin",angular))*0.85
	var reacted: Vector2 = contact.get("velocity",incoming)
	velocity.x = reacted.x*0.85
	var tiny_hop := sqrt(2.0*GRAVITY*size.y*0.025)*clampf(sqrt(impact_energy)/(size.y*3.0),0,1)
	var hop := clampf(absf(incoming.y)*0.20,tiny_hop,sqrt(2.0*GRAVITY*size.y*0.10))
	velocity.y = -hop
	_confine()

func _confine() -> void:
	var box := bounds()
	center.x = clampf(center.x,area.position.x-box.position.x,area.end.x-box.end.x)
	center.y = minf(center.y,area.end.y-box.end.y)

func _begin_roll() -> void:
	# Friction brings linear and angular motion together over time rather
	# than abruptly replacing either velocity at the end of the hop.
	phase = "slide"; slide_age = 0.0; velocity.y = 0.0

func _plan() -> void:
	phase = "roll"
	direction = signf(spin)
	if direction==0.0: _begin_rock(); return
	# Brake toward an upright pose inside the residual stopping distance.
	# Never add a minimum number of turns or boost speed to reach that pose.
	var budget := absf(spin)*1.25
	target = direction*floorf((direction*angle+budget)/TAU)*TAU
	var distance := direction*(target-angle)
	if distance<0.15 or absf(spin)<0.5: _begin_rock(); return
	var speed := absf(spin)
	roll_speed = speed; roll_duration = 3.0*distance/speed; roll_age = 0.0

func _begin_rock() -> void:
	phase = "rock"; target = roundf(angle/TAU)*TAU
	# Preserve velocity through the transition. A bounded, heavily damped
	# restoring torque settles a low-energy tilted pot without a fast flip.

func _wall() -> bool:
	var box := bounds()
	if center.x+box.position.x>area.position.x+3.0: wall_contacts &= ~1
	if center.x+box.end.x<area.end.x-3.0: wall_contacts &= ~2
	var left := center.x+box.position.x<=area.position.x+0.001
	var right := center.x+box.end.x>=area.end.x-0.001
	if not ((left and velocity.x<0.0) or (right and velocity.x>0.0)): return false
	_confine()
	var contact := 1 if left else 2
	if (wall_contacts & contact)==0: wall_hits += 1
	wall_contacts |= contact
	if phase=="roll":
		spin *= -0.88; velocity.x *= -0.88
		_plan()
	elif phase in ["hop","slide"]:
		velocity.x *= -0.55; spin *= -0.55
	else:
		# A near-rest pot wedged against a wall must be able to rock inward.
		# Project its support position instead of flipping a tiny spin forever.
		velocity.x = 0.0
	return true

func advance(h: float) -> void:
	if not active(): return
	elapsed += h
	var old_angle := angle
	match phase:
		"hop":
			center += velocity*h+Vector2(0,0.5*GRAVITY*h*h)
			velocity.y += GRAVITY*h; angle += spin*h
			_wall()
			if center.y+bounds().end.y>=area.end.y:
				center.y = area.end.y-bounds().end.y
				_begin_roll()
		"slide":
			var radius := maxf(4.0,bounds().end.y)
			var old_velocity := velocity.x; var old_spin := spin
			var slip := velocity.x-radius*spin
			# A gradual inelastic contact dissipates kinetic energy at every
			# substep, including when translation and rotation oppose each other.
			var impulse := -slip/(1.0+radius*radius/inertia)*(1.0-exp(-h/0.06))
			velocity.x += impulse; spin -= impulse*radius/inertia
			velocity.x *= exp(-0.45*h); spin *= exp(-0.45*h)
			center.x += (old_velocity+velocity.x)*0.5*h
			angle += (old_spin+spin)*0.5*h
			center.y = area.end.y-bounds().end.y
			var hit_wall := _wall()
			slide_age += h
			if not hit_wall and slide_age>=0.12 and absf(velocity.x-maxf(4.0,bounds().end.y)*spin)<size.x*0.025:
				_plan()
		"roll":
			# Analytic deceleration: speed falls continuously to zero, and its
			# slope also reaches zero. No integration remainder can restart it.
			var before := maxf(0.0,1.0-roll_age/roll_duration)
			roll_age = minf(roll_duration,roll_age+h)
			var after := maxf(0.0,1.0-roll_age/roll_duration)
			var step := roll_speed*roll_duration*(pow(before,3)-pow(after,3))/3.0
			var next_angle := angle+direction*step
			var support := maxf(4.0,bounds(angle+direction*step*0.5).end.y)
			center.x += direction*step*support
			angle = next_angle; spin = direction*roll_speed*after*after
			velocity = Vector2(spin*support,0)
			center.y = area.end.y-bounds().end.y
			var hit_wall := _wall()
			if not hit_wall and roll_age>=roll_duration: _begin_rock()
		"rock":
			# Only the final low-speed fraction uses an upright restoring force.
			# Keep the support-point travel coupled during the small final wobble.
			var previous_spin := spin
			var acceleration := clampf((target-angle)*8.0-spin*6.0,-4.0,4.0)
			spin += acceleration*h
			var step := (previous_spin+spin)*0.5*h
			var support := maxf(4.0,bounds(angle+step*0.5).end.y)
			center.x += step*support; angle += step
			velocity = Vector2(spin*support,0)
			center.y = area.end.y-bounds().end.y
			_wall()
			if absf(target-angle)<0.002 and absf(spin)<0.02:
				angle = target; spin = 0.0; velocity = Vector2.ZERO; phase = "idle"
				center.y = area.end.y-bounds().end.y
	travelled += absf(angle-old_angle)
	_confine()
