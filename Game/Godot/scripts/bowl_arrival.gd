extends RefCounted
## Reveal inside the selected screen, then release once. Never retarget a drop.
const REVEAL := 0.5
const HOLD := 0.6
var age := -1.0
func active() -> bool: return age>=0.0
func start() -> void: age = 0.0
func cancel() -> void: age = -1.0
func update(dt: float, height: float) -> Dictionary:
	var result := {"offset":Vector2.ZERO,"release":false}
	if not active(): return result
	age += clampf(dt,0.0,0.05)
	result.offset.y = -height*(1.0-smoothstep(0.0,REVEAL,age))
	if age>=REVEAL:
		result.offset.x = 1.3*sin((age-REVEAL)*TAU*3.0)*sin(PI*clampf((age-REVEAL)/HOLD,0.0,1.0))
	if age>=REVEAL+HOLD:
		cancel(); result.offset = Vector2.ZERO; result.release = true
	return result
