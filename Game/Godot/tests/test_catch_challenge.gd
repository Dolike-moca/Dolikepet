extends SceneTree
const Challenge = preload("res://scripts/catch_challenge.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, words: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("CATCH: "+words)
func run() -> void:
	var game = Challenge.new()
	check(not game.caught(0,12,0,false,true) and not game.shown,"unthrown fall started game")
	var expected := 0
	var walls := 0
	for n in range(1,41):
		var hits: int = [2,1,3,1][(n-1)%4]
		game.released(n*1.0,walls,0,700,420); walls += hits
		check(game.caught(n+0.5,walls,0,false,true),"valid wall catch refused")
		expected += hits*hits+(n if n%10==0 else 0)
		check(game.streak==n and game.total==expected,"per-throw running total at "+str(n))
		check(game.base_points==hits*hits and game.scored_bounces==hits,"previous flight leaked into base points")
		check(game.delta==hits*hits+(n if n%10==0 else 0),"increment at "+str(n))
		if n<=4: check(game.total==[4,5,14,15][n-1],"2 / 1 / 3 / 1 bounces must add 4 / 1 / 9 / 1")
		var deadline: float = game.deadline
		check(not game.caught(n+0.6,walls,0,false,true) and game.deadline==deadline,"duplicate press extended catch")
	var snapshot: Dictionary = game.snapshot(40.5)
	check(snapshot.base_points==1 and snapshot.bonus==40 and snapshot.delta==41,"40th single bounce must expose +1 and +40 separately")
	check(game.total==250 and game.best==250,"mixed-bounce 40 streak record")
	game.advance(43.5,walls,0)
	check(game.total==0 and game.streak==0 and game.best==250 and game.shown,"3s exact deadline/reset lost record")
	check(game.base_points==0 and game.bonus==0 and game.scored_bounces==0,"ended round retained awards")
	game = Challenge.new()
	game.released(34,100,0,700,420); game.caught(34.5,101,0,false,true)
	game.released(37.499,101,0,700,420)
	game.advance(99,102,0)
	check(game.streak==1 and game.phase=="flight","flight incorrectly kept held countdown")
	check(game.caught(99.5,102,0,false,true) and game.total==2,"second single bounce must add one after long flight")
	game.released(100,102,0,700,420)
	check(not game.caught(100.5,102,0,false,true) and game.total==0,"catch without a new bounce qualified")
	game.released(101,103,0,700,420)
	check(not game.caught(101.5,104,1,false,true),"floor then catch in one display frame qualified")
	game.released(102,104,1,700,420)
	check(not game.caught(102.5,105,1,true,true),"grounded catch qualified")
	game.released(103,105,1,700,420); game.caught(103.5,106,1,false,true)
	game.advance(104,106,2)
	check(game.total==1,"floor contact while held invalidated a catch")
	game.released(106.5,106,2,700,420); game.caught(107,107,2,false,true)
	check(game.total==1,"throw at exact timeout incorrectly retained streak")
	game.released(108,107,2,0,420)
	check(not game.active() and game.phase=="idle","resting release retained challenge")
	game.released(109,107,2,700,420); game.advance(110,108,3)
	check(not game.active() and game.phase=="idle","ground did not end flight")
	game.released(111,108,3,700,420); game.finish("menu")
	check(not game.caught(111.5,109,3,false,true),"menu pin became a catch")
	print("CATCH: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
