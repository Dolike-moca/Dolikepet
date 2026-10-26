extends SceneTree
const Sizes = preload("res://scripts/pet_size.gd")
const Change = preload("res://scripts/size_change.gd")
var failures: Array[String] = []
func verify(value: bool, label: String) -> void:
	if not value: failures.append(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	verify(Sizes.PIXELS == [150,225,300,375,450,525,600],"seven size choices")
	verify(Sizes.nearest(420)==450 and Sizes.nearest(800)==600 and Sizes.nearest(80)==150,"legacy size migration and limits")
	verify(Sizes.step(300,1)==375 and Sizes.step(300,-1)==225 and Sizes.step(600,1)==600,"one wheel step, limits")
	var change := Change.new()
	change.initialize(300)
	change.request(450,300)
	for i in 60: change.update(1.0/60.0,300,true)
	verify(change.state=="waiting" and change.pose().is_empty() and change.value==300,"blocked request stays pending")
	change.request(600,300)
	var last := change.value
	var peaks := 0
	var previous_flash := 0.0
	var rising := true
	var saw_food := false
	var bites := {}
	var remaining:=1.0
	var eating_frames:=0
	for i in 360:
		change.update(1.0/60.0,roundi(change.value),false)
		verify(change.value>=last and change.value<=600,"growth monotonic and bounded")
		last = change.value
		var pose := change.pose()
		if pose.get("pickupAlpha",0.0)>0.0:
			saw_food = true
			verify(pose.pickupFlight==1.0 and pose.pickupBowl==0.0,"mushroom appears in hand without bowl flight")
			verify(pose.foodItem.source.is_empty(),"prop cannot consume any user file")
		if pose.get("foodCutIndex",-1)>=0:
			bites[pose.foodCutIndex] = true
			eating_frames+=1
			verify(pose.chewEyeClose==1.0 and pose.chewReliefSmile>0.5,"happy closed eyes throughout five bites")
			verify(pose.foodRemaining<=remaining+0.0001,"bites consume the prop monotonically")
			remaining=pose.foodRemaining
			if pose.foodCutIndex<4: verify(pose.pickupAlpha>0.0 and remaining>0.0,"mushroom stays visible until final bite")
		var flash := change.flash()
		if flash<previous_flash and rising: peaks+=1; rising=false
		if flash>previous_flash: rising=true
		previous_flash=flash
	verify(not change.pending() and change.value==600 and saw_food and bites.size()==5 and peaks==3,"one mushroom, five bites, three light pulses, final target")
	verify(eating_frames>=200 and remaining==0.0,"five small bites take about 3.5 seconds and finish the stem")
	change.request(150,600)
	for i in 45:
		change.update(1.0/60.0,roundi(change.value),false)
		verify(change.pose().is_empty() and change.flash()==0.0,"shrinking has no mushroom or flash")
	verify(change.value==150 and not change.pending(),"shrink completion")
	change.request(600,150)
	for i in 285: change.update(1.0/60.0,roundi(change.value),false)
	verify(change.charged,"mushroom consumed before interruption")
	change.update(0.02,roundi(change.value),true)
	for i in 10: change.update(0.02,roundi(change.value),false)
	verify(change.state=="grow" and change.pose().pickupAlpha==0.0 and change.pose().pickupArms==0.0,"resume consumed prop without second eating or hand jump")
	change.request(450,roundi(change.value))
	for i in 90: change.update(1.0/60.0,roundi(change.value),false)
	verify(change.value==450 and not change.pending(),"retarget while growing")
	for message in failures: printerr(message)
	print("Size-change controller: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
