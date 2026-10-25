extends SceneTree
const Jump = preload("res://scripts/bowl_jump.gd")
const Reach = preload("res://scripts/bowl_reach_pose.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL SHOUT: "+message)
func face(step: Dictionary) -> Dictionary:
	return {"eyeNear":1.0,"eyeFar":1.0,"bowlReach":step.weight,"bowlTime":step.time,"bowlCalling":step.calling,"bowlPaused":step.paused}
func _initialize() -> void:
	for fps in [30,60,120]:
		var jump = Jump.new(); var reach = Reach.new()
		var origin := Vector2(600,500); var at := origin
		var size := Vector2(420,420); var area := Rect2(0,0,1600,920)
		var hops := 0; var flying := false; var open_frames := 0; var shut_frames := 0; var partial_eyes := 0
		for i in fps*10:
			var step: Dictionary = jump.update(1.0/fps,at,size,area,i<float(fps)*6.7,false)
			at = step.position
			var air := at.y<origin.y-0.1
			if air and not flying: hops += 1
			flying = air
			check(at.y<=origin.y and at.y>=origin.y-31.0,"hop exceeded bounded height")
			check(absf(at.x-origin.x)<=6.0,"side sway drifted")
			if jump.age>0.6 and jump.age<6.7: check(step.weight>0.999,"hands lowered between hops")
			var pose: Dictionary = reach.prepare(face(step),1.0/fps)
			if step.weight>0.00001: check(pose.eyeNear==0.0 and pose.eyeFar==0.0,"normal eyes visible under squeeze")
			if pose.bowlEyeOpenness>0.01 and pose.bowlEyeOpenness<0.99: partial_eyes += 1
			if step.calling:
				if reach.mouth_open>0.8: open_frames += 1
				if reach.mouth_open==0.0: shut_frames += 1
		check(hops==6,"held bowl did not produce six distinct hops")
		check(open_frames>0 and shut_frames>0,"calling never fully opened/closed")
		check(partial_eyes>0,"eyes skipped progressive reopening")
		check(at==origin and not jump.active() and reach.mouth_open==0.0 and not reach.eye_recovery.recovering,"burst did not return to neutral")
		# Pause in midair; release must land before lowering the arms.
		jump = Jump.new(); reach = Reach.new(); at = origin
		for i in int(fps*1.1):
			var step: Dictionary = jump.update(1.0/fps,at,size,area,true,false)
			at = step.position; reach.prepare(face(step),1.0/fps)
		var stopped_at := at; var stopped_age: float = jump.age; var stopped_mouth: float = reach.mouth_open
		for i in fps:
			var step: Dictionary = jump.update(1.0/fps,at,size,area,false,true)
			at = step.position; reach.prepare(face(step),1.0/fps)
		check(at==stopped_at and jump.age==stopped_age and reach.mouth_open==stopped_mouth,"paused animation advanced")
		var previous_open: float = reach.mouth_open
		for i in fps*3:
			var step: Dictionary = jump.update(1.0/fps,at,size,area,false,false)
			at = step.position; reach.prepare(face(step),1.0/fps)
			check(reach.mouth_open<=previous_open+0.00001,"release reopened mouth")
			previous_open = reach.mouth_open
			if at.y<origin.y-0.1: check(step.weight>0.999,"arms dropped while still airborne")
		check(at==origin and not jump.active(),"early release drifted or kept hopping")
		# Taking over with a real drag must not leave the shouting face attached.
		var p := {"eyeNear":1.0,"eyeFar":1.0,"bowlReach":1.0,"bowlTime":1.1,"bowlCalling":true}
		reach.prepare(p,1.0/fps); p.dragHeld = true
		var interrupted: Dictionary = reach.prepare(p,1.0/fps)
		check(interrupted.bowlReach==0.0 and reach.mouth_open==0.0 and not reach.eye_recovery.recovering,"drag did not take face priority")
	print("BOWL SHOUT: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
