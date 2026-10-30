extends SceneTree
const Sleep = preload("res://scripts/sleep_cycle.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text)

func run_for(cycle, seconds: float, fps: int = 60, minute: int = 12*60, blocked: bool = false, settled: bool = true) -> Dictionary:
	var events := {"started":0,"sit":0,"waking":0,"finished":0}
	for frame in int(round(seconds*fps)):
		var step: Dictionary = cycle.advance(1.0/fps,{"minute":minute,"blocked":blocked,"settled":settled})
		for key in events:
			if step[key]: events[key] += 1
	return events

func fixture():
	var cycle = Sleep.new()
	cycle.rng.seed = 31102026
	cycle.random_source = func(): return 0.0
	return cycle

func _initialize() -> void:
	verify_schedule()
	verify_probabilities()
	for fps in [30,60,120]:
		verify_timeline(fps)
		verify_cooldown(fps)
	verify_night()
	verify_blocks()
	verify_pause_and_invalid()
	verify_config()
	for failure in failures: printerr("SLEEP CYCLE: "+failure)
	print("Sleep cycle: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func verify_schedule() -> void:
	var cycle = fixture()
	check(cycle.settings()=={"enabled":true,"start_minute":1380,"end_minute":480,"frequency":1},"default schedule differs from approved plan")
	check(not cycle.in_schedule(1379) and cycle.in_schedule(1380),"sleep start boundary is not inclusive")
	check(cycle.in_schedule(1439) and cycle.in_schedule(0) and cycle.in_schedule(479),"cross-midnight schedule has a gap")
	check(not cycle.in_schedule(480) and not cycle.in_schedule(720),"wake end boundary is not exclusive")
	cycle.configure({"start_minute":60,"end_minute":120})
	check(not cycle.in_schedule(59) and cycle.in_schedule(60) and cycle.in_schedule(119) and not cycle.in_schedule(120),"same-day schedule is incorrect")
	cycle.configure({"start_minute":100,"end_minute":100})
	check(cycle.in_schedule(0) and cycle.in_schedule(1439),"equal schedule times do not represent all day")
	check(not cycle.in_schedule(-1) and not cycle.in_schedule(1440),"invalid clock minute entered schedule")

func verify_probabilities() -> void:
	for frequency in 3:
		var cycle = fixture()
		cycle.configure({"frequency":frequency})
		cycle.random_source = func(): return Sleep.DAY_CHANCES[frequency]
		run_for(cycle,180)
		check(cycle.state=="awake" and cycle.checks==1,"day probability upper boundary accepted at frequency "+str(frequency))
		cycle.random_source = func(): return Sleep.DAY_CHANCES[frequency]-0.00001
		run_for(cycle,60)
		check(cycle.state=="drowsy" and cycle.checks==2,"frequency probability threshold did not apply")
	var night = fixture()
	night.random_source = func(): return 0.6
	run_for(night,30,60,1380)
	check(night.state=="awake" and night.checks==1,"night probability upper boundary accepted")
	night.random_source = func(): return 0.59999
	run_for(night,30,60,1380)
	check(night.state=="drowsy" and night.checks==2,"night frequency/probability is not higher")
	for fps in [30,60,120]:
		var rejects = fixture(); rejects.random_source = func(): return 1.0
		run_for(rejects,600,fps)
		check(rejects.checks==8,"daily dice count depends on render frames at "+str(fps))
		var night_rejects = fixture(); night_rejects.random_source = func(): return 1.0
		run_for(night_rejects,600,fps,0)
		check(night_rejects.checks==20,"night dice count depends on render frames at "+str(fps))

func verify_timeline(fps: int) -> void:
	var cycle = fixture()
	var events := run_for(cycle,180.0-1.0/fps,fps)
	check(cycle.state=="awake" and events.started==0,"day sleeps before three idle minutes at "+str(fps))
	events = run_for(cycle,1.0/fps,fps)
	check(cycle.state=="drowsy" and events.started==1 and cycle.pose().sleepEye==1.0,"day sleep start did not begin smoothly at "+str(fps))
	events = run_for(cycle,2,fps)
	check(cycle.state=="settling" and events.sit==1 and events.started==0,"drowsy must request sitting exactly once at "+str(fps))
	events = run_for(cycle,3,fps)
	check(cycle.state=="asleep" and cycle.pose().sleepWeight==1.0 and cycle.pose().sleepEye==0.0,"sleep did not settle closed-eye at "+str(fps))
	check(cycle.nap_seconds>=180 and cycle.nap_seconds<=480,"random nap is outside three to eight minutes")
	cycle.nap_seconds = 180.0
	events = run_for(cycle,180,fps)
	check(cycle.state=="waking" and events.waking==1,"daytime nap did not naturally wake at "+str(fps))
	var closed: float = cycle.pose().sleepEye
	run_for(cycle,0.5,fps)
	check(closed==0.0 and cycle.pose().sleepEye>closed and cycle.pose().sleepEye<1.0,"wake did not gradually open eyes")
	events = run_for(cycle,1.5,fps)
	check(cycle.state=="awake" and events.finished==1 and cycle.pose().sleepWeight==0.0 and cycle.pose().sleepEye==1.0,"wake did not finish neutral at "+str(fps))

func verify_cooldown(fps: int) -> void:
	var cycle = fixture()
	check(cycle.request_sleep() and not cycle.request_sleep(),"duplicate manual sleep restarted animation")
	run_for(cycle,5,fps,0)
	cycle.interact()
	var before := cycle.pose()
	check(cycle.state=="waking" and before.sleepEye==0.0 and before.sleepWeight==1.0,"interaction jumped to awake pose")
	var events := run_for(cycle,2,fps,0)
	check(events.waking==1 and events.finished==1 and cycle.state=="awake","manual wake signals repeated or missing")
	run_for(cycle,119,fps,0)
	check(cycle.state=="awake" and cycle.checks==0,"scheduled cat fell asleep during wake protection")
	run_for(cycle,1,fps,0)
	check(cycle.state=="drowsy" and cycle.checks==1,"night sleep did not resume after two minute protection")
	cycle.interact(true)
	check(cycle.state=="awake" and not cycle.active() and cycle.pose().sleepWeight==0.0,"immediate interruption retained sleep ownership")
	events = run_for(cycle,1.0/fps,fps,0)
	check(events.finished==1 and events.started==0 and events.sit==0,"immediate interruption leaked delayed entry events")
	for index in 8:
		run_for(cycle,90,fps,0); cycle.interact()
	check(cycle.state=="awake" and cycle.idle_seconds==0.0,"continued user interaction did not restart the awake wait")

func verify_night() -> void:
	var cycle = fixture()
	var events := run_for(cycle,30,60,0)
	check(cycle.state=="drowsy" and events.started==1,"night idle did not begin at thirty seconds")
	run_for(cycle,5,60,0)
	cycle.nap_seconds = 1.0
	events = run_for(cycle,3600,30,0)
	check(cycle.state=="asleep" and events.waking==0 and events.finished==0,"night sleep woke without interaction")
	var step: Dictionary = cycle.advance(1.0/60,{"minute":480})
	check(cycle.state=="waking" and step.waking,"leaving sleep schedule did not begin natural wake")
	var day = fixture(); day.request_sleep(); run_for(day,5)
	day.nap_seconds = 1.0
	step = day.advance(1.0/60,{"minute":1380})
	events = run_for(day,30,60,1380)
	check(day.state=="asleep" and events.waking==0,"day nap was not extended when sleep schedule began")

func verify_blocks() -> void:
	var cycle = fixture()
	run_for(cycle,300,60,720,true)
	check(cycle.state=="awake" and cycle.checks==0 and cycle.idle_seconds>299,"busy dialogue rolled sleep or lost all idle history")
	var step: Dictionary = cycle.advance(1.0/60,{"minute":720,"blocked":false,"settled":false})
	check(cycle.state=="awake" and not step.started,"moving/unsettled cat started sleeping")
	step = cycle.advance(1.0/60,{"minute":720,"blocked":false,"settled":true})
	check(cycle.state=="drowsy" and step.started,"settled cat did not spend its pending idle opportunity")
	run_for(cycle,1)
	var before := cycle.pose()
	step = cycle.advance(0.01,{"minute":720,"blocked":true})
	check(cycle.state=="waking" and step.waking and not step.sit,"busy action did not cancel drowsy sitting request")
	check(absf(float(cycle.pose().sleepEye)-float(before.sleepEye))<0.02,"interrupted drowsiness jumped its eyes")
	var events := run_for(cycle,4,60,720,true)
	check(cycle.state=="awake" and events.waking==0 and events.finished==1,"persistent busy state restarted wake every frame")
	var unsettled = fixture(); unsettled.request_sleep(); run_for(unsettled,5,60,720,false,false)
	check(unsettled.state=="settling","sleep became deep before body settled")
	unsettled.advance(1.0/60,{"minute":720,"settled":true})
	check(unsettled.state=="asleep","fully settled sleep did not complete")
	var canceled = fixture(); canceled.request_sleep(); canceled.interact()
	step = canceled.advance(0.01,{"minute":720})
	check(not step.started and not step.sit and step.waking,"cancelled-before-frame manual sleep still announced entry")

func verify_pause_and_invalid() -> void:
	var cycle = fixture()
	run_for(cycle,170)
	for delta in [NAN,INF,-INF,-1.0,0.0,3600.0]: cycle.advance(delta,{"minute":720})
	check(absf(cycle.idle_seconds-170.0)<0.001 and cycle.checks==0,"invalid or resumed frame accrued idle/check backlog")
	run_for(cycle,10)
	check(cycle.state=="drowsy" and cycle.checks==1,"ordinary frame after pause did not resume one opportunity")
	run_for(cycle,5,60,0)
	var before := cycle.pose()
	for minute in [NAN,INF,"480",-1,1440]: cycle.advance(0.01,{"minute":minute})
	check(cycle.state=="asleep" and cycle.pose().sleepEye==before.sleepEye,"invalid local clock woke scheduled sleep")
	cycle.advance(3600.0,{"minute":480})
	check(cycle.state=="waking" and cycle.age==0.0,"resume across wake boundary skipped natural waking animation")
	var broken_rng = fixture(); broken_rng.random_source = func(): return NAN
	run_for(broken_rng,180)
	check(broken_rng.state=="awake" and broken_rng.checks==1,"invalid probability source forced a sleep")

func verify_config() -> void:
	var cycle = fixture()
	cycle.configure({"enabled":"yes","start_minute":NAN,"end_minute":INF,"frequency":"high"})
	check(cycle.settings()=={"enabled":true,"start_minute":1380,"end_minute":480,"frequency":1},"invalid config did not use safe defaults")
	cycle.configure({"enabled":false,"start_minute":-500,"end_minute":99999,"frequency":9})
	check(cycle.settings()=={"enabled":false,"start_minute":0,"end_minute":1439,"frequency":2},"settings ranges were not sanitized")
	run_for(cycle,600,60,0)
	check(not cycle.active() and cycle.checks==0,"disabled automatic sleep still triggered")
	check(cycle.request_sleep(),"manual sleep did not remain available with automation off")
	run_for(cycle,5,60,0)
	check(cycle.state=="asleep","manual sleep with automation disabled failed")
	var unchanged = fixture(); run_for(unchanged,100)
	unchanged.configure(unchanged.settings())
	check(absf(unchanged.idle_seconds-100.0)<0.001,"saving unchanged sleep config reset idle activity")
	var automatic = fixture(); run_for(automatic,30,60,0)
	check(automatic.state=="drowsy","fixture automatic sleep was not started")
	automatic.configure({"enabled":false})
	check(automatic.state=="waking","disabling automation did not cancel current automatic sleep")
