extends RefCounted
## Owns only the new interaction; approved arm, drag, impact and smile rigs stay shared.
var state := "idle"
var age := 0.0
var weight := 0.0
var lower_from := 0.0
var target := Rect2()
var user_dragged := false
var speak_wait := 0.0
func active() -> bool: return state!="idle"
func request() -> void:
	if active(): return
	state = "pending"; age = 0.0; weight = 0.0; user_dragged = false
func begin(cap: Rect2) -> void:
	target = cap; state = "calling"; age = 0.0; speak_wait = 0.0
func grabbed_cat() -> void:
	if state=="calling": user_dragged = true
func finish(rescued := false) -> void:
	if state=="idle": return
	state = "rescue_wait" if rescued else "recover"
	lower_from = weight; age = 0.0
func cancel() -> void:
	state = "idle"; age = 0.0; weight = 0.0; user_dragged = false
func update(dt: float, cap: Rect2, pot: Rect2, released: bool, on_floor: bool, held: bool, stable: bool) -> Dictionary:
	var result := {"weight":weight,"calling":false,"time":age,"wave":0.0,"tilt":0.0,"say":false,"thanks":false}
	if state in ["idle","pending"]: return result
	age += clampf(dt,0.0,0.05)
	if state=="calling":
		weight = smoothstep(0.0,0.55,age) if not held else 0.0
		result.calling = not held
		speak_wait -= dt
		if speak_wait<=0.0 and not held: result.say = true; speak_wait = 2.6
		# Judge only once the whole pot has passed the original crown. A click,
		# a native menu hold, or grabbing the pot cannot earn a rescue response.
		if released and (pot.position.y>target.end.y or on_floor):
			var clear := cap.end.x<pot.position.x-4.0 or cap.position.x>pot.end.x+4.0
			var moved := absf(cap.get_center().x-target.get_center().x)>maxf(8.0,target.size.x*0.2)
			finish(user_dragged and clear and moved)
			result.calling = false
	elif state in ["recover","rescue_wait"]:
		weight = lower_from*(1.0-smoothstep(0.0,0.45,age))
		if age>=0.65 and not held:
			if state=="recover": cancel()
			elif stable:
				state = "thanking"; age = 0.0; result.thanks = true
	elif state=="thanking":
		weight = 0.0
		if age>=2.5: cancel()
	result.weight = weight; result.time = age
	result.wave = 0.65*sin(age*TAU*1.2)+0.35*sin(age*TAU*1.87)
	result.tilt = deg_to_rad(1.2)*result.wave*weight
	return result
