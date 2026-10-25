extends Control
## The same bounded, click-through drawing is used in the desktop and preview.
const CANVAS := Vector2(320,254)
const INK := Color("f4eaff")
const LILAC := Color("c49aff")
const GOLD := Color("ffd98d")
const SOUP := Color("92c84b")
var font := SystemFont.new()
var data := {"active":false,"streak":0,"total":0,"best":0,"delta":0,"bonus":0,
	"base_points":0,"scored_bounces":0,"bounce_count":0,
	"revision":0,"phase":"idle","remaining":0.0,"message":"撞边后接住，自动开始"}
var event_age := 10.0
var revision := 0
var displayed_game := "catch"
var fade := 1.0

func _init() -> void:
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	font.font_weight = 600
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = CANVAS

func update_score(value: Dictionary, dt: float) -> void:
	data = value
	if revision != int(data.revision) or displayed_game!=str(data.get("game","catch")):
		revision = data.revision; event_age = 0.0
	else: event_age += maxf(0.0,dt)
	displayed_game = str(data.get("game","catch"))
	fade = clampf(float(data.get("opacity",1.0)),0.0,1.0)
	queue_redraw()

func strength() -> float:
	return clampf(log(float(data.streak)+1.0)/log(41.0),0.0,1.0)

func _text(text: String, at: Vector2, pixels: int, color: Color, width := 270.0, centered := false) -> void:
	while pixels>10 and font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x>width:
		pixels -= 1
	if centered: at.x -= font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x*0.5
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,Color(color,color.a*fade))

func _panel(rect: Rect2, color: Color, radius: int, border := Color.TRANSPARENT) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color,color.a*fade)
	style.set_corner_radius_all(radius)
	if border.a>0.0:
		style.border_color = Color(border,border.a*fade); style.set_border_width_all(1)
	draw_style_box(style,rect)

func _star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 8:
		points.append(center+Vector2.from_angle(i*TAU/8-PI/2)*radius*(1.0 if i%2==0 else 0.28))
	draw_colored_polygon(points,color)

func _draw() -> void:
	var power := strength()
	var milestone: bool = int(data.bonus)>0
	var reward_color := SOUP if data.get("game","catch")=="juggle" else GOLD
	var accent := reward_color if milestone else LILAC
	var flash := maxf(0.0,1.0-event_age/0.8) if int(data.delta)>0 else 0.0
	_panel(Rect2(10,30,300,214),Color("241c32"),18,Color("59446f"))
	_panel(Rect2(10,30,300,214),Color(accent,flash*(0.025+power*0.045)),18)
	_text("猫猫颠锅" if data.get("game","catch")=="juggle" else "猫猫抛接",Vector2(28,60),16,INK)
	_text("最高  %d"%data.best,Vector2(174,60),13,Color("baa8ce"),118)
	_text("本轮",Vector2(28,88),13,Color("baa8ce"))
	_text(str(data.total),Vector2(72,90),23,INK,218)
	var blessing_age := float(data.get("blessing_age",-10.0))-0.7
	var blessing_alpha := smoothstep(0.0,0.16,blessing_age)*(1.0-smoothstep(1.10,1.50,blessing_age)) if blessing_age>=0.0 else 0.0
	var panel_fade := fade
	fade *= 1.0-blessing_alpha
	# Stronger pulses and stars remain inside a fixed 320 x 254 native window.
	var pop := sin(minf(event_age/0.28,1.0)*PI)*(0.10+power*0.20) if event_age<0.28 else 0.0
	var pixels := int(minf(88.0,(44.0+power*26.0)*(1.0+pop)))
	var reward_alpha := 0.0
	if milestone:
		reward_alpha = 1.0 if data.phase=="caught" else 1.0-smoothstep(0.85,1.35,event_age)
	_text(str(data.streak),Vector2(216,166),pixels,Color(LILAC,1.0-reward_alpha),158,true)
	if reward_alpha>0.0:
		_text("+%d"%data.bonus,Vector2(216,166),pixels,Color(reward_color,reward_alpha),158,true)
	_text("连击奖励" if reward_alpha>0.5 else "连  击",Vector2(216,188),13,Color("baa8ce"),100,true)
	_text("基础分",Vector2(78,121),12,Color("baa8ce"),92,true)
	# A fixed-size base award is independent of the streak and its effects.
	# Keep both awards readable while held; release lets the pop-up fade out.
	var base_alpha := 1.0 if data.phase=="caught" else 1.0-smoothstep(0.85,1.35,event_age)
	if int(data.base_points)>0 and base_alpha>0.0:
		_text("+%d"%data.base_points,Vector2(78,158-minf(event_age,0.6)*8),24,Color(INK,base_alpha),92,true)
	else: _text("—",Vector2(78,153),20,Color("baa8ce"),92,true)
	_text("弹 %d 次"%data.scored_bounces if data.active else "本次弹边",Vector2(78,181),12,Color("baa8ce"),92,true)
	if flash>0.0:
		var count := 4+int(power*10)
		for i in count:
			var angle := TAU*i/count-PI/2
			var radius := 43.0+(1.0-flash)*(16.0+power*25.0)
			var center := Vector2(216,147)+Vector2(cos(angle)*0.82,sin(angle)*0.48)*radius
			_star(center,2.0+power*3.5,Color(accent,flash*fade*0.9))
	if reward_alpha>0.0:
		_text("%d 连击"%data.streak,Vector2(160,23),17,Color(reward_color,reward_alpha),290,true)
	fade = panel_fade
	if blessing_alpha>0.0: _blessing(blessing_age,blessing_alpha)
	_text(str(data.message),Vector2(160,207),13,INK,264,true)
	_panel(Rect2(28,221,264,5),Color("43334f"),2)
	if data.phase=="caught":
		var portion := clampf(float(data.remaining)/3.0,0.0,1.0)
		_panel(Rect2(28,221,maxf(1.0,264*portion),5),GOLD if portion<0.34 else LILAC,2)
	else:
		_text("双击查看计分板",Vector2(160,236),11,Color("baa8ce"),264,true)

func _blessing(age: float, alpha: float) -> void:
	var at := Vector2(160,157-5.0*smoothstep(0,1.5,age))
	for offset in [Vector2(-1,0),Vector2(1,0),Vector2(0,-1),Vector2(0,1)]:
		_text("慈父的赐福",at+offset,27,Color("d2e9a5",alpha*0.75),270,true)
	_text("慈父的赐福",at,27,Color(SOUP,alpha),270,true)
	for i in 6:
		var t := clampf((age-i*0.05)/1.2,0,1)
		var p := Vector2(42+i*46,185-t*66+sin(i*2.2+t*3)*4)
		var radius := (3.0+float(i%3)*1.5)*smoothstep(0,0.16,t)
		var a := alpha*fade*(1.0-smoothstep(0.68,1,t))
		draw_circle(p,radius,Color(SOUP,a*0.30))
		draw_arc(p,radius,0,TAU,20,Color(SOUP,a*0.8),1.2,true)
		if t>0.68: draw_arc(p,radius+(t-0.68)*17,0,TAU,20,Color(SOUP,a*0.5),1.0,true)
