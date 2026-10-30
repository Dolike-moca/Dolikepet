extends RefCounted
## Discrete user-facing talk frequency. Saved legacy intervals remain valid.
const MINUTES := [120, 60, 30, 15, 5]
const NAMES := ["很少", "偶尔", "适中", "经常", "频繁"]

static func nearest(minutes: float) -> int:
	if not is_finite(minutes): return 1
	var best := 1
	var distance := INF
	for index in MINUTES.size():
		var difference := absf(float(MINUTES[index]) - minutes)
		if difference < distance:
			best = index
			distance = difference
	return best

static func minute_at(index: int) -> int:
	return int(MINUTES[clampi(index, 0, MINUTES.size() - 1)])

static func label_at(index: int) -> String:
	return str(NAMES[clampi(index, 0, NAMES.size() - 1)])
