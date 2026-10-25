extends SceneTree
const Physics = preload("res://scripts/desktop_physics.gd")
const Challenge = preload("res://scripts/catch_challenge.gd")
var checks := 0
var failures := 0
var motion
var at := Vector2.ZERO
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CATCH PHYSICS: "+words)
func setup(offset := Vector2.ZERO) -> void:
	if is_instance_valid(motion): motion.free()
	motion = Physics.new(); root.add_child(motion)
	motion.set_geometry(Vector2.ONE*240,Rect2(offset,Vector2(1280,900)),Vector2(0.43,0.25)*240)
	at = offset+Vector2(460,280); motion.reposition(at); motion.configure(false)
func step() -> void:
	var result: Dictionary = motion.update(1.0/120,at,motion.size,motion.area,motion.state=="held")
	if result.move: at = result.position
	await physics_frame; await process_frame
func run() -> void:
	var game = Challenge.new()
	var n := 0
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP]:
		n += 1
		setup(Vector2(-1920,-200) if n==3 else Vector2.ZERO)
		motion.begin(at,at+motion.anchor,1.0)
		motion.body.linear_velocity = direction*4500
		game.released(n*1.0,motion.body.wall_sequence,motion.body.floor_sequence,4500,240)
		motion.release()
		var bounced := false
		for frame in 100:
			await step()
			if motion.body.wall_sequence>0:
				bounced = true; break
		check(bounced and motion.body.linear_velocity.dot(direction)<0,"no qualifying native rebound "+str(direction))
		check(game.caught(n+0.5,motion.body.wall_sequence,motion.body.floor_sequence,motion.body.grounded,motion.state=="falling"),"native rebound did not score")
		check(game.total==n and game.base_points==1,"native single-bounce base increased with streak")
		var velocity: Vector2 = motion.body.linear_velocity
		motion.begin(at,at+motion.anchor,1.0)
		check(motion.body.linear_velocity==velocity,"catch changed momentum")
	# A real side/top double rebound must award four, regardless of the
	# existing three-catch streak. The next flight starts from zero bounces.
	setup()
	motion.begin(at,at+motion.anchor,1.0)
	motion.body.linear_velocity = Vector2(7000,-5000)
	game.released(4,0,0,motion.body.linear_velocity.length(),240); motion.release()
	for frame in 100:
		await step()
		if motion.body.wall_sequence>=2: break
	check(motion.body.wall_sequence==2,"native double rebound was not counted twice")
	check(game.caught(4.5,motion.body.wall_sequence,motion.body.floor_sequence,motion.body.grounded,true),"double rebound catch refused")
	check(game.base_points==4 and game.total==7 and game.streak==4,"double rebound did not add exactly four")
	setup()
	motion.begin(at,at+motion.anchor,1.0)
	motion.set_pointer(Vector2(-400,at.y)+motion.anchor)
	for i in 100: await step()
	check(motion.body.impact_count>0 and motion.body.wall_sequence==0,"held wall drag counted")
	setup()
	motion.configure(true)
	motion.begin(at,at+motion.anchor,1.0); motion.body.linear_velocity = Vector2(0,800)
	game.released(10,0,0,800,240); motion.release()
	for i in 140:
		await step()
		game.advance(10+i/120.0,motion.body.wall_sequence,motion.body.floor_sequence)
		if motion.body.floor_sequence>0: break
	check(motion.body.floor_sequence>0 and motion.body.wall_sequence==0,"floor classified as wall")
	check(game.phase=="idle" and game.total==0,"native floor failed to end round")
	motion.free()
	print("CATCH PHYSICS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
