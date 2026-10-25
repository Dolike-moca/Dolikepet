extends SceneTree
const Summon = preload("res://scripts/bowl_summon.gd")
const Arrival = preload("res://scripts/bowl_arrival.gd")
const Reach = preload("res://scripts/bowl_reach_pose.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr(message)
func _initialize() -> void:
	var cap := Rect2(200,400,160,70)
	var pot := Rect2(220,0,130,120)
	for fps in [30,60,120]:
		var face = Reach.new()
		var open_frames := 0; var closed_frames := 0
		var p := {"eyeNear":1.0,"eyeFar":1.0,"mouth":0.0,"bowlSummoning":true,"bowlCalling":true,"bowlReach":1.0,"bowlTime":0.0}
		for i in fps*4:
			p.bowlTime = float(i+1)/fps
			var expression: Dictionary = face.prepare(p,1.0/fps)
			if i>fps/2:
				check(expression.eyeNear==0.0 and expression.eyeFar==0.0,"chant did not hold closed smiling eyes")
				if expression.mouth>0.45: open_frames += 1
				if expression.mouth<0.01: closed_frames += 1
			check(face.mouth_open==0.0,"chant used shouting bitmap")
		check(open_frames>0 and closed_frames>0,"chant mouth never fully opened/closed between phrases")
		p.bowlCalling = false; p.bowlReach = 0.0; p.bowlSummoning = false
		var previous_eye := 0.0; var partial := false
		for i in fps:
			var expression: Dictionary = face.prepare(p,1.0/fps)
			partial = partial or (expression.eyeNear>0.0 and expression.eyeNear<1.0)
			check(expression.eyeNear>=previous_eye,"chant eye recovery reversed")
			previous_eye = expression.eyeNear
		check(partial and previous_eye==1.0 and face.chant_mouth==0.0,"chant did not recover naturally")
		for interrupt in ["dragHeld","bowlHitActive","dizzyActive"]:
			p.bowlSummoning = true; p.bowlCalling = true; p.bowlReach = 1.0
			for i in 20: face.prepare(p,1.0/fps)
			var taken := p.duplicate(); taken[interrupt] = true
			face.prepare(taken,1.0/fps)
			check(face.chant_face==0.0 and face.chant_mouth==0.0,"interruption retained chanting face")
		var arrival = Arrival.new(); arrival.start()
		var releases := 0; var previous := -120.0
		for i in fps*2:
			var step: Dictionary = arrival.update(1.0/fps,120.0)
			check(step.offset.y>=previous-0.001,"reveal moved backwards")
			check(step.offset.y>=-120.0 and step.offset.y<=0.0,"reveal escaped clipping interval")
			previous = step.offset.y
			if step.release: releases += 1
		check(releases==1 and not arrival.active(),"arrival must release exactly once")
		for rescue in [false,true]:
			var s = Summon.new(); s.request(); s.begin(cap)
			for i in fps: s.update(1.0/fps,cap,pot,false,false,false,true)
			check(s.weight==1.0 and s.state=="calling","hands not held up")
			if rescue: s.grabbed_cat()
			var away := Rect2(500,400,160,70)
			pot.position.y = 480
			s.update(1.0/fps,away,pot,true,false,true,false)
			var thanks := 0
			for i in fps:
				if s.update(1.0/fps,away,pot,true,false,true,false).thanks: thanks += 1
			check(thanks==0,"thanks fired while held")
			for i in fps*4:
				if s.update(1.0/fps,away,pot,true,true,false,true).thanks: thanks += 1
			check(thanks==(1 if rescue else 0) and not s.active(),"rescue attribution or completion")
			pot.position.y = 0
		var hit = Summon.new(); hit.request(); hit.begin(cap); hit.grabbed_cat()
		hit.finish()
		for i in fps*4:
			check(not hit.update(1.0/fps,cap,Rect2(220,480,130,120),true,true,false,true).thanks,"hit gave thanks")
		check(not hit.active(),"hit stranded summoning")
		var under = Summon.new(); under.request(); under.begin(cap); under.grabbed_cat()
		under.update(1.0/fps,cap,Rect2(220,480,130,120),true,true,false,true)
		check(under.state=="recover","grab without escaping counted as rescue")
		under.cancel(); check(not under.active() and under.weight==0.0,"cancel left hands stuck")
	print("BOWL SUMMON: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
