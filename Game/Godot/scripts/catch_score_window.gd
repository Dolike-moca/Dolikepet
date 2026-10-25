extends Window
signal board_requested
const View = preload("res://scripts/catch_score_view.gd")
const Visibility = preload("res://scripts/score_visibility.gd")
var view = View.new()
var lifetime = Visibility.new()
var pointer_override := Vector2(-99999,-99999) # Deterministic fixture override.
var use_pointer_override := false
const HIT_RECT := Rect2(10,30,300,214)

func _init() -> void:
	title = "接猫挑战"
	borderless = true; transparent = true; transparent_bg = true
	always_on_top = true; transient = false; unfocusable = true; mouse_passthrough = false
	minimize_disabled = true; maximize_disabled = true
	size = Vector2i(View.CANVAS); visible = false

func _ready() -> void:
	add_child(view)
	mouse_passthrough_polygon = PackedVector2Array([Vector2(10,30),Vector2(310,30),Vector2(310,244),Vector2(10,244)])
	window_input.connect(_on_window_input)

func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT \
		and event.pressed and event.double_click and HIT_RECT.has_point(event.position):
		board_requested.emit()

func refresh(data: Dictionary, dt: float, screen: int) -> void:
	var pointer := pointer_override if use_pointer_override else Vector2(DisplayServer.mouse_get_position()-position)
	var inside := visible and HIT_RECT.has_point(pointer)
	var presented := data.duplicate()
	presented.opacity = lifetime.update(data,float(data.get("now",Time.get_ticks_msec()/1000.0)),inside)
	view.update_score(presented,dt)
	if view.fade<=0.0:
		if visible: hide()
		return
	var area := DisplayServer.screen_get_usable_rect(screen)
	var target := area.end-size-Vector2i(12,12)
	target.x = maxi(area.position.x,target.x); target.y = maxi(area.position.y,target.y)
	if position != target: position = target
	if not visible: show()
