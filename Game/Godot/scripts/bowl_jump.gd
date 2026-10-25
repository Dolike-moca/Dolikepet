extends RefCounted
## Six small hops with persistent raised hands, then mouth/arm/eye recovery.
const RAISE_SECONDS := 0.55
const HOP_START := 0.65
const HOP_PERIOD := 1.0
const HOP_COUNT := 6
const LOWER_DELAY := 0.10
const LOWER_SECONDS := 0.60
const EYE_TAIL := 0.18
var age := -1.0
var cooldown := 0.0
var speak_wait := 0.0
var base_position := Vector2.ZERO
var base_y := 0.0
var amplitude := 0.0
var sway_amplitude := 0.0
var stop_at := HOP_START+HOP_COUNT*HOP_PERIOD
var call_stop_at := stop_at
var stopping := false
var rng := RandomNumberGenerator.new()

func active() -> bool: return age >= 0.0
func cancel() -> void: age = -1.0; cooldown = 1.2

func stop_for_impact() -> void:
	if not active(): return
	stopping = true; call_stop_at = age
	var cycle := floorf(maxf(0.0,age-HOP_START)/HOP_PERIOD)
	stop_at = minf(stop_at,HOP_START+(cycle+1.0)*HOP_PERIOD)

func update(dt: float, at: Vector2, size: Vector2, area: Rect2, request: bool, paused: bool) -> Dictionary:
	var result := {"position":at,"move":false,"say":false,"weight":0.0,
		"calling":false,"time":0.0,"wave":0.0,"tilt":0.0,"knee":0.0,"paused":paused}
	var step := 0.0 if paused else clampf(dt,0.0,0.05)
	cooldown = maxf(0.0,cooldown-step); speak_wait = maxf(0.0,speak_wait-step)
	if not active() and request and cooldown==0.0 and not paused:
		age = 0.0; base_position = at; base_y = at.y
		amplitude = minf(size.y*(46.0/630.0),maxf(0.0,base_y-area.position.y))
		# Physics permits transparent margins past the desktop edge. Preserve
		# that standing anchor and limit only the added sway, never clamp the
		# entire window back inside on the first frame of the gesture.
		var side_room := maxf(0.0,minf(at.x-area.position.x,area.end.x-size.x-at.x))
		sway_amplitude = minf(size.x*(8.0/630.0),side_room)
		stop_at = HOP_START+HOP_COUNT*HOP_PERIOD; call_stop_at = stop_at; stopping = false
		if speak_wait==0.0: result.say = true; speak_wait = rng.randf_range(6.0,8.5)
	if not active(): return result
	if not request and not paused and not stopping:
		# Finish only the current hop; never snap a released cat back to the floor.
		stopping = true; call_stop_at = age
		var cycle := floorf(maxf(0.0,age-HOP_START)/HOP_PERIOD)
		stop_at = minf(stop_at,HOP_START+(cycle+1.0)*HOP_PERIOD)
	age += step
	var height := 0.0
	if age>=HOP_START and age<stop_at:
		var cycle := fposmod(age-HOP_START,HOP_PERIOD)
		var flight := clampf((cycle-0.16)/0.64,0.0,1.0)
		height = amplitude*4.0*flight*(1.0-flight)
		result.knee = 0.16*sin(PI*cycle/0.16) if cycle<0.16 else (0.12*sin(PI*(cycle-0.80)/0.20) if cycle>0.80 else 0.0)
	result.weight = smoothstep(0.0,RAISE_SECONDS,age)*(1.0-smoothstep(stop_at+LOWER_DELAY,stop_at+LOWER_DELAY+LOWER_SECONDS,age))
	result.time = maxf(0.0,age-RAISE_SECONDS)
	result.wave = sin(result.time*TAU*1.2)
	result.tilt = deg_to_rad(1.8)*result.wave*result.weight
	result.calling = age>=0.20 and age<call_stop_at
	result.position = Vector2(base_position.x+sway_amplitude*result.wave*result.weight,base_y-height)
	result.move = true
	if age>=stop_at+LOWER_DELAY+LOWER_SECONDS+EYE_TAIL:
		age = -1.0; cooldown = rng.randf_range(1.0,1.8)
		result.position = base_position; result.weight = 0.0; result.tilt = 0.0
	return result
