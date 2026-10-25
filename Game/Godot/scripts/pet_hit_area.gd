extends RefCounted
## Hit exactly the displayed pixels, including animated limbs and transparent gaps.
const ALPHA_THRESHOLD := 0.08
var image: Image
var size := Vector2.ZERO

func capture(frame: Image, viewport_size: Vector2) -> void:
	image = frame
	size = viewport_size

func contains(point: Vector2, viewport_size: Vector2) -> bool:
	if image == null or image.is_empty() or size != viewport_size: return false
	if not Rect2(Vector2.ZERO, size).has_point(point): return false
	var pixel := Vector2i((point * Vector2(image.get_size()) / size).floor())
	return image.get_pixelv(pixel).a >= ALPHA_THRESHOLD
