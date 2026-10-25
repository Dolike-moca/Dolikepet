extends SceneTree
const Jump = preload("res://scripts/bowl_jump.gd")
const Roaming = preload("res://scripts/roaming.gd")
var failures := 0
var checks := 0
var worst_jump_step := 0.0
var worst_walk_step := 0.0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures<12: printerr("BOWL EDGE: "+message)
func hops(area: Rect2, extent: float, fps: int, edge: int, release_at: float) -> void:
	var size := Vector2.ONE*extent
	# Physics allows transparent window margins beyond the display while the
	# head/body remain inside. Reproduce that exact standing position.
	var x: float = area.position.x-size.x*0.14 if edge<0 else area.end.x-size.x*0.86
	var origin := Vector2(x,area.end.y-size.y)
	var at := origin
	var jump = Jump.new()
	var moved_smoothly := true; var stable_anchor := true; var paused_stably := true
	for frame in fps*9:
		var pause: bool = frame>=fps*2 and frame<fps*3
		var step: Dictionary = jump.update(1.0/fps,at,size,area,frame<float(fps)*release_at,pause)
		worst_jump_step = maxf(worst_jump_step,absf(step.position.x-at.x))
		moved_smoothly = moved_smoothly and absf(step.position.x-at.x)<=size.x*0.11/fps+0.01
		stable_anchor = stable_anchor and absf(step.position.x-origin.x)<0.01
		if pause: paused_stably = paused_stably and step.position.is_equal_approx(at)
		check(step.position.y<=origin.y+0.001,"hop sank through floor")
		at = step.position
	check(moved_smoothly,"jump teleported horizontally at display edge")
	check(stable_anchor,"edge jump displaced the standing anchor")
	check(paused_stably,"paused edge jump moved")
	check(not jump.active() and at.is_equal_approx(origin),"jump did not finish at its original standing position")
func walk(area: Rect2, extent: float, fps: int, edge: int, airborne: bool) -> void:
	var size := Vector2.ONE*extent
	var x: float = area.position.x-size.x*0.14 if edge<0 else area.end.x-size.x*0.86
	var at := Vector2(x,area.end.y-size.y-(size.y*0.25 if airborne else 0.0))
	var roam = Roaming.new(); roam.configure("off")
	var goal := (area.size.x-size.x)*0.5+area.position.x
	var smooth := true; var inward := true
	for frame in fps*28:
		var before := at
		var result: Dictionary = roam.update(1.0/fps,at,size,area,0.0,false,false,false,false,goal)
		if result.move: at = result.position
		worst_walk_step = maxf(worst_walk_step,absf(at.x-before.x))
		smooth = smooth and absf(at.x-before.x)<=size.x*0.18/fps+0.001
		inward = inward and absf(at.x-goal)<=absf(before.x-goal)+0.001
	check(smooth,"approaching bowl snapped off screen edge")
	check(inward,"approach moved away from bowl")
	check(absf(at.x-goal)<0.1,"approach did not reach bowl goal")
	# Right-clicking during the first steps must brake where the cat stands.
	roam.state = "walking"; roam.speed = size.x*0.18; roam.facing = -edge
	roam.stop_for_menu(Vector2(x,area.end.y-size.y))
	at = Vector2(x,area.end.y-size.y)
	var result: Dictionary = roam.update(1.0/fps,at,size,area,0.0,false,false,false,true)
	check(absf(result.position.x-at.x)<=size.x*0.18/fps+0.001,"menu braking snapped to window bounds")
func _initialize() -> void:
	for area in [Rect2(0,0,1920,1040),Rect2(-1920,-200,1920,1080)]:
		for extent in [240.0,420.0,780.0]:
			for fps in [30,60,120]:
				for edge in [-1,1]:
					hops(area,extent,fps,edge,6.7)
					hops(area,extent,fps,edge,1.1)
					walk(area,extent,fps,edge,false)
					walk(area,extent,fps,edge,true)
	# Just inside either edge: sway may use the remaining room but must
	# never push the window outside or alter the final standing position.
	for inset in [0.0,1.0,3.0,8.0]:
		for edge in [-1,1]:
			var near_jump = Jump.new()
			var origin := Vector2(inset if edge<0 else 1500.0-inset,620)
			var at := origin
			for frame in 480:
				var step: Dictionary = near_jump.update(1.0/60,at,Vector2(420,420),Rect2(0,0,1920,1040),frame<400,false)
				check(step.position.x>=-0.001 and step.position.x<=1500.001,"near-edge sway left the desktop")
				at = step.position
			check(at.is_equal_approx(origin),"near-edge sway changed final position")
	# A window larger than the monitor has no valid horizontal clamp range.
	var jump = Jump.new(); var origin := Vector2(-60,-40); var at := origin
	for frame in 480:
		var result: Dictionary = jump.update(1.0/60,at,Vector2(780,780),Rect2(0,0,640,740),frame<400,false)
		check(is_equal_approx(result.position.x,origin.x),"oversized pet shifted horizontally")
		check(is_equal_approx(result.position.y,origin.y),"no headroom still jumped")
		at = result.position
	print("BOWL EDGE: %d checks, %d failures; max horizontal jump/walk steps %.4f / %.4f"%[checks,failures,worst_jump_step,worst_walk_step])
	quit(0 if failures==0 else 1)
