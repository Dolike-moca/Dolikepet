extends SceneTree
const Flight = preload("res://scripts/juggle_flight.gd")
const Game = preload("res://scripts/juggle_challenge.gd")
const Motion = preload("res://scripts/juggle_motion.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("JUGGLE: "+label)
func flight():
	var f = Flight.new(); f.rng.seed = 42
	f.next_special_override = 0
	f.start(Vector2(400,600),Vector2(80,70),PackedVector2Array([Vector2(-40,-35),Vector2(40,-35),Vector2(40,35),Vector2(-40,35)]),Rect2(0,0,1000,1000))
	return f
func run() -> void:
	var game = Game.new(); var total := 0
	for i in range(1,41):
		var walls := i%4; var high := i%2==0
		var base := maxi(1,walls*walls)*(7 if high else 1)
		total += base+(i if i%10==0 else 0)
		game.hit(i,walls,high)
		check(game.total==total and game.base_points==base,"independent wall/boost score at "+str(i))
		check(game.bonus==(i if i%10==0 else 0),"bonus was multiplied")
	game.hit(41,2,true)
	check(game.base_points==28 and game.snapshot(41.8).blessing_age>0.7,"boost award/blessing order")
	game.finish("floor",42); var record: int = game.best
	check(not game.active() and game.snapshot(46.9).shown and not game.snapshot(47.0).shown,"floor hide not five seconds")
	game.finish("again",48); check(game.ended_at==42,"duplicate end extended hide")
	game.hit(49,0,false); check(game.total==1 and game.streak==1 and game.best==record,"next game did not reset")
	var f = flight(); var count := 0
	for i in 2000:
		f.center = Vector2(400,600); f.angle = 0; f.hits = 0; f._bounce()
		check(f.height_ratio>=1.0 and f.height_ratio<=3.0,"random height outside 1–3")
		if f.special: count += 1
	check(count>55 and count<110,"opening 4 percent special distribution: "+str(count))
	count = 0
	for i in 2000:
		f.center = Vector2(400,600); f.angle = 0; f.hits = 59; f._bounce()
		if f.special: count += 1
	check(count>700 and count<830,"late 38 percent special distribution: "+str(count))
	var cap := PackedVector2Array([Vector2(330,650),Vector2(360,620),Vector2(390,650)])
	for fps in [30,60,120]:
		f = flight(); f.state = "flight"; f.center = Vector2(360,350); f.velocity = Vector2(0,5000)
		f.boosted = true; f.walls = 2; f.armed = true; f.separated = true
		var hits := 0
		for frame in fps/3:
			for e in f.advance(1.0/fps,{"cap":cap,"extent":420}):
				if e.type=="head":
					hits += 1; check(e.boosted and e.walls==2,"contact lost boost/walls")
		check(hits==1,"tunnel/duplicate head contact at fps "+str(fps))
		check(not f.boosted and f.walls==0,"next flight inherited boost/walls")
		# All three screen edges reflect; a corner is one collision event.
		f = flight(); f.state = "flight"; f.center = Vector2(950,500); f.velocity = Vector2(3000,-100)
		f.boosted = true
		var wall_events := f.advance(0.05,{})
		check(f.velocity.x<0 and f.walls==1 and f.boosted,"right wall reflection")
		f.center = Vector2(50,500); f.velocity = Vector2(-3000,-100)
		f.advance(0.05,{}); check(f.velocity.x>0 and f.walls==2,"left wall reflection")
		f.center = Vector2(500,40); f.velocity = Vector2(0,-3000)
		f.advance(0.05,{}); check(f.velocity.y>0 and f.walls==3,"top reflection")
		# Floor wins if the crown shares the floor line.
		f.center = Vector2(500,950); f.velocity = Vector2(0,3000); f.armed = true
		var ended := false; hits = 0
		for e in f.advance(0.05,{"cap":PackedVector2Array([Vector2(400,1000),Vector2(600,1000)]),"extent":420}):
			if e.type=="floor": ended = true
			if e.type=="head": hits += 1
		check(ended and hits==0 and not f.active(),"floor did not end before tied head contact")
	# Deterministic special: fixed position, 1–5 turns, exactly 0.8 s charge,
	# locked bottom direction, stage-dependent speed, gravity after launch.
	f = flight(); f.next_special_override = 1; f._bounce()
	var spin_at := Vector2.INF; var charge_at := -1.0; var launch := {}
	var locked := 0.0
	for frame in 2000:
		var previous: String = f.state
		var events: Array = f.advance(1.0/240.0,{})
		if f.state=="spin":
			if not spin_at.is_finite(): spin_at = f.center
			check(f.center.distance_to(spin_at)<0.001,"spin drifted")
			var box: Rect2 = f.bounds(); box.position += f.center
			check(f.area.grow(0.1).encloses(box),"spin clipped at screen edge")
		if f.state=="charge":
			if charge_at<0: charge_at = f.time; locked = f.angle
			check(is_equal_approx(f.angle,locked),"charge changed aim")
		for e in events:
			if e.type=="launch": launch = e
		if not launch.is_empty(): break
	check(not launch.is_empty() and absf(f.time-charge_at-0.8)<0.005,"charge duration")
	check(absf(f.spin_turns)>=1 and absf(f.spin_turns)<=5,"spin turn count")
	check(launch.get("direction",Vector2.ZERO).distance_to(Vector2.DOWN.rotated(locked))<0.001,"launch not along pot bottom")
	check(absf(f.velocity.length()-sqrt(2*Flight.GRAVITY*f.base_height)*float(f.difficulty().launch))<0.01,"launch speed differs from difficulty")
	var vy: float = f.velocity.y; f.advance(1.0/240.0,{})
	check(absf(f.velocity.y-vy-Flight.GRAVITY/240.0)<0.01,"launched pot ignored gravity")
	f.next_special_override = 1; f._bounce(); check(f.special,"artificial cooldown prohibited consecutive specials")
	physics_c()
	var motion = Motion.new(); var pose := {"dragHeld":true,"dragFace":1.0,"dragHang":1.0,"dragTilt":0.0,"dragStretch":0.1,"dragBend":0.0}
	var p := pose
	for i in 90: p = motion.prepare(pose,1.0/60,true,true,2.0 if i<45 else -2.0)
	check(p.dizzyAlpha==1.0 and p.dragFace==0.0 and p.juggleWeight==1.0,"held pose retained squeezed eyes")
	check(absf(p.dragTilt)<=0.45 and absf(p.juggleLimbs)<=0.25,"ragdoll unstable")
	for i in 60: p = motion.prepare(pose,1.0/60,false,false,0.0)
	check(p==pose,"ragdoll did not recover to original pose")
	print("JUGGLE: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)

func physics_c() -> void:
	var f = flight(); var prior := f.difficulty()
	for i in range(2,100):
		f.hits = i; var level: Dictionary = f.difficulty()
		check(level.chance>=prior.chance and level.height>=prior.height and level.launch>=prior.launch,"difficulty regressed")
		check(level.chance<=0.38 and level.height<=1.85 and level.launch<=3.0,"difficulty unbounded")
		prior = level
	# Same deterministic contact and geometry; only the real head motion differs.
	var outputs := []
	for head in [Vector2.ZERO,Vector2(0,-300),Vector2(350,0),Vector2(-350,0)]:
		f = flight(); f.rng.seed = 25; f.hits = 0; f.next_special_override = 0
		f.center = Vector2(400,600); f.velocity = Vector2(0,450); f.angular_velocity = 0; f.angle = 0.7
		f.head_velocity = head; f._bounce(f.center+Vector2(0,35),Vector2.UP)
		outputs.append(f.velocity)
		check(is_equal_approx(f.angle,0.7),"head impact snapped orientation")
	check(outputs[1].y<outputs[0].y-150,"upward head did not transfer momentum")
	check(outputs[2].x>outputs[0].x+30 and outputs[3].x<outputs[0].x-30,"sideways head did not transfer momentum")
	var spins := []
	for x in [-30.0,0.0,30.0]:
		f = flight(); f.rng.seed = 25; f.hits = 0; f.next_special_override = 0
		f.velocity = Vector2(0,450); f.angular_velocity = 0; f.head_velocity = Vector2.ZERO
		f._bounce(f.center+Vector2(x,35),Vector2.UP); spins.append(f.angular_velocity)
	check(spins[0]>0.2 and absf(spins[1])<0.001 and spins[2]<-0.2,"off-centre torque wrong direction")
	for fps in [30,60,120]:
		# Until the entire pot separates, continue passive contact resolution
		# without adding another score or another powered bounce.
		for turn in [0.0,0.5,1.2,2.5]:
			for spin in [-10.0,0.0,10.0]:
				f = flight(); f.state = "flight"; f.center = Vector2(400,350)
				f.angle = turn; f.angular_velocity = spin; f.velocity = Vector2(0,2500)
				f.armed = true; f.separated = true
				var contacts := 0; var penetration := 0.0
				for frame in fps:
					f.next_special_override = 0
					for event in f.advance(1.0/fps,{"cap":PackedVector2Array([Vector2(0,650),Vector2(1000,650)])}):
						if event.type=="head": contacts += 1
					if contacts>0:
						penetration = maxf(penetration,f.center.y+f.bounds().end.y-650)
						if f.separated: break
				check(contacts==1 and penetration<1.25,"spinning secondary contact tunneled/re-scored at fps "+str(fps))
		# No arbitrary speed/rotation changes in a free ballistic flight.
		f = flight(); f.area = Rect2(-10000,-10000,20000,20000)
		f.state = "flight"; f.center = Vector2(0,0); f.velocity = Vector2(120,-250); f.angle = 0.7; f.angular_velocity = 3.0
		for frame in fps/2: f.advance(1.0/fps,{})
		check(f.center.distance_to(Vector2(60,87.5))<0.02 and f.velocity.distance_to(Vector2(120,600))<0.02,"ballistic parabola varies with fps")
		check(absf(f.angle-2.2)<0.001 and absf(f.angular_velocity-3)<0.001,"free spin was forced upright")
		# A spinning, fast pot remains inside all three walls without counting
		# the same persisting contact repeatedly. Ground ends once, then rolls.
		for turn in [0.4,1.8,3.0,-2.0]:
			f = flight(); f.state = "flight"; f.center = Vector2(700,200)
			f.angle = turn; f.angular_velocity = 9.0; f.velocity = Vector2(1800,-700)
			var floors := 0; var rest := 0; var head_hits := 0; var contained := true
			var landed_at := -1.0; var changed := false; var hop := false; var end_x := 0.0
			var floor_angle := 0.0; var previous: float = f.angle; var continuous := true
			for frame in fps*7:
				for event in f.advance(1.0/fps,{}):
					if event.type=="floor": floors += 1; landed_at = frame/float(fps); floor_angle = f.angle; end_x = f.center.x
					if event.type=="rest": rest += 1
					if event.type=="head": head_hits += 1
				var box: Rect2 = f.bounds(); box.position += f.center
				contained = contained and f.area.grow(0.3).encloses(box)
				continuous = continuous and absf(wrapf(f.angle-previous,-PI,PI))<0.75
				previous = f.angle
				if landed_at>=0 and f.state=="settle":
					changed = changed or absf(f.center.x-end_x)>0.5 or absf(wrapf(f.angle-floor_angle,-PI,PI))>0.05
					hop = hop or box.end.y<f.area.end.y-0.5
				if not f.animating(): break
			check(contained,"rotating pot escaped screen at fps "+str(fps))
			check(floors==1 and rest==1 and head_hits==0 and not f.active(),"floor/settle scored or ended twice")
			check(hop and changed and continuous,"floor lacked continuous hop/rolling fps %s turn %s: %s %s %s"%[fps,turn,hop,changed,continuous])
			check(absf(f.angle)<0.001 and f.velocity.length()<0.001 and f.angular_velocity==0,"pot did not come to upright rest")
		# Only rotation (no centre translation) can strike the crown.
		var poly := PackedVector2Array([Vector2(-40,-10),Vector2(40,-10),Vector2(40,10),Vector2(-40,10)])
		var spun := PackedVector2Array()
		for point in poly: spun.append(point.rotated(0.2))
		var hit: Dictionary = Flight.sweep(Vector2.ZERO,Vector2.ZERO,poly,PackedVector2Array([Vector2(20,14),Vector2(45,14)]),Vector2.ZERO,spun)
		check(not hit.is_empty(),"rotating edge missed stationary crown")
	# Conservative wall impulse (no gravity step) cannot create kinetic energy.
	f = flight(); f.velocity = Vector2(1300,-140); f.angular_velocity = 5
	var energy: float = f.velocity.length_squared()+f._inertia()*f.angular_velocity*f.angular_velocity
	f._impulse(f.center+Vector2(40,12),Vector2.LEFT,Vector2.ZERO,0.86)
	check(f.velocity.length_squared()+f._inertia()*f.angular_velocity*f.angular_velocity<=energy+0.01,"static wall created energy")
	f.hits = 100; f.start(Vector2(400,600),f.pot_size,f.outline,f.area)
	check(f.hits==1 and is_equal_approx(float(f.difficulty().chance),0.04),"new round inherited difficulty")
