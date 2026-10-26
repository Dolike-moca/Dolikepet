extends Window
signal files_received(paths: PackedStringArray)
signal opened
signal moved
signal hidden_by_user
signal struck_pet(impact: Dictionary)
signal intercepted
signal juggled(event: Dictionary)
signal juggling_ended(reason: String)
const Arrival = preload("res://scripts/bowl_arrival.gd")
const Impact = preload("res://scripts/bowl_impact.gd")
const Rebound = preload("res://scripts/bowl_rebound.gd")
const Capacity = preload("res://scripts/bowl_capacity.gd")
const JuggleFlight = preload("res://scripts/juggle_flight.gd")
const DesktopDrag = preload("res://scripts/desktop_drag.gd")
const ART = preload("res://assets/bowl/cauldron.png")
const USED := Rect2(50,91,1215,1046)
var sprite := Sprite2D.new()
var soup := ShaderMaterial.new()
var charge_aura := Sprite2D.new()
var aura_material := ShaderMaterial.new()
var pressed := false
var dragging := false
var pointer_start := Vector2i.ZERO
var position_start := Vector2i.ZERO
var at := Vector2.ZERO
var velocity := 0.0
var full_bytes := Capacity.DEFAULT
var total_bytes := 0
var fill := 0.0
var clock := 0.0
var slosh := 0.0
var art_scale := 1.0
var paused := false
var impact_target := Callable()
var drop_armed := false
var release_at := Vector2.ZERO
var last_cap_center := Vector2.INF
var rebound = Rebound.new()
var rest_size := Vector2i.ZERO
var margin := Vector2.ZERO
var silhouette := PackedVector2Array()
var source_hull := PackedVector2Array()
var arrival = Arrival.new()
var arrival_area := Rect2()
var juggle = JuggleFlight.new()
var drag_input = DesktopDrag.new()

func _init() -> void:
	title = "猫的饭盆 · 双击打开文件夹"
	borderless = true; transparent = true; transparent_bg = true
	always_on_top = true; unresizable = true; transient = false; unfocusable = true
	visible = false

func _ready() -> void:
	sprite.texture = ART; sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	soup.shader = preload("res://shaders/bowl_soup.gdshader")
	sprite.material = soup
	charge_aura.texture = ART; charge_aura.centered = false
	charge_aura.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	aura_material.shader = preload("res://shaders/bowl_charge.gdshader")
	charge_aura.material = aura_material; charge_aura.visible = false
	add_child(charge_aura)
	add_child(sprite)
	window_input.connect(_input_window)
	files_dropped.connect(func(paths): files_received.emit(paths))
	close_requested.connect(func(): end_juggle("关闭饭盆 · 本轮结束"); _release(); hide(); hidden_by_user.emit())
	focus_exited.connect(_release)
	visibility_changed.connect(func():
		if not visible: _release())

func fit_pet(pet_size: float) -> void:
	end_juggle("大小已调整 · 本轮结束")
	var old_bottom := at.y+rest_size.y if rest_size!=Vector2i.ZERO else float(position.y+size.y)
	rebound.cancel(); margin = Vector2.ZERO
	art_scale = pet_size*0.40/USED.size.y
	size = Vector2i((USED.size*art_scale+Vector2(8,8)).ceil())
	rest_size = size
	sprite.scale = Vector2.ONE*art_scale
	sprite.position = Vector2(4,4)-USED.position*art_scale
	position.y = int(old_bottom)-size.y
	at = Vector2(position)
	# Polygon follows the real silhouette; transparent corners remain clickable through.
	if source_hull.is_empty():
		# The source image is immutable. Read its alpha once, not on every frame
		# of pet scaling: repeated full-image readbacks stall desktop presentation.
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(ART.get_image(),0.06)
		# Full-image contours keep USED.position from being subtracted twice.
		var contours := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO,bitmap.get_size()),2.0)
		var all_points := PackedVector2Array()
		for contour in contours: all_points.append_array(contour)
		if not all_points.is_empty(): source_hull = Geometry2D.convex_hull(all_points)
	if not source_hull.is_empty():
		var points := PackedVector2Array()
		for point in source_hull: points.append(sprite.position+point*art_scale)
		# Win32 also uses this input polygon as a visual window region. Leave
		# two display pixels for edge filtering and retain all three pot feet.
		var padded := Geometry2D.offset_polygon(points,2.0,Geometry2D.JOIN_ROUND)
		silhouette = padded[0] if not padded.is_empty() else points
		mouse_passthrough_polygon = silhouette
	sprite.rotation = 0.0
	charge_aura.transform = sprite.transform

