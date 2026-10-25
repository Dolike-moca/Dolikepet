extends Window
const Scores = preload("res://scripts/game_scores.gd")
const Chart = preload("res://scripts/score_chart.gd")
const PAGE_SIZE := 50
var ledger
var tabs := TabContainer.new()
var game_filter := OptionButton.new()
var sort_filter := OptionButton.new()
var game_rank := OptionButton.new()
var games := ["","catch","juggle"]
var rows := ItemList.new()
var details := RichTextLabel.new()
var chart = Chart.new()
var trend = Chart.new()
var ranking := RichTextLabel.new()
var stats := Label.new()
var notice := Label.new()
var page_label := Label.new()
var previous := Button.new()
var next := Button.new()
var listed: Array = []
var page := 0
var dirty := false

func _init() -> void:
	title = "Dolike · 计分板"
	size = Vector2i(880,720); min_size = Vector2i(720,600)
	visible = false; transient = false; exclusive = false
	transparent = false; transparent_bg = false; borderless = false

func _ready() -> void:
	var panel := PanelContainer.new(); add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var font := SystemFont.new(); font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	theme.default_font = font; theme.default_font_size = 16
	var background := StyleBoxFlat.new(); background.bg_color = Color("231e2c")
	theme.set_stylebox("panel","PanelContainer",background)
	panel.theme = theme
	var margin := MarginContainer.new(); panel.add_child(margin)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	var layout := VBoxContainer.new(); layout.add_theme_constant_override("separation",12); margin.add_child(layout)
	var heading := Label.new(); heading.text = "一起玩的每一局"; heading.add_theme_font_size_override("font_size",24); layout.add_child(heading)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; notice.add_theme_font_size_override("font_size",13); layout.add_child(notice)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL; layout.add_child(tabs)
	var recent := VBoxContainer.new(); recent.name = "最近游戏"; tabs.add_child(recent)
	var filters := HBoxContainer.new(); recent.add_child(filters)
	for text in ["全部游戏","猫猫抛接","猫猫颠锅"]: game_filter.add_item(text)
	for text in ["最近优先","得分从高到低","连击从高到低"]: sort_filter.add_item(text)
	filters.add_child(game_filter); filters.add_child(sort_filter)
	previous.text = "上一页"; next.text = "下一页"
	filters.add_child(previous); filters.add_child(page_label); filters.add_child(next)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; recent.add_child(split)
	rows.custom_minimum_size.x = 280; rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_font_size_override("font_size",14)
	rows.add_theme_constant_override("v_separation",12); split.add_child(rows)
	var right := VBoxContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; split.add_child(right)
	right.add_child(chart); details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.bbcode_enabled = true; details.selection_enabled = true; right.add_child(details)
	var records := VBoxContainer.new(); records.name = "最高成绩"; tabs.add_child(records)
	for text in ["猫猫抛接","猫猫颠锅"]: game_rank.add_item(text)
	records.add_child(game_rank)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; records.add_child(stats)
	records.add_child(trend)
	ranking.bbcode_enabled = true; ranking.selection_enabled = true; ranking.size_flags_vertical = Control.SIZE_EXPAND_FILL; records.add_child(ranking)
	var footer := Label.new(); footer.text = "记录保存在本机 · 双击右下角计分窗口，也可以回到这里"; footer.add_theme_font_size_override("font_size",13); layout.add_child(footer)
	close_requested.connect(hide)
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: hide())
	game_filter.item_selected.connect(func(_index): page = 0; refresh())
	sort_filter.item_selected.connect(func(_index): page = 0; refresh())
	game_rank.item_selected.connect(func(_index): _refresh_rank())
	rows.item_selected.connect(_select)
	previous.pressed.connect(func(): page = maxi(0,page-1); refresh())
	next.pressed.connect(func(): page += 1; refresh())

func bind(store) -> void:
	ledger = store
	ledger.changed.connect(func(): dirty = true)

func _process(_dt: float) -> void:
	if visible and dirty: refresh()

func open_board(screen: int) -> void:
	refresh()
	if visible:
		mode = Window.MODE_WINDOWED; grab_focus(); return
	var area := DisplayServer.screen_get_usable_rect(screen)
	size = Vector2i(mini(880,area.size.x),mini(720,area.size.y))
	position = area.position+(area.size-size)/2
	show(); grab_focus()

func _date(unix: int) -> String:
	# Stored timestamps are UTC; display in the user's current local timezone.
	var offset := int(Time.get_time_zone_from_system().get("bias",0))*60
	return Time.get_datetime_string_from_unix_time(unix+offset).replace("T"," ")

