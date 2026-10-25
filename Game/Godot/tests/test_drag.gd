extends SceneTree
const Drag = preload("res://scripts/drag_motion.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	for fps in [30, 60, 120]:
		for extent in [240.0, 420.0, 800.0]:
			var d = Drag.new()
			var origin := Vector2(-1100, -200)
			d.begin(origin, -0.12)
			var maximum := 0.0
			for f in fps * 3:
				var t: float = float(f) / fps
				var target: Vector2 = origin + Vector2(sin(t * 3.0), sin(t * 2.0)) * extent * 0.8
				var at: Vector2 = d.follow_pointer(1.0 / fps, target, Vector2.ONE * extent)
				d.update(1.0 / fps, at, Vector2.ONE * extent)
				maximum = maxf(maximum, absf(d.tilt))
				_check(is_finite(d.tilt) and absf(d.tilt) <= deg_to_rad(22.01), "tilt limit / finite")
			_check(maximum > deg_to_rad(10), "missing distance-driven suspended swing")
			_check(d.face == 1.0 and d.hang > 0.99 and d.facing == -1.0, "held face / turn width")
			var held_at: Vector2 = d.position
			d.release()
			for f in fps * 3:
				d.update(1.0 / fps, held_at, Vector2.ONE * extent)
				_check(d.position == held_at, "release moved the window")
			_check(not d.active() and d.hang == 0.0 and d.face == 0.0 and d.tilt == 0.0, "release failed to settle")
	var d = Drag.new()
	d.begin(Vector2.ZERO)
	d.update(0.1, Vector2(100, 20), Vector2(420, 420))
	var angle: float = d.tilt
	d.update(1.0, Vector2(200, 100), Vector2(420, 420), true)
	_check(d.tilt == angle, "menu/minimize pause")
	d.update(NAN, Vector2.ZERO, Vector2(420, 420))
	_check(d.tilt == angle, "invalid delta")
	d.release()
	d.begin(Vector2(100, 100), 1.0)
	_check(d.state == "held" and d.tilt == angle, "regrab reset swing")
	d.reposition(Vector2(-800, 0))
	d.update(1.0 / 60, Vector2(-800, 0), Vector2(600, 600))
	_check(d.velocity == Vector2.ZERO, "zoom/position rebase made impulse")
	d.cancel()
	_check(not d.active() and d.face == 0.0 and d.tilt == 0.0, "reset cancellation")
	_check_follow()
	_check_progressive_pull()
	_check_bending()
	print("DRAG: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		if failures < 12: printerr("DRAG: " + message)

func _check_follow() -> void:
	var final_positions: Array[Vector2] = []
	for fps in [30, 60, 120]:
		for extent in [240.0, 420.0, 800.0]:
			var gaps: Array[float] = []
			for speed in [0.2, 3.0]:
				var d = Drag.new()
				d.begin(Vector2.ZERO)
				var target := Vector2.ZERO
				for f in fps:
					target.x = speed * extent * float(f + 1) / fps
					var at: Vector2 = d.follow_pointer(1.0 / fps, target, Vector2.ONE * extent)
					d.update(1.0 / fps, at, Vector2.ONE * extent)
				gaps.append(target.distance_to(d.follow_position) / extent)
				var before: Vector2 = d.follow_position
				d.follow_pointer(1.0 / fps, target - Vector2(extent * 0.15, 0), Vector2.ONE * extent)
				_check(d.follow_position.distance_to(before) < extent * 0.15, "reversal snapped position")
				var minimum_tilt := 0.0
				for f in fps * 2:
					var at: Vector2 = d.follow_pointer(1.0 / fps, target, Vector2.ONE * extent)
					d.update(1.0 / fps, at, Vector2.ONE * extent)
					minimum_tilt = minf(minimum_tilt, d.tilt)
				_check(d.follow_position.distance_to(target) < 0.01, "stationary cursor not caught")
				if speed > 1.0: _check(minimum_tilt < deg_to_rad(-1.0), "fast stop lost rebound")
				final_positions.append(d.follow_position / extent)
				var paused: Vector2 = d.follow_position
				d.release()
				d.follow_pointer(0.1, Vector2.ZERO, Vector2.ONE * extent)
				_check(d.follow_position == paused, "released pet still chased cursor")
			_check(gaps[0] < 0.04 and gaps[1] > 0.12 and gaps[1] < 0.5, "slow/fast lag not distinct")
			print("FOLLOW %d FPS size %.0f: slow gap %.3f, fast gap %.3f window heights" % [fps, extent, gaps[0], gaps[1]])
	for i in range(6, final_positions.size()):
		_check(final_positions[i].distance_to(final_positions[i % 6]) < 0.0001, "frame rate / size changed catch-up endpoint")

func _check_bending() -> void:
	var rig = preload("res://scripts/drag_pose.gd")
	for angle in [-0.12, 0.0, 0.12]:
		for stretch in [-0.025, 0.14]:
			for y in [1100, 1160, 1250, 1290]:
				var p := Vector2(870, y) - Vector2(1024, 1024)
				_check(rig.bend_point(p, angle, stretch) == p, "head / neck / scarf stretched")
			var boot_a := Vector2(900, 1800) - Vector2(1024, 1024)
			var boot_b := Vector2(1080, 2000) - Vector2(1024, 1024)
			_check(absf(rig.bend_point(boot_a, angle, stretch).distance_to(rig.bend_point(boot_b, angle, stretch)) - boot_a.distance_to(boot_b)) < 0.001, "boot length changed by torso deformation")
	var waist := Vector2(1030, 1425) - Vector2(1024, 1024)
	var lifted: Vector2 = rig.bend_point(waist, 0.0, 0.12)
	_check(lifted.y > waist.y + 10.0 and lifted.x < waist.x - 8.0, "pickup has no visible torso strain")

func _check_progressive_pull() -> void:
	var speeds: Array[float] = []
	var leans: Array[float] = []
	for distance in [0.05, 0.2, 0.5]:
		var d = Drag.new()
		d.begin(Vector2.ZERO)
		var target := Vector2(420.0 * distance, 0)
		d.pointer_previous = target
		for i in 6: d.follow_pointer(1.0 / 240.0, target, Vector2(420, 420))
		speeds.append(d.follow_velocity.x)
		# Hold the same stationary-pointer gap to isolate lean from travel speed.
		for i in 60: d.update(1.0 / 60.0, Vector2.ZERO, Vector2(420, 420))
		leans.append(d.tilt)
	_check(speeds[0] < speeds[1] and speeds[1] < speeds[2], "larger gap did not pull faster")
	_check(leans[0] < leans[1] and leans[1] < leans[2], "larger stationary gap did not lean more")
	_check(speeds[2] / 0.5 > speeds[0] / 0.05, "spring is not progressive")
	print("PROGRESSIVE: speeds %s, leans %s" % [speeds, leans])
	var spring = Drag.new()
	spring.begin(Vector2.ZERO)
	var stop := Vector2(210, 0)
	spring.pointer_previous = stop
	var overshoot := 0.0
	var crossings := 0
	var side := 1
	for i in 720:
		var at: Vector2 = spring.follow_pointer(1.0 / 240.0, stop, Vector2(420, 420))
		overshoot = maxf(overshoot, at.x - stop.x)
		var delta := stop.x - at.x
		if absf(delta) > 0.42 and signf(delta) != side:
			crossings += 1
			side = int(signf(delta))
	_check(overshoot > 0.5 and overshoot < 420 * 0.08, "B spring needs one small positional overshoot")
	_check(crossings == 1, "B spring bounced repeatedly instead of settling")
	_check(spring.follow_position.distance_to(stop) < 0.01, "B spring stopped away from cursor")
	print("B SPRING: %.2f px overshoot at 420 px size; %d visible crossing" % [overshoot, crossings])
	for fps in [30, 60, 120]:
		var d = Drag.new()
		d.begin(Vector2.ZERO)
		var peak_stretch := 0.0
		for f in fps:
			d.update(1.0 / fps, Vector2.ZERO, Vector2(420, 420))
			peak_stretch = maxf(peak_stretch, d.stretch)
		_check(peak_stretch > 0.06 and peak_stretch < 0.15, "pickup strain missing or excessive")
		_check(d.stretch > 0.02 and d.stretch < peak_stretch * 0.7, "pickup did not settle into light hanging shape")
		d.cancel()
		_check(d.pull == Vector2.ZERO and d.stretch == 0.0, "reset kept spring strain")
