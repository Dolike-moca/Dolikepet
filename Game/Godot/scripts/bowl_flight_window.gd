extends Window
var icon := Sprite2D.new()
func _init() -> void:
	title = "饭盆取食"
	borderless = true; transparent = true; transparent_bg = true
	always_on_top = true; transient = false; unfocusable = true; mouse_passthrough = true
	visible = false
func _ready() -> void:
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(icon)
func follow(food: Sprite2D, desktop_origin: Vector2) -> void:
	var transform := food.global_transform
	var rect := Rect2(food.offset-food.texture.get_size()*0.5,food.texture.get_size())
	var corners := [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var bounds := Rect2(transform*corners[0],Vector2.ZERO)
	for corner in corners: bounds = bounds.expand(transform*corner)
	var origin := (desktop_origin+bounds.position).floor()-Vector2(2,2)
	size = Vector2i(bounds.size.ceil())+Vector2i(6,6)
	position = Vector2i(origin)
	icon.texture = food.texture; icon.offset = food.offset
	icon.transform = transform
	icon.position += desktop_origin-origin
	icon.modulate.a = food.modulate.a
	show()
