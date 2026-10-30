extends RefCounted
## Shared reading limits; window-specific input and alpha stay in each surface.
const SHORT := 30.0
const LONG := 60.0
const DRAFT := 120.0
const LONG_TEXT := 120
const FADE := 3.0
const RESTORE := 0.2

static func idle_seconds(text: String, has_draft: bool) -> float:
	if has_draft: return DRAFT
	var characters := 0
	for character in text:
		if not character.strip_edges().is_empty(): characters += 1
		if characters >= LONG_TEXT: return LONG
	return SHORT
