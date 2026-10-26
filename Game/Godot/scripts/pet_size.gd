extends RefCounted
## User-facing size choices. Animation may pass between them, saved sizes may not.
const BASE := 300
const PERCENTS := [50, 75, 100, 125, 150, 175, 200]
const PIXELS := [150, 225, 300, 375, 450, 525, 600]

static func nearest(pixels: float) -> int:
	if not is_finite(pixels): return BASE
	var best: int = BASE
	var distance := INF
	for choice in PIXELS:
		if absf(choice-pixels) < distance:
			best = choice
			distance = absf(choice-pixels)
	return best

static func step(pixels: int, direction: int) -> int:
	return PIXELS[clampi(PIXELS.find(nearest(pixels))+signi(direction),0,PIXELS.size()-1)]
