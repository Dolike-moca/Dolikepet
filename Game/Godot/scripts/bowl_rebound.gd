extends RefCounted
## Contact -> continuous ballistic fall -> one small bounce -> damped rocking.
const Impact = preload("res://scripts/bowl_impact.gd")
var age := -1.0
var origin := Vector2.ZERO
var endpoint := Vector2.ZERO
var floor_y := 0.0
var ceiling := 0.0
var pause := 0.12
var travel := 0.45
var clear_time := 0.2
var up_speed := 0.0
var side_speed := 0.0
var land_time := 0.0
var tilt := 0.0
var direction := 1.0
var bounce_height := 0.0
var bounce_time := 0.0
var level := 0.0

func active() -> bool: return age>=0.0
func cancel() -> void: age = -1.0

func start(at: Vector2, size: Vector2, cap: PackedVector2Array, area: Rect2, height: float) -> void:
	origin = at; age = 0.0; floor_y = area.end.y-size.y; ceiling = area.position.y
	level = Impact.intensity(height)
	var safe := Impact.deflection(at,size,cap,area)
	direction = -1.0 if safe.x<at.x else 1.0
	# Continue sideways throughout the flight, leaving room beyond the crown.
	var wanted := safe.x+direction*size.x*lerpf(0.65,1.65,level)
	endpoint = Vector2(clampf(wanted,area.position.x,area.end.x-size.x),floor_y)
	var ratio := clampf(absf(safe.x-at.x)/maxf(0.001,absf(endpoint.x-at.x)),0.0,1.0)
	var drop := maxf(0.0,floor_y-at.y)
	# For constant horizontal speed, H >= drop*r^2/(4*(1-r)) keeps the
	# pot above its contact height until it clears the head. Screen headroom
	# bounds the rise; never introduce an artificial hover or midair stop.
	var clearance_rise := drop*ratio*ratio/(4.0*maxf(0.001,1.0-ratio))
	var rise := maxf(size.y*lerpf(0.55,1.10,level),clearance_rise)
	rise = minf(rise,maxf(0.0,at.y-ceiling))
	up_speed = sqrt(2.0*Impact.GRAVITY*rise)
	land_time = maxf(0.001,(up_speed+sqrt(up_speed*up_speed+2.0*Impact.GRAVITY*drop))/Impact.GRAVITY)
	travel = land_time
	side_speed = (endpoint.x-origin.x)/land_time
	clear_time = land_time*ratio
	tilt = deg_to_rad(lerpf(5.0,10.0,level))*direction
	bounce_height = lerpf(2.5,6.0,level)*(size.y/176.0)
	bounce_time = sqrt(8.0*bounce_height/Impact.GRAVITY)

func update(dt: float) -> Dictionary:
	if not active(): return {}
	var old := age
	age += maxf(0.0,dt)
	var t := maxf(0.0,age-pause)
	var at := Vector2(origin.x+side_speed*t,origin.y-up_speed*t+0.5*Impact.GRAVITY*t*t)
	var angle := tilt*sin(PI*clampf(t/land_time,0.0,1.0))
	var grounded := t>=land_time
	var shape := Vector2.ONE
	if age<pause:
		var press := sin(PI*age/pause)
		shape = Vector2(1.0+0.075*press,1.0-0.10*press)
	elif t<0.20:
		var spring := sin(PI*t/0.20)*(1.0-smoothstep(0.10,0.20,t))
		shape = Vector2(1.0-0.035*spring,1.0+0.065*spring)
	var finished := false
	if grounded:
		var since := t-land_time
		at.x = endpoint.x
		at.y = floor_y
		if since<bounce_time:
			var u := since/bounce_time
			at.y -= 4.0*bounce_height*u*(1.0-u)
		else:
			var settle := since-bounce_time
			angle = deg_to_rad(2.3)*direction*sin(settle*TAU/0.24)*exp(-settle*11.0)*(1.0-smoothstep(0.30,0.48,settle))
			finished = settle>=0.48
		if finished: age = -1.0; angle = 0.0
	return {"at":at,"angle":angle,"shape":shape,"grounded":grounded,
		"landed":old-pause<land_time and grounded,"finished":finished,
		"slosh":-angle*0.7+direction*0.035*sin(t*11.0)*exp(-t*1.8)}
