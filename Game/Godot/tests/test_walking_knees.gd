extends SceneTree
const Leg = preload("res://scripts/walking_leg.gd")
var failures := 0
var checks := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("WALK KNEES: " + message)

func _bottom(points: PackedVector2Array) -> float:
	var y := -INF
	for point in points:
		y = maxf(y, point.y)
	return y

func _knee_angle(points: PackedVector2Array) -> float:
	return (points[1] - points[0]).angle_to(points[2] - points[1])

func _initialize() -> void:
	var leg = Leg.new()
	var contours: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/sitting-boot-contours.json")).boots
	leg.setup(contours)
	var contact_ok := true
	var boots_rigid := true
	var hip_stable := true
	var smooth := true
	var rest_exact := true
	for id in Leg.HIPS:
		var sole: PackedVector2Array = leg.soles[id]
		var hip: Vector2 = Leg.HIPS[id]
		var knee: Vector2 = Leg.KNEES[id]
		var ankle := Vector2(1055, 1885) if id == "ArtMesh22" else Vector2(805, 1870)
		ankle -= Vector2(1024, 1024)
		var landmarks := PackedVector2Array([hip, knee, ankle])
		var neutral_angle := _knee_angle(landmarks)
		var bent := leg.deform_points(id, landmarks, Transform2D.IDENTITY, 0.0, 1.0, -5.2)
		var difference := rad_to_deg(wrapf(_knee_angle(bent) - neutral_angle, -PI, PI))
		print("%s additional knee flex: %.2f degrees" % [id, difference])
		_check(difference < -3.0 and difference > -12.0, "missing or excessive knee bend: " + id)
		var lifted := leg.deform_points(id, sole, Transform2D.IDENTITY, 0.0, 1.0, -5.2)
		var clearance := _bottom(sole) - (_bottom(lifted) - 5.2)
		_check(clearance > 8.0 and clearance < 16.0, "swing foot clearance: " + id)
		for weight in [0.0, 0.25, 0.5, 1.0]:
			var previous := PackedVector2Array()
			# Include a breathing scale and small body rotation.
			for body in [Transform2D.IDENTITY, Transform2D(0.004, Vector2(1.002, 1.002), 0.0, Vector2(0.3, -0.6))]:
				var raw: PackedVector2Array = body * sole
				var base_y := _bottom(raw)
				for degree in 361:
					var phase := deg_to_rad(degree)
					var bounce: float = -5.2 * pow(cos(phase), 2.0) * weight
					var actual := leg.deform_points(id, raw, body, phase, weight, bounce)
					var contact_y: float = _bottom(actual) + bounce
					if cos(phase) <= 0.0:
						contact_ok = contact_ok and absf(contact_y - base_y) < 0.02
					else:
						contact_ok = contact_ok and contact_y <= base_y + 0.02
					# All outline points are below the cuff: one rigid boot.
					for i in range(1, actual.size()):
						boots_rigid = boots_rigid and absf(
							actual[0].distance_to(actual[i]) - raw[0].distance_to(raw[i])) < 0.02
					var h := leg.deform_points(id, PackedVector2Array([body * hip]),
						body, phase, weight, bounce)
					hip_stable = hip_stable and h[0].distance_to(body * hip) < 0.001
					if weight == 0.0:
						rest_exact = rest_exact and actual == raw
					if previous.size() == actual.size():
						for i in actual.size():
							smooth = smooth and actual[i].distance_to(previous[i]) < 3.0
					previous = actual
				previous = PackedVector2Array()
	_check(contact_ok, "support foot floated or swing foot crossed the ground")
	_check(boots_rigid, "boot shape stretched during knee deformation")
	_check(hip_stable, "leg detached at hip")
	_check(smooth, "foot snapped at lift/contact/phase wrap")
	_check(rest_exact, "resting leg retained deformation")
	print("WALK KNEES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
