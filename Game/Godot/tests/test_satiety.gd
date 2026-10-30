extends SceneTree
const Satiety = preload("res://scripts/satiety.gd")
const Files = preload("res://scripts/bowl_files.gd")
const Food = preload("res://scripts/food_item.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("SATIETY: "+message)
func _initialize() -> void:
	var s = Satiety.new(); s.capacity = 1000
	s.observe(750)
	check(not s.resting and s.can_take(250),"crossing half upward interrupted meal")
	s.observe(1000)
	check(s.resting and s.full_pending and not s.can_take(0),"full did not latch")
	s.full_pending = false; s.observe(800); s.observe(500)
	check(s.resting and not s.full_pending,"half reopened or repeated full reaction")
	s.observe(499)
	check(not s.resting and s.can_take(501),"strictly below half did not recover")
	s.observe(900,101,true)
	check(s.resting,"whole-file fit did not stop meal")
	s.full_pending = false; s.observe(400,700,true)
	check(s.resting and not s.full_pending,"blocked FIFO head caused repeated full reaction")
	s.observe(300,700,true)
	check(not s.resting,"head fits but did not resume")
	s.observe(0,1001,true)
	check(not s.can_take(1001) and not s.full_pending,"oversized file caused false full celebration")
	s.reminder_wait = 0.0
	check(s.request_bowl(0.1,false,true)=="","busy reminder")
	check(s.request_bowl(0.1,false,false)=="ask","hidden bowl not requested")
	check(s.request_bowl(0.1,false,false)=="","reminder repeated immediately")
	s.auto_open = true; s.reminder_wait = 0.0
	check(s.request_bowl(0.1,false,false)=="open","auto open ignored")
	s.manual_close()
	check(s.reminder_wait==30.0,"manual hide immediately reopened")
	s.resting = true; s.reminder_wait = 0.0
	check(s.request_bowl(0.1,false,false)=="","full pet requested bowl")
	check(Satiety.sanitize_hours(NAN)==6.0 and Satiety.sanitize_hours(-2)==0.01,"invalid digestion time")
	var f = Files.new(); f.storage_ready = true; f.stomach_capacity = 1000
	for i in 3:
		var token := str(i)
		f.entries.append({"token":token,"bytes":400,"ready":true,"icon":"","label":token})
		f.stable[token] = true; f.textures[token] = Food.DEMO_TEXTURES[0]
	check(f.food_items().size()==2,"queued meal overbooked stomach")
	check(f.food_items(["0"]).size()==1,"held food was not reserved")
	f.pending["0"] = 400
	check(f.food_items(["0"]).size()==1,"pending food counted twice")
	f.entries[1].ready = false
	check(f.food_items().is_empty(),"skipped busy FIFO head")
	f.entries[1].ready = true; f.entries[1].bytes = 1100
	check(f.food_items().is_empty(),"skipped oversized FIFO head")
	f.free()
	check_oversized()
	print("SATIETY: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func check_oversized() -> void:
	var s = Satiety.new(); s.capacity = 1000
	s.observe(0,5000,true,true)
	check(not s.resting and s.can_take(5000,true),"all-oversized empty stomach cannot accept one whole file")
	check(not s.can_take(5000),"oversized permission leaked into ordinary meals")
	s.observe(499,5000,true,true)
	check(s.can_take(5000,true),"below-half oversize opportunity rejected")
	s.observe(500,5000,true,true)
	check(not s.can_take(5000,true),"exactly-half stomach accepted oversized food")
	s.observe(499,5000,true,true)
	check(not s.resting and s.can_take(5000,true),"resting oversized meal did not reopen below half")
	s.observe(5499,5000,true,true)
	check(s.used == 5499 and s.resting and s.full_pending,"oversized swallow did not retain real usage and latch fullness")
	s.full_pending = false
	s.observe(5499,5000,true,true)
	check(not s.full_pending and not s.can_take(5000,true),"oversized full reaction repeated or allowed a second file")
	s.observe(500,5000,true,true)
	check(s.resting,"oversized meal recovered at exactly half")
	s.observe(0,5000,true,false)
	check(s.resting and not s.can_take(5000),"missing all-food proof bypassed resting FIFO guard")
	s.observe(0,5000,true,true)
	check(not s.resting and s.can_take(5000,true),"digested oversized meal could not recover")
	check(not s.can_take(-1,true),"oversized permission accepted invalid negative bytes")
	var f = Files.new(); f.storage_ready = true; f.stomach_capacity = 100
	for spec in [["older",900],["smaller",500]]:
		var token: String = spec[0]
		f.entries.append({"token":token,"bytes":spec[1],"ready":true,"icon":"","label":token})
		f.stable[token] = true; f.textures[token] = Food.DEMO_TEXTURES[0]
	check(not f.all_food_oversized() and f.food_items().is_empty(),"visible prefix alone proved all files oversized")
	f.smallest_bytes = 500
	var items: Array = f.food_items()
	check(f.all_food_oversized() and items.size() == 1,"all-oversized snapshot did not offer exactly one food")
	check(items.size() == 1 and items[0].source.token == "older","oversized fallback changed arrival order to size order")
	f.stomach_bytes = 49
	check(f.food_items().size() == 1,"below-half usage blocked oversized offer")
	f.stomach_bytes = 50
	check(f.food_items().is_empty(),"exactly-half usage offered oversized food")
	f.stomach_bytes = 500
	check(f.food_items().is_empty(),"over-capacity usage offered another food")
	f.stomach_bytes = 0
	check(f.food_items(["older"]).is_empty(),"held oversized file allowed a second oversized offer")
	check(f.food_items(["outside-snapshot"]).is_empty(),"unknown held item allowed oversized overbooking")
	f.pending["older"] = 900
	check(f.food_items().is_empty(),"pending oversized file allowed another offer")
	f.pending.clear(); f.pending["zero-byte-pending"] = 0
	check(f.food_items().is_empty(),"zero-byte pending item bypassed single-food exception")
	f.pending.clear(); f.smallest_bytes = 100
	check(not f.all_food_oversized() and f.food_items().is_empty(),"fitting file beyond the visible prefix was ignored")
	f.smallest_bytes = 500; f.entries[0].ready = false
	check(f.food_items().is_empty(),"busy oldest oversized file was skipped")
	f.entries[0].ready = true; f.stable.erase("older")
	check(f.food_items().is_empty(),"unstable oldest oversized file was skipped")
	f.stable["older"] = true; f.failed["older"] = 1
	check(f.food_items().is_empty(),"failed oldest oversized file was skipped")
	f.failed.clear(); f.storage_ready = false
	check(not f.all_food_oversized() and f.food_items().is_empty(),"invalid storage snapshot authorized an oversized meal")
	f.storage_ready = true; f.entries.clear()
	check(not f.all_food_oversized(),"empty queue retained oversized proof")
	f.free()
