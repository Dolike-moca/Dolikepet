extends SceneTree
const Hit = preload("res://scripts/bowl_impact.gd")
const Reaction = preload("res://scripts/bowl_hit_reaction.gd")
const Landing = preload("res://scripts/landing_motion.gd")
const Eyes = preload("res://scripts/drag_eye_transition.gd")
const Rebound = preload("res://scripts/bowl_rebound.gd")
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr(text)
func _initialize() -> void:
	for extent in [240.0,420.0,840.0]:
		check(Hit.classify(extent*0.01,30.0,extent)=="","gentle placement")
		check(Hit.classify(extent*0.18,sqrt(3400.0*extent*0.18),extent)=="light","scaled low drop")
		check(Hit.classify(extent*0.75,sqrt(3400.0*extent*0.75),extent)=="hard","scaled high drop")
		check(Hit.classify(extent,0.0,extent)=="","stationary pot")
	var cap := PackedVector2Array([Vector2(100,200),Vector2(200,150),Vector2(300,200)])
	var feet := PackedVector2Array([Vector2.ZERO])
	check(not Hit.sweep(Vector2(200,0),Vector2(200,400),feet,cap).is_empty(),"fast drop tunneled")
	check(Hit.sweep(Vector2(40,0),Vector2(40,400),feet,cap).is_empty(),"transparent side hit")
	check(Hit.sweep(Vector2(200,400),Vector2(200,0),feet,cap).is_empty(),"upward hit")
	check(Hit.sweep(Vector2(200,220),Vector2(200,400),feet,cap).is_empty(),"already below crown hit")
	for offset in [Vector2.ZERO,Vector2(-1920,-200)]:
		var shifted := PackedVector2Array()
		for point in cap: shifted.append(point+offset)
		var away := Hit.deflection(Vector2(130,10)+offset,Vector2(150,130),shifted,Rect2(offset,Vector2(600,600)))
		check(away.x>=offset.x and away.x+150<=offset.x+600,"deflection escaped desktop")
		check(away.x+150<=100+offset.x or away.x>=300+offset.x,"deflection still over crown")
	for fps in [30,60,120]:
		var reaction = Reaction.new(); var eyes = Eyes.new()
		check(reaction.start("light"),"light start")
		var saw_closed := false; var saw_half := false
		for i in fps:
			reaction.update(1.0/fps,true,false,false)
			var p := reaction.prepare({"eyeNear":1.0,"eyeFar":1.0,"headZ":0.0,"headY":0.0})
			p = eyes.update(p,1.0/fps)
			saw_closed = saw_closed or p.eyeNear==0.0
			saw_half = saw_half or (p.eyeNear>0.0 and p.eyeNear<1.0)
			check(not p.get("dragHang",false),"light knock became actual hanging")
		check(saw_closed and saw_half and not reaction.active(),"eye recovery or duration failed")
	var high = Reaction.new(); high.start("hard")
	check(not high.update(0.05,false,false,false) and high.waiting_for_floor(),"airborne cat sat in air")
	check(high.update(0.05,true,false,false),"hard knock did not request landing")
	check(not high.start("hard"),"repeated knock reset animation")
	var landing = Landing.new(); landing.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED})
	var direct = Landing.new()
	direct.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED,"immediate_dizzy":true})
	check(direct.pose().dizzyAlpha==1.0 and direct.pose().dizzyEyeOverride,"summon hit did not enter dizziness on first frame")
	check(landing.pose().dizzyAlpha==0.0 and not landing.pose().dizzyEyeOverride,"ordinary high fall entrance changed")
	var airborne = Reaction.new(); airborne.start("hard",3.0,true)
	var instant: Dictionary = airborne.prepare({"eyeNear":0.0,"eyeFar":0.0,"headZ":0.0,"headY":0.0,"bowlReach":1.0})
	check(instant.dizzyAlpha==1.0 and instant.dragFace==0.0,"direct hit showed drag face before ground")
	var elastic = Rebound.new()
	elastic.start(Vector2(300,100),Vector2(150,130),cap,Rect2(0,0,1200,800),1.2)
	var pressed: Dictionary = elastic.update(0.06)
	check(pressed.shape.y<0.92 and pressed.shape.x>1.05,"contact has no squash")
	var springing: Dictionary = elastic.update(0.13)
	check(springing.shape.y>1.02 and springing.at.y<elastic.origin.y-10.0,"pot did not spring upward after compression")
	var old_age: float = high.age
	high.update(1.0,true,true,true)
	check(high.age==old_age,"pause advanced reaction")
	for i in 190:
		high.update(1.0/60,true,landing.active(),false)
		landing.update(1.0/60)
	check(not high.active() and not landing.active(),"hard knock never recovered")
	var previous_distance := -1.0
	var previous_duration := 0.0
	for height in [0.04,0.15,0.65,0.9,1.3,1.8,3.0]:
		var motion = Rebound.new()
		motion.start(Vector2(300,100),Vector2(150,130),PackedVector2Array([Vector2(280,240),Vector2(360,230),Vector2(440,240)]),Rect2(0,0,1200,800),height)
		var distance: float = absf(motion.endpoint.x-motion.origin.x)
		var seconds := Hit.dizzy_seconds(height)
		check(distance>=previous_distance,"higher drop rebounded less")
		check(seconds>=previous_duration and seconds<=6.0,"dizziness not monotonic/bounded")
		previous_distance = distance; previous_duration = seconds
		var long_landing = Landing.new()
		long_landing.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED,"dizzy_seconds":seconds})
		long_landing.age = 0.25
		var entry: Dictionary = long_landing.pose()
		check(is_equal_approx(entry.dizzyAlpha,0.5),"extended dizziness slowed entrance")
		long_landing.age = seconds-0.085
		check(is_equal_approx(long_landing.pose().dizzyOpenness,0.5),"extended dizziness slowed eye recovery")
		long_landing.age = seconds-0.01; long_landing.update(0.02)
		check(not long_landing.active(),"extended dizziness outlived deadline")
	for fps in [30,60,120]:
		for offset in [Vector2.ZERO,Vector2(-1200,-200)]:
			var motion = Rebound.new()
			var head := PackedVector2Array([Vector2(280,240)+offset,Vector2(360,230)+offset,Vector2(440,240)+offset])
			motion.start(Vector2(300,100)+offset,Vector2(150,130),head,Rect2(offset,Vector2(900,800)),1.8)
			var landed := 0; var took_off_again := false; var land_seen := false
			var last: Vector2 = motion.origin
			for i in fps*3:
				if not motion.active(): break
				var result: Dictionary = motion.update(1.0/fps)
				check(result.at.x>=offset.x and result.at.x<=offset.x+750,"rebound escaped horizontal screen bounds")
				check(result.at.y>=offset.y and result.at.y<=offset.y+670,"rebound escaped vertical screen bounds")
				check(result.at.distance_to(last)<85.0,"rebound position jumped")
				if result.landed: landed += 1; land_seen = true
				elif land_seen and result.at.y<offset.y+669.0: took_off_again = true
				last = result.at
			check(landed==1 and took_off_again and not motion.active(),"missing single small landing bounce / finish")
	# The same contact and trajectory must resolve identically at 30/60/120 FPS.
	var paths: Array = []
	for fps in [30,60,120]:
		var motion = Rebound.new(); motion.start(Vector2(300,100),Vector2(150,130),cap,Rect2(0,0,1200,800),1.2)
		var result := {}
		for i in int(fps*0.5): result = motion.update(1.0/fps)
		paths.append(result.at)
	check(paths[0].distance_to(paths[1])<0.01 and paths[1].distance_to(paths[2])<0.01,"rebound depends on frame rate")
	for scale in [0.6,1.0,2.0]:
		for head_x in [10.0,800.0]:
			var motion = Rebound.new()
			var edge_cap := PackedVector2Array([Vector2(head_x,230)*scale,Vector2(head_x+120,200)*scale,Vector2(head_x+240,230)*scale])
			var area := Rect2(Vector2(-1200,-200)*scale,Vector2(2300,1100)*scale)
			motion.start(Vector2(head_x+45,-200)*scale,Vector2(150,130)*scale,edge_cap,area,1.8)
			for i in 180:
				if not motion.active(): break
				var result: Dictionary = motion.update(1.0/60)
				check(area.encloses(Rect2(result.at,Vector2(150,130)*scale)),"ceiling/edge rebound escaped usable monitor")
			check(not motion.active(),"edge rebound never settled")
	for fps in [30,60,120]:
		var repeated = Landing.new()
		repeated.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED})
		for i in fps*2: repeated.update(1.0/fps)
		var before: float = repeated.age
		repeated.extend_dizziness(6.0)
		check(repeated.age==before and is_equal_approx(repeated.dizzy_remaining(),7.0),"repeated hit reset clock")
		for i in 12: repeated.extend_dizziness(6.0)
		check(is_equal_approx(repeated.dizzy_remaining(),30.0),"remaining duration cap")
		for i in fps*29: repeated.update(1.0/fps)
		check(repeated.active() and repeated.pose().dizzyAlpha>0.99,"long hold lost dizziness")
		for i in fps*2: repeated.update(1.0/fps)
		check(not repeated.active(),"stacked dizziness never recovered")
	# A physical arc keeps horizontal velocity until landing and constant gravity.
	for height in [0.15,0.9,1.8]:
		var arc = Rebound.new()
		arc.start(Vector2(600,320),Vector2(204,176),PackedVector2Array([Vector2(560,500),Vector2(700,490),Vector2(840,500)]),Rect2(0,0,1600,1000),height)
		check(arc.up_speed*arc.up_speed/(2.0*Hit.GRAVITY)>=176*0.55,"new arc did not rise visibly higher")
		var samples: Array[Vector2] = []
		for time in [0.10,0.20,0.30]:
			arc.age = arc.pause+time
			samples.append(arc.update(0.0).at)
		check(absf(samples[2].x-2.0*samples[1].x+samples[0].x)<0.01,"sideways motion still eases in midair")
		check(absf(samples[2].y-2.0*samples[1].y+samples[0].y-Hit.GRAVITY*0.01)<0.01,"vertical path is not ballistic")
		arc.age = arc.pause+arc.land_time-0.02
		var before_ground: Vector2 = arc.update(0.0).at
		check(absf(before_ground.x-arc.endpoint.x)>0.1,"horizontal motion stopped before landing")
		check(arc.clear_time<=2.0*arc.up_speed/Hit.GRAVITY+0.001,"arc descends through crown before clearing it")
	var recovering = Landing.new()
	recovering.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED})
	recovering.age = 2.92
	var prior: Dictionary = recovering.pose()
	recovering.extend_dizziness(3.0)
	check(is_equal_approx(recovering.pose().dizzyAlpha,prior.dizzyAlpha) and is_equal_approx(recovering.pose().dizzyOpenness,prior.dizzyOpenness),"late rehit snapped recovery face")
	recovering.update(0.1); recovering.update(0.1)
	check(recovering.pose().dizzyAlpha>0.99 and recovering.pose().dizzyOpenness<0.01,"late rehit did not return to dizzy face")
	for fps in [30,60,120]:
		var dip = Landing.new()
		dip.start({"height":Landing.HIGH_HEIGHT,"speed":Landing.HIGH_SPEED})
		for i in fps*2: dip.update(1.0/fps)
		var before_age: float = dip.age
		var before_spin: float = dip.pose().dizzyAngle
		dip.extend_dizziness(3.0)
		check(dip.age==before_age and dip.pose().dizzyAngle==before_spin,"rehit restarted dizziness phase")
		check(dip.rehit.amount==0.0,"rehit snapped the body on contact")
		var peak := 0.0
		for i in fps:
			dip.update(1.0/fps)
			peak = maxf(peak,dip.rehit.amount)
		check(peak>0.9 and peak<1.16,"rehit dip missing or excessive")
		check(dip.rehit.amount<0.0001,"rehit did not settle within one second")
		dip.extend_dizziness(3.0); dip.update(0.05)
		var before_dip: float = dip.rehit.amount
		dip.extend_dizziness(3.0)
		check(dip.rehit.amount==before_dip,"rapid rehit reset body position")
		for i in 20: dip.extend_dizziness(3.0); dip.update(1.0/fps)
		check(dip.rehit.amount<=1.15 and dip.dizzy_remaining()<=30.0,"rapid hits exceeded visual/time bounds")
		var frozen: float = dip.rehit.amount
		dip.update(0.1,true)
		check(dip.rehit.amount==frozen,"paused dip kept advancing")
		dip.cancel()
		check(dip.pose().dizzyRehit==0.0 and dip.rehit.velocity==0.0,"regrab left a residual dip")
	print("Bowl impact: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
