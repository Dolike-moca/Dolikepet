extends SceneTree
const Roll = preload("res://scripts/bowl_roll.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL ROLL: "+label)
func polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-47,-25),Vector2(-30,-36),Vector2(30,-36),Vector2(47,-25),Vector2(42,10),Vector2(29,35),Vector2(8,40),Vector2(-8,40),Vector2(-29,35),Vector2(-42,10)])
func make(at: Vector2, incoming: Vector2, turn: float, spin: float, screen: Rect2):
	var r = Roll.new()
	r.start(at,incoming,turn,spin,Vector2(100,84),polygon(),screen)
	r.center.y = screen.end.y-r.bounds().end.y
	return r
func simulate(r, fps: int) -> Dictionary:
	var supported := true; var continuous := true; var coupled := true
	var dissipative := true; var gentle_settle := true; var passive_contact := true
	var old_angle: float = r.angle; var old_center: Vector2 = r.center
	var max_height := 0.0; var frames := 0; var steps := 0
	for frame in fps*7:
		for substep in 8:
			var old_phase: String = r.phase; var old_walls: int = r.wall_hits
			var old_spin: float = r.spin
			var old_energy: float = r.velocity.x*r.velocity.x+r.inertia*r.spin*r.spin
			r.advance(1.0/fps/8)
			var box: Rect2 = r.bounds(); box.position += r.center
			supported = supported and r.area.grow(0.1).encloses(box)
			continuous = continuous and absf(r.angle-old_angle)<0.2
			if old_phase=="slide":
				var energy: float = r.velocity.x*r.velocity.x+r.inertia*r.spin*r.spin
				passive_contact = passive_contact and energy<=old_energy+0.01
			if old_phase=="roll" and r.phase=="roll" and r.wall_hits==old_walls:
				dissipative = dissipative and absf(r.spin)<=absf(old_spin)+0.0001
				var turn: float = r.angle-old_angle
				var support: float = r.bounds(old_angle+turn*0.5).end.y
				coupled = coupled and absf(r.center.x-old_center.x-turn*support)<0.05
			if old_phase=="rock" and r.phase=="rock" and r.wall_hits==old_walls:
				gentle_settle = gentle_settle and absf(r.spin-old_spin)<=4.001/fps/8
			max_height = maxf(max_height,r.area.end.y-box.end.y)
			old_angle = r.angle; old_center = r.center; steps += 1
		frames = frame+1
		if not r.active(): break
	return {"supported":supported,"continuous":continuous,"coupled":coupled,"dissipative":dissipative,"gentle":gentle_settle,"passive":passive_contact,"hop":max_height,"seconds":frames/float(fps),"steps":steps}
func run() -> void:
	var results := []
	# A hard impact followed by a slow hop must not replay the impact energy.
	var spent = make(Vector2(400,500),Vector2(500,1600),0.12,6,Rect2(0,0,5000,800))
	spent.velocity = Vector2(30,-80); spent.spin = 0.15
	var transition_energy := 0.0; var after_energy := 0.0
	for step in 1000:
		transition_energy = spent.velocity.x*spent.velocity.x+spent.inertia*spent.spin*spent.spin
		spent.advance(1.0/960)
		if spent.phase!="hop":
			after_energy = spent.velocity.x*spent.velocity.x+spent.inertia*spent.spin*spent.spin
			break
	check(after_energy<=transition_energy+0.01,"spent landing energy relaunched rolling: %s -> %s"%[transition_energy,after_energy])
	check(is_equal_approx(spent.velocity.x,30.0) and is_equal_approx(spent.spin,0.15),"second contact replaced residual velocities")
	for fps in [30,60,120]:
		for sign in [-1.0,1.0]:
			for turn in [0.15,1.9,-2.7]:
				var r = make(Vector2(2500,500),Vector2(sign*500,1450),turn,sign*5.0,Rect2(0,0,5000,800))
				var result := simulate(r,fps)
				check(not r.active() and r.velocity==Vector2.ZERO and r.spin==0,"never came to rest")
				check(absf(wrapf(r.angle,-PI,PI))<0.001,"base not down")
				check(result.supported and result.continuous,"floor penetration/angle snap")
				check(result.coupled,"ground translation detached from rotation")
				check(result.dissipative,"rolling accelerated again near its target")
				check(result.gentle,"upright assistance accelerated abruptly")
				check(result.passive,"ground friction added kinetic energy")
				results.append([fps,sign,turn,r.travelled/TAU,result.seconds])
		# Walls can reduce the turn count, but never leave a half-sunk/spinning pot.
		for x in [55.0,345.0]:
			var r = make(Vector2(x,500),Vector2(-800 if x<100 else 800,1600),0.7,6,Rect2(0,0,400,800))
			var result := simulate(r,fps)
			check(r.wall_hits>0 and r.wall_hits<15 and not r.active(),"narrow screen fps %s x %s: phase %s angle %s spin %s walls %s"%[fps,x,r.phase,r.angle,r.spin,r.wall_hits])
			check(result.supported and result.continuous,"wall clipped or snapped")
			check(r.travelled<TAU*5.5,"wall created extra turns")
		# A nearly resting pot should not be boosted into a full multi-turn roll.
		var gentle = make(Vector2(400,500),Vector2(1,20),0.1,0.05,Rect2(0,0,1000,800))
		var slow := simulate(gentle,fps)
		check(not gentle.active() and gentle.travelled<TAU and slow.supported,"low energy was artificially boosted")
		# Late-game, fast horizontal landings and opposite spins must also
		# lose energy on contact, including repeated edge collisions.
		for speed in [-3000.0,3000.0]:
			for angular in [-12.0,12.0]:
				var fast = make(Vector2(700,500),Vector2(speed,2200),2.9,angular,Rect2(0,0,1400,800))
				var result := simulate(fast,fps)
				check(not fast.active() and result.supported,"fast landing failed to settle inside screen")
				check(result.passive and result.dissipative and result.gentle,"fast landing added sudden energy")
	# Cancelling during a roll clears motion immediately; no delayed completion.
	var interrupted = make(Vector2(400,500),Vector2(700,1200),0.8,5,Rect2(0,0,2000,800))
	interrupted.advance(0.02); interrupted.cancel(); var saved: Vector2 = interrupted.center
	interrupted.advance(1.0)
	check(not interrupted.active() and interrupted.center==saved,"cancel left ground motion")
	print("ROLL SAMPLES: "+JSON.stringify(results))
	print("BOWL ROLL: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
