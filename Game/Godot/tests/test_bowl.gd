extends SceneTree
const Capacity = preload("res://scripts/bowl_capacity.gd")
const Meal = preload("res://scripts/meal_motion.gd")
const Food = preload("res://scripts/food_item.gd")
const Jump = preload("res://scripts/bowl_jump.gd")
const Bowl = preload("res://scripts/bowl_window.gd")
var checks := 0
var failures := 0
var near := true
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("BOWL: "+words)
func fixture(name: String):
	var food = Food.from_texture(Food.DEMO_TEXTURES[0],name)
	food.source = {"path":name,"token":name}
	return food
func run() -> void:
	check(Capacity.level(0,Capacity.GB)==0.0,"empty was filled")
	check(Capacity.sanitize(-10)==Capacity.MB,"invalid capacity")
	var last := 0.0
	for i in 1001:
		var value: float = Capacity.level(i*Capacity.GB/500,Capacity.GB)
		check(value>=last and value<=0.95,"fill backwards or overflow")
		last = value
	var meal = Meal.new()
	meal.serve_allowed = func(): return near
	meal.source_available = func(_food): return true
	check(meal.request_food([fixture("one"),fixture("two")],0,600),"start refused")
	near = false
	meal.update(0.05,true)
	for i in 25: meal.update(1.0/60,true)
	check(not meal.active() and meal.take_finished().is_empty(),"out of reach took a file")
	near = true
	meal.request_food([fixture("one"),fixture("two")],0,600)
	for i in 90: meal.update(1.0/60,true)
	check(meal.age>meal.CATCH_TIME,"never caught food")
	near = false
	var events := []
	for i in 12000:
		meal.update(1.0/60,true)
		events.append_array(meal.take_finished())
		if not meal.active(): break
	check(events.size()==1 and events[0].label=="one","far bowl served queued file or lost held food")
	check(meal.take_finished().is_empty(),"duplicate completion")
	near = true
	meal.request_food([fixture("one"),fixture("two")],0,600)
	events.clear()
	for i in 18000:
		meal.update(1.0/60,true)
		events.append_array(meal.take_finished())
		if not meal.active(): break
	check(events.size()==2 and meal.served==2,"continuous queue failed")
	meal.request_food([fixture("cancel")],0,600)
	for i in 90: meal.update(1.0/60,true)
	meal.cancel(true)
	check(meal.take_finished().is_empty(),"cancel ate the file")
	for fps in [30,60,120]:
		var jump = Jump.new()
		jump.rng.seed = 32
		var at := Vector2(600,500)
		var min_y := at.y
		for i in fps*3:
			var result: Dictionary = jump.update(1.0/fps,at,Vector2(400,400),Rect2(0,0,1600,900),i==0,false)
			at = result.position; min_y = minf(min_y,at.y)
		check(min_y<480 and at==Vector2(600,500) and not jump.active(),"jump failed to land at original floor")
	var bowl = Bowl.new()
	root.add_child(bowl); bowl.fit_pet(600); bowl.show()
	var area := DisplayServer.screen_get_usable_rect(bowl.current_screen)
	bowl.place(Vector2i(area.position.x+50,area.position.y+50))
	for i in 900: bowl._process(1.0/60)
	check(absf(bowl.position.y+bowl.size.y-area.end.y)<=1,"bowl did not settle on desktop floor")
	check(absf(bowl.size.y-248)<=2,"approved 20-percent smaller size changed")
	var art: Image = bowl.ART.get_image()
	var clipped := 0
	for y in range(0,art.get_height(),3):
		for x in range(0,art.get_width(),3):
			if art.get_pixel(x,y).a<=0.06: continue
			var pixel: Vector2 = bowl.sprite.position+Vector2(x,y)*bowl.art_scale
			if not Geometry2D.is_point_in_polygon(pixel,bowl.mouse_passthrough_polygon): clipped += 1
	check(clipped==0,"native window region clips cauldron art: %d samples"%clipped)
	bowl.total_bytes = Capacity.GB
	for i in 400: bowl._process(1.0/60)
	check(is_equal_approx(bowl.fill,0.95),"fullness failed to animate")
	bowl.total_bytes = 0
	for i in 400: bowl._process(1.0/60)
	check(bowl.fill==0.0,"empty did not clear")
	bowl.queue_free()
	print("BOWL: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
