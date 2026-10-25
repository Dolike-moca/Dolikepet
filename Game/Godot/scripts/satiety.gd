extends RefCounted
const Capacity = preload("res://scripts/bowl_capacity.gd")
const DEFAULT_HOURS := 6.0
var capacity := Capacity.DEFAULT
var digestion_hours := DEFAULT_HOURS
var auto_open := false
var used := 0
var resting := false
var full_pending := false
var reminder_wait := 12.0

static func sanitize_hours(value: Variant) -> float:
	if not (value is int or value is float) or not is_finite(float(value)): return DEFAULT_HOURS
	return clampf(float(value),0.01,8760.0)

func observe(bytes: int, next_bytes: int = -1, consider_next: bool = false) -> bool:
	used = maxi(0,bytes)
	var before := resting
	if resting:
		# Strictly below half. A blocked oversized head item must not cause a
		# full/hungry loop (and repeat the satisfied speech every scan).
		if used*2<capacity and (next_bytes<0 or next_bytes<=capacity-used):
			resting = false; full_pending = false; reminder_wait = 3.0
	else:
		var no_room := consider_next and used>0 and next_bytes>=0 and next_bytes<=capacity and next_bytes>capacity-used
		if used>=capacity or no_room:
			resting = true; full_pending = true
	return before!=resting

func can_take(bytes: int) -> bool:
	return not resting and bytes>=0 and bytes<=capacity-used

func request_bowl(dt: float, visible: bool, blocked: bool) -> String:
	if resting or blocked: return ""
	if visible:
		reminder_wait = maxf(reminder_wait,12.0)
		return ""
	reminder_wait -= clampf(dt,0.0,0.1)
	if reminder_wait>0.0: return ""
	reminder_wait = 120.0
	return "open" if auto_open else "ask"

func manual_close() -> void:
	reminder_wait = 30.0
