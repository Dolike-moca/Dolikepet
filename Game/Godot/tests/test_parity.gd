extends SceneTree

const Behavior = preload("res://scripts/pet_behavior.gd")
const Secondary = preload("res://scripts/secondary_deformation.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/parity-fixtures.json"))
	var controller = Behavior.new()
	controller.automatic_blinks = false
	var frame := 0
	for sample in fixture.frames:
		if sample.action != "":
			controller.command(sample.action)
		var actual: Dictionary = controller.update(sample.dt,
			Vector2(sample.sample.x, sample.sample.y), Vector2(210, 170), 420, sample.sample.active)
		for key in sample.expected:
			_check(absf(actual[key] - sample.expected[key]) < 0.00003, "frame %d %s" % [frame, key])
		_check(actual.headX == 0.0 and actual.headY == 0.0 and actual.bodyY == 0.0,
			"no neck translation")
		frame += 1
	var deformer = Secondary.new()
	for id in fixture.neutral:
		deformer.reference[id] = _pixels(fixture.neutral[id])
	for id in ["ArtMesh18", "ArtMesh24"]:
		deformer.samplers[id] = deformer._sample_triangle(deformer.reference[id])
	for sample in fixture.cases:
		var head: Transform2D = deformer._affine("ArtMesh18", _pixels(sample.raw.ArtMesh18))
		var body: Transform2D = deformer._affine("ArtMesh24", _pixels(sample.raw.ArtMesh24))
		for id in Secondary.HAIR.keys() + ["ArtMesh5"]:
			var actual: PackedVector2Array = deformer.deform_points(id, _pixels(sample.raw[id]), sample.pose, head, body)
			var expected := _pixels(sample.expected[id])
			for i in actual.size():
				_check(actual[i].distance_to(expected[i]) < 0.001, "mesh %s vertex %d" % [id, i])
	print("PARITY: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _pixels(core: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(0, core.size(), 2):
		result.append(Vector2(core[i] * 2048.0, -core[i + 1] * 2048.0))
	return result

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 20:
			printerr("FAIL: " + label)