func set_charge(value: float) -> void:
	charge_aura.visible = value>0.0
	aura_material.set_shader_parameter("charge_glow",value)
	aura_material.set_shader_parameter("clock_time",clock)

func _art_pose(angle: float, grounded := false, shape := Vector2.ONE) -> void:
	# Expand the native window only during a rebound: rotating the old clipped
	# window would cut off handles/feet. Logical `at` keeps the resting origin.
	var padding := 0.35 if juggle.animating() else (0.14 if rebound.active() else 0.0)
	var wanted := Vector2.ONE*ceilf(maxf(rest_size.x,rest_size.y)*padding)
	if margin!=wanted:
		margin = wanted; size = rest_size+Vector2i(margin*2.0)
	var pivot := Vector2(4,4)+USED.size*art_scale*0.5
	var basis := Transform2D(angle,shape,0.0,Vector2.ZERO)
	var foot := Vector2(4,4)+(Vector2(620,1134)-USED.position)*art_scale
	# Squash around the contact foot, keeping the soup, outline and window
	# input region attached to the same transform as the cauldron sprite.
	var offset := (foot-pivot).rotated(angle)-basis.basis_xform(foot-pivot)
	if juggle.animating(): offset = Vector2.ZERO
	var points := PackedVector2Array()
	for point in silhouette: points.append(margin+pivot+basis.basis_xform(point-pivot)+offset)
	if grounded and not points.is_empty():
		var bottom := -INF
		for point in points: bottom = maxf(bottom,point.y)
		# Rock on the floor, not through it; retain the original upright margin.
		var rest_bottom := -INF
		for point in silhouette: rest_bottom = maxf(rest_bottom,point.y)
		var lift := margin.y+rest_bottom-bottom
		offset.y += lift
		for i in points.size(): points[i].y += lift
	sprite.rotation = angle
	sprite.scale = shape*art_scale
	sprite.position = margin+pivot-basis.basis_xform((USED.position+USED.size*0.5)*art_scale)+offset
	charge_aura.transform = sprite.transform
	if not points.is_empty():
		# Win32 uses this polygon as the visible region too. Give only the
		# charging halo extra room; collision geometry remains the pot itself.
		if juggle.glow>0.0:
			var halo := Geometry2D.offset_polygon(points,ceilf(72.0*art_scale),Geometry2D.JOIN_ROUND)
			mouse_passthrough_polygon = halo[0] if not halo.is_empty() else points
		else: mouse_passthrough_polygon = points
	position = Vector2i((at-margin).round())

func _cancel_rebound() -> void:
	rebound.cancel()
	if margin!=Vector2.ZERO or sprite.rotation!=0.0 or sprite.scale!=Vector2.ONE*art_scale: _art_pose(0.0)

func place(value: Vector2i) -> void:
	end_juggle("移动饭盆 · 本轮结束")
	cancel_arrival()
	_cancel_rebound()
	var screen := DisplayServer.get_screen_from_rect(Rect2i(value,size))
	if screen < 0: screen = DisplayServer.get_primary_screen()
	var area := DisplayServer.screen_get_usable_rect(screen)
	position = Vector2i(clampi(value.x,area.position.x,area.end.x-size.x),clampi(value.y,area.position.y,area.end.y-size.y))
	at = Vector2(position); velocity = 0.0
	drop_armed = false; last_cap_center = Vector2.INF

func surface_point() -> Vector2:
	return Vector2(position)+sprite.transform*Vector2(656,340)

func contains_drop_point(screen_point: Vector2) -> bool:
	if not visible or mode==Window.MODE_MINIMIZED: return false
	var local := screen_point-Vector2(position)
	return Rect2(Vector2.ZERO,Vector2(size)).has_point(local) \
		and Geometry2D.is_point_in_polygon(local,mouse_passthrough_polygon)

func receive_covered_drop(paths: PackedStringArray, screen_point: Vector2) -> bool:
	# The pet's transparent native window can be above this window. Forward
	# only a drop over the cauldron silhouette, never elsewhere on the pet.
	if paths.is_empty() or not contains_drop_point(screen_point): return false
	files_received.emit(paths)
	return true

