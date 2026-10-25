extends RefCounted
## The same relative curve is used for every user-selected full capacity.
const MB := 1048576
const GB := 1073741824
const DEFAULT := GB
const MAXIMUM := 1024 * GB
const RATIOS := [0.0, 0.001, 0.01, 0.1, 0.5, 1.0]
const LEVELS := [0.0, 0.15, 0.30, 0.50, 0.75, 0.95]

static func sanitize(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return DEFAULT
	return clampi(int(value), MB, MAXIMUM)

static func level(bytes: int, capacity: int) -> float:
	if bytes <= 0: return 0.0
	var ratio := clampf(float(bytes) / sanitize(capacity), 0.0, 1.0)
	for i in range(1, RATIOS.size()):
		if ratio <= RATIOS[i]:
			return lerpf(LEVELS[i-1], LEVELS[i], inverse_lerp(RATIOS[i-1], RATIOS[i], ratio))
	return 0.95

static func caption(bytes: int) -> String:
	if bytes < 1024: return "%d B" % bytes
	if bytes < MB: return "%.1f KB" % (float(bytes)/1024.0)
	return "%.2f GB" % (float(bytes)/GB) if bytes >= GB else "%.1f MB" % (float(bytes)/MB)
