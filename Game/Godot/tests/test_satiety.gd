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
	print("SATIETY: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