func _input_window(event: InputEvent) -> void:
	if event is InputEventMouseMotion and pressed:
		_update_drag_pointer(position+Vector2i(event.position),true)
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed and pressed and not event.double_click: return
	if event.pressed:
		end_juggle("拿起饭盆 · 本轮结束")
		cancel_arrival(); intercepted.emit()
	if event.pressed and event.double_click:
		_release(); drag_input.release_capture(self); opened.emit(); return
	if event.pressed:
		drag_input.begin(self)
		_cancel_rebound()
		pressed = true; pointer_start = position+Vector2i(event.position); position_start = position
		at = Vector2(position); velocity = 0.0
		drop_armed = false; last_cap_center = Vector2.INF
	else:
		if pressed: _update_drag_pointer(position+Vector2i(event.position),true)
		_release()

func _release() -> void:
	if not pressed and not dragging: return
	var was_dragging := dragging
	pressed = false; dragging = false
	drag_input.release_capture(self)
	if was_dragging:
		arm_drop()
		moved.emit()
	drag_input.repair_cache(self)

func arm_drop() -> void:
	_cancel_rebound()
	release_at = at; drop_armed = true; last_cap_center = Vector2.INF

func begin_arrival(target_x: float, area: Rect2) -> void:
	end_juggle("重新召唤 · 本轮结束")
	_cancel_rebound()
	arrival_area = area
	# Lock the landing column now. A later pet drag never changes it.
	at = Vector2(clampf(target_x-_feet()[1].x,area.position.x,area.end.x-rest_size.x),area.position.y)
	velocity = 0.0; drop_armed = false; last_cap_center = Vector2.INF
	arrival.start(); visible = true
	_arrival_pose(Vector2(0,-rest_size.y))

func cancel_arrival() -> void:
	if not arrival.active(): return
	arrival.cancel(); mouse_passthrough = false; _art_pose(0.0)

func _arrival_pose(offset: Vector2) -> void:
	# The window stays on this screen; only its contents slide into view.
	# This prevents an upper monitor from showing the hidden part of the pot.
	sprite.position = Vector2(4,4)-USED.position*art_scale+offset
	var points := PackedVector2Array()
	for point in silhouette: points.append(point+offset)
	var clip := PackedVector2Array([Vector2.ZERO,Vector2(rest_size.x,0),Vector2(rest_size),Vector2(0,rest_size.y)])
	var visible_parts := Geometry2D.intersect_polygons(points,clip)
	mouse_passthrough = visible_parts.is_empty()
	if not visible_parts.is_empty(): mouse_passthrough_polygon = visible_parts[0]
	position = Vector2i(at.round())

func _advance_arrival(dt: float) -> void:
	var step: Dictionary = arrival.update(dt,rest_size.y)
	_arrival_pose(step.offset)
	if step.release:
		mouse_passthrough = false; _art_pose(0.0); arm_drop()

func _feet() -> PackedVector2Array:
	var result := PackedVector2Array()
	# Actual three feet, excluding the transparent gaps and side handles.
	for point in [Vector2(280,1060),Vector2(620,1134),Vector2(980,1080)]:
		result.append(sprite.transform*point-margin)
	return result

func _advance_fall(dt: float, area: Rect2) -> void:
	var floor_y := area.end.y-rest_size.y
	if juggle.animating():
		_advance_juggle(dt,area)
		return
	if rebound.active():
		var before := at
		var step: Dictionary = rebound.update(dt)
		at = step.at; slosh = step.slosh
		_art_pose(step.angle,step.grounded,step.shape)
		if not step.grounded and _try_juggle_start(before,at,area,dt): return
		if step.finished: velocity = 0.0; moved.emit()
	elif at.y<floor_y or absf(velocity)>0.1:
		velocity += Impact.GRAVITY*dt
		var next := at+Vector2(0,velocity*dt)
		if _try_juggle_start(at,next,area,dt): return
		var target: Dictionary = impact_target.call() if drop_armed and impact_target.is_valid() else {}
		var hit := {}
		if not target.is_empty() and velocity>0.0:
			var cap: PackedVector2Array = target.cap
			var center := Vector2.ZERO
			for point in cap: center += point/float(cap.size())
			var change := center-last_cap_center if last_cap_center.is_finite() else Vector2.ZERO
			last_cap_center = center
			hit = Impact.sweep(at,next,_feet(),cap,change)
			if not hit.is_empty():
				at = hit.position; drop_armed = false
				hit.kind = Impact.classify(maxf(0.0,at.y-release_at.y),velocity,target.extent)
				hit.speed = velocity; hit.height = maxf(0.0,at.y-release_at.y)/target.extent
				hit.dizzy_seconds = Impact.dizzy_seconds(hit.height)
				rebound.start(at,Vector2(rest_size),cap,area,hit.height)
				_art_pose(0.0)
				velocity = 0.0
				if not hit.kind.is_empty(): struck_pet.emit(hit)
		if hit.is_empty():
			at = next
			if at.y>=floor_y:
				at.y = floor_y; drop_armed = false
				velocity = -velocity*0.18 if velocity>100.0 else 0.0
				moved.emit()
	position = Vector2i((at-margin).round())

