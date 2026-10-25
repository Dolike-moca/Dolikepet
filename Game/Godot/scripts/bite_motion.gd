extends RefCounted
## One bite: open first, bring the food in, close quickly, then settle to chew.
const MIN_DURATION := 0.85
const MAX_DURATION := 1.10
const CHEW_AT := 0.64
const BLEND := 0.20
const SETTLE := 0.34
const CONTACT := 0.49
const CLOSED := 0.60
const CARRY := Vector2(2.0, -23.0)

static func sample(age: float, duration: float) -> Dictionary:
	var p := {"biteAlpha":0.0, "biteOpen":0.0, "biteCut":0.0,
		"biteCarry":Vector2.ZERO, "biteLean":0.0, "biteNod":0.0,
		"biteChewAge":-1.0, "biteSettle":1.0}
	if age < 0.0: return p
	var u := age / duration
	p.biteChewAge = age-duration*CHEW_AT
	p.biteSettle = smoothstep(0.0,SETTLE,p.biteChewAge)
	p.biteAlpha = smoothstep(0.0,0.10,age) \
		* (1.0-smoothstep(duration*CHEW_AT,duration*CHEW_AT+BLEND,age))
	p.biteOpen = smoothstep(0.07,0.25,u) * (1.0-smoothstep(CONTACT,CLOSED,u))
	# The cut starts at jaw contact, never while the icon is still approaching.
	p.biteCut = smoothstep(CONTACT,CLOSED,u)
	var reach := smoothstep(0.17,0.46,u) * (1.0-smoothstep(0.60,0.91,u))
	var recoil := smoothstep(0.62,0.75,u) * (1.0-smoothstep(0.75,1.0,u))
	p.biteCarry = CARRY * reach + Vector2(-3.0,3.0) * recoil
	p.biteLean = 0.18 * reach - 0.025 * recoil
	p.biteNod = smoothstep(0.20,0.46,u) * (1.0-smoothstep(0.58,0.87,u)) - 0.10*recoil
	return p
