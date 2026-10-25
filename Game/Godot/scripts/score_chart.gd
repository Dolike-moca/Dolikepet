extends Control
var values: Array = []
var accent := Color("c49aff")
var font := SystemFont.new()
var caption := "单局累计得分 · 横轴为加分次数"

func _init() -> void:
	custom_minimum_size = Vector2(200,140)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font.font_names = PackedStringArray(["Microsoft YaHei UI"])

func set_values(points: Array, color: Color, text: String) -> void:
	values = points; accent = color; caption = text; queue_redraw()

func _draw() -> void:
	var box := Rect2(42,32,maxf(1.0,size.x-62),maxf(1.0,size.y-55))
	draw_string(font,Vector2(4,19),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("c6b9d7"))
	draw_line(box.position,Vector2(box.position.x,box.end.y),Color("574b65"))
	draw_line(Vector2(box.position.x,box.end.y),box.end,Color("574b65"))
	if values.is_empty():
		draw_string(font,box.position+Vector2(12,38),"暂无记录",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("c6b9d7")); return
	var peak := maxf(1.0,float(values.max()))
	draw_string(font,Vector2(0,box.position.y+6),str(int(peak)),HORIZONTAL_ALIGNMENT_LEFT,38,12,Color("c6b9d7"))
	draw_string(font,Vector2(22,box.end.y),"0",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("c6b9d7"))
	var points := PackedVector2Array([Vector2(box.position.x,box.end.y)])
	for i in values.size():
		points.append(Vector2(box.position.x+box.size.x*(i+1)/values.size(),box.end.y-box.size.y*float(values[i])/peak))
	draw_polyline(points,accent,2.5,true)
	draw_circle(points[-1],4.0,accent)
