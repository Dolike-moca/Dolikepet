extends RefCounted
## Presentation-only typewriter. Appended stream chunks retain their progress.
const MAX_CHARACTERS := 8000
var full_text := ""
var _shown := 0.0

func clear() -> void:
	full_text = ""; _shown = 0.0

func replace(text: String) -> void:
	full_text = text.left(MAX_CHARACTERS); _shown = 0.0

func set_text(text: String) -> void:
	var next := text.left(MAX_CHARACTERS)
	if next.begins_with(full_text) or full_text.begins_with(next):
		pass
	elif next.begins_with(full_text.strip_edges()) or full_text.strip_edges().begins_with(next):
		# Completion may trim streamed whitespace; preserve the drawn prefix.
		_shown = maxf(0.0, _shown - (full_text.length() - full_text.strip_edges(true, false).length()))
	else:
		# A changed turn or corrected response cannot inherit unrelated letters.
		_shown = 0.0
	full_text = next
	_shown = minf(_shown, full_text.length())

func advance(dt: float, characters_per_second: float) -> String:
	if is_finite(dt) and is_finite(characters_per_second):
		_shown = minf(float(full_text.length()), _shown + clampf(dt, 0.0, 0.25) * maxf(0.0, characters_per_second))
	return visible_text()

func visible_text() -> String:
	return full_text.left(int(_shown))

func done() -> bool:
	return int(_shown) >= full_text.length()

func finish() -> void:
	_shown = float(full_text.length())

func seek(characters: int) -> void:
	_shown = clampf(float(characters), 0.0, float(full_text.length()))