func _try_juggle_start(before: Vector2, after: Vector2, area: Rect2, dt := 1.0/60.0) -> bool:
	if not impact_target.is_valid(): return false
	var target: Dictionary = impact_target.call()
	if not target.get("juggle",false): return false
	var head_speed: Vector2 = target.get("velocity",Vector2.ZERO)
	var hit := JuggleFlight.sweep(before,after,_pot_polygon(),target.cap,head_speed*dt)
	if hit.is_empty(): return false
	# If this step also reaches the floor, only an earlier head contact counts.
	var floor_y := area.end.y-rest_size.y
	if after.y>=floor_y and float(hit.fraction)>=(floor_y-before.y)/maxf(0.00001,after.y-before.y): return false
	at = hit.position
	var pivot := Vector2(4,4)+USED.size*art_scale*0.5
	var outline := PackedVector2Array()
	for point in silhouette: outline.append(point-pivot)
	var contact := {"point":hit.point,"normal":hit.normal,"angle":sprite.rotation,
		"velocity":(after-before)/maxf(0.0001,dt),"head_velocity":head_speed}
	rebound.cancel(); drop_armed = false; velocity = 0.0
	juggle.start(at+pivot,Vector2(rest_size),outline,area,contact)
	_art_pose(juggle.angle)
	juggled.emit({"walls":0,"boosted":false,"point":hit.point})
	return true

func _pot_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	var pivot := Vector2(4,4)+USED.size*art_scale*0.5
	for point in silhouette: points.append(pivot+(point-pivot).rotated(sprite.rotation))
	return points

func _advance_juggle(dt: float, area: Rect2) -> void:
	juggle.area = area
	var target: Dictionary = impact_target.call() if impact_target.is_valid() else {}
	var events: Array = juggle.advance(dt,target)
	var pivot := Vector2(4,4)+USED.size*art_scale*0.5
	at = juggle.center-pivot
	_art_pose(juggle.angle,false,juggle.shape)
	set_charge(juggle.glow)
	for event in events:
		if event.type=="head": juggled.emit(event)
		elif event.type=="floor":
			juggling_ended.emit("锅落地 · 本轮结束"); moved.emit()
		elif event.type=="rest": moved.emit()

func end_juggle(reason: String) -> void:
	if not juggle.animating(): return
	var was_playing: bool = juggle.active()
	juggle.cancel(); velocity = 0.0; drop_armed = false
	set_charge(0.0)
	var area := DisplayServer.screen_get_usable_rect(current_screen)
	at.x = clampf(at.x,area.position.x,area.end.x-rest_size.x)
	at.y = clampf(at.y,area.position.y,area.end.y-rest_size.y)
	_art_pose(0.0)
	if was_playing: juggling_ended.emit(reason)

func _process(delta: float) -> void:
	if not visible: return
	var dt := minf(delta,0.05)
	if pressed or dragging:
		_update_drag_pointer(DisplayServer.mouse_get_position(),drag_input.held(self))
	if not pressed and not paused:
		if arrival.active(): _advance_arrival(dt)
		else:
			var area := DisplayServer.screen_get_usable_rect(current_screen)
			_advance_fall(dt,Rect2(area))
	if paused: return
	clock += dt
	fill = move_toward(fill,Capacity.level(total_bytes,full_bytes),dt*0.22)
	slosh = lerpf(slosh,0.0,1.0-exp(-dt*4.0))
	soup.set_shader_parameter("fullness",fill)
	soup.set_shader_parameter("clock_time",clock)
	soup.set_shader_parameter("slosh",slosh)
	soup.set_shader_parameter("ripple",1.0)

func _update_drag_pointer(pointer: Vector2i, down: bool) -> void:
	if not pressed and not dragging: return
	if not down or not pressed:
		_release()
	elif pointer.distance_to(pointer_start)>5.0 or dragging:
		dragging = true
		var target := position_start+pointer-pointer_start
		var dx := target.x-position.x
		place(target)
		slosh = lerpf(slosh,clampf(-dx*0.002,-0.12,0.12),0.25)
