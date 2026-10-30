extends RefCounted
## One presentation setting shared by text reveal and speaking animation.
const DEFAULT := 2
const FACTORS := [0.6, 0.8, 1.0, 1.25, 1.6]
const LABELS := ["慢", "较慢", "正常", "较快", "快"]
const BASE_CHARACTERS_PER_SECOND := 18.0

static func factor(index: int) -> float:
	return FACTORS[clampi(index, 0, FACTORS.size() - 1)]

static func label_at(index: int) -> String:
	return LABELS[clampi(index, 0, LABELS.size() - 1)]

static func chars_per_second(index: int) -> float:
	return BASE_CHARACTERS_PER_SECOND * factor(index)

static func characters_per_second(index: int) -> float:
	return chars_per_second(index)

static func spoken_seconds(text: String) -> float:
	# A brief closing tail follows the final revealed letter. The same normal-
	# speed duration is consumed by both mouth clocks after multiplying dt.
	return maxf(0.8, text.strip_edges().length() / BASE_CHARACTERS_PER_SECOND + 0.55)

static func safe_factor(value: float) -> float:
	return clampf(value, FACTORS[0], FACTORS[-1]) if is_finite(value) else 1.0