func _color(game: String) -> Color:
	return Color("92c84b") if game=="juggle" else Color("c49aff")

func refresh() -> void:
	if ledger==null: return
	dirty = false
	var selected := ""
	if not rows.get_selected_items().is_empty(): selected = str(rows.get_item_metadata(rows.get_selected_items()[0]))
	listed = ledger.query(games[game_filter.selected],["recent","score","streak"][sort_filter.selected])
	page = clampi(page,0,maxi(0,(listed.size()-1)/PAGE_SIZE))
	rows.clear()
	for i in range(page*PAGE_SIZE,mini(listed.size(),(page+1)*PAGE_SIZE)):
		var item: Dictionary = listed[i]
		var badge := " ★" if item.get("new_record",false) else ""
		rows.add_item("%s · %s  %d 分%s"%[_date(int(item.ended)).substr(5,11),Scores.NAMES[item.game],item.total,badge])
		rows.set_item_metadata(rows.item_count-1,item.id)
		rows.set_item_tooltip(rows.item_count-1,"%s\n%d 分 · %d 连击%s"%[_date(int(item.ended)),item.total,item.streak," · 新纪录" if not badge.is_empty() else ""])
		rows.set_item_custom_fg_color(rows.item_count-1,_color(item.game))
	page_label.text = "%d / %d"%[page+1,maxi(1,ceili(float(listed.size())/PAGE_SIZE))]
	previous.disabled = page==0; next.disabled = (page+1)*PAGE_SIZE>=listed.size()
	notice.text = ledger.last_error if not ledger.last_error.is_empty() else "每局结束后自动记录；动作得分与连击奖励分别保存。"
	if not ledger.current.is_empty(): notice.text += "  当前挑战进行中…"
	if rows.item_count>0:
		var index := 0
		for i in rows.item_count:
			if str(rows.get_item_metadata(i))==selected: index = i; break
		rows.select(index); _select(index)
	else:
		details.text = "还没有完成的游戏。\n撞边后接住猫咪，即可开始记录。" if game_filter.selected!=2 else "猫猫颠锅尚无记录。"
		chart.set_values([],Color("c49aff"),"单局累计得分 · 横轴为加分次数")
	_refresh_rank()

func _select(index: int) -> void:
	var item: Dictionary = listed[page*PAGE_SIZE+index]
	var lines := PackedStringArray(["[b]%s · %d 分[/b]"%[Scores.NAMES[item.game],item.total],
		"%s\n持续 %.1f 秒 · %d 连击\n%s\n"%[_date(int(item.ended)),item.duration,item.streak,str(item.get("reason",""))]])
	var points: Array = []
	for event in item.events:
		points.append(event.total)
		var color := "92c84b" if item.game=="juggle" else "ffd98d"
		var reward := "  [color=#%s]连击 +%d[/color]"%[color,event.bonus] if int(event.bonus)>0 else ""
		var flight := "高速 ×7 · " if int(event.multiplier)==7 else ""
		lines.append("第 %d 次  ·  %.1f 秒\n%s弹边 %d 次  ·  动作 +%d%s  →  %d 分\n"%[event.streak,event.elapsed,flight,event.walls,event.base,reward,event.total])
		if event.get("blessing","")=="慈父的赐福": lines.append("[color=#92c84b]慈父的赐福[/color]\n")
	details.text = "\n".join(lines)
	chart.set_values(points,_color(item.game),"单局累计得分 · 横轴为加分次数")

func _refresh_rank() -> void:
	if ledger==null: return
	var game: String = games[game_rank.selected+1]
	var info: Dictionary = ledger.statistics(game)
	stats.text = "最高 %d 分    最高连击 %d    完成 %d 局\n平均 %.1f 分    累计游玩 %.1f 分钟"%[info.best,info.streak,info.plays,info.average,info.seconds/60.0]
	var lines := PackedStringArray(["[b]历史前十[/b]"])
	if info.legacy: lines.append("旧版最高 %d 分（旧版未保存时间与明细）"%info.best)
	for i in info.top.size():
		var item: Dictionary = info.top[i]
		lines.append("%02d    %d 分    %d 连击    %s"%[i+1,item.total,item.streak,_date(int(item.ended))])
	if info.top.is_empty(): lines.append("暂无完整记录")
	ranking.text = "\n\n".join(lines)
	var recent: Array = ledger.query(game).slice(0,30); recent.reverse()
	var points: Array = []
	for item in recent: points.append(item.total)
	trend.set_values(points,_color(game),"最近 30 局得分 · 从旧到新")
