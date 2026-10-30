extends RefCounted
## Wording only: one choice is shared by AI and offline invitations.
## No state is persisted and no pet action is executed here.
const WEIGHTS := {"daily": 3, "food": 2, "interaction": 3, "warhammer": 2}
const OPTIONS := {
	"daily": [
		{"variant":"bright_spot", "prompt":"轻松问用户今天有没有一件让心情变好的小事，不预设发生了什么。", "fallback":"今天有没有一件让你心情变好的小事呀？"},
		{"variant":"small_plan", "prompt":"轻松问用户闲下来时想做什么小事，不推测日程。", "fallback":"等闲下来，你想做点什么让自己开心呀？"},
		{"variant":"free_chat", "prompt":"轻松问用户此刻有没有想随口聊的话题，不索取回应。", "fallback":"现在有没有想随口聊聊的事呀？"},
	],
	"food": [
		{"variant":"snack", "prompt":"从喜欢美食自然开场，问用户现在想聊哪种小零食，不声称饥饿或刚被喂食。", "fallback":"如果挑一份小零食，你今天会选什么呀？"},
		{"variant":"fries", "prompt":"聊猫猫喜欢的薯条，问用户喜欢什么口味，不要求喂食或操作文件。", "fallback":"说到薯条，你喜欢原味，还是蘸点酱呀？"},
		{"variant":"favorite_food", "prompt":"轻松问用户想到哪道食物会开心，不推测用户吃了什么。", "fallback":"有没有一道食物，光是想到就让你开心呀？"},
	],
	"interaction": [
		{"variant":"grow", "prompt":"可以提议让用户把猫猫的体型调大一档，问这样陪伴会不会更显眼；只能提议，不声称已经调大或会自动执行。", "fallback":"要不要把我调大一档，让猫猫更显眼一点呀？"},
		{"variant":"catch", "prompt":"轻松邀请用户有空时玩一会儿桌宠抛接；只提议，不声称刚玩过、已开始或会自动执行。", "fallback":"有空的话，要不要和猫猫玩一会儿抛接呀？"},
		{"variant":"juggle", "prompt":"轻松邀请用户有空时玩一会儿桌宠颠锅；只提议，不声称刚玩过、已开始或会自动执行。", "fallback":"要不要找个空当，和猫猫玩一会儿颠锅呀？"},
	],
	"warhammer": [
		{"variant":"faction", "prompt":"偶尔从战锤兴趣开场，问用户偏爱哪个阵营；不预设其熟悉程度，不加入具体背景事实或未经核实的新消息。", "fallback":"说起战锤，你有没有偏爱的阵营呀？"},
		{"variant":"stories", "prompt":"偶尔从战锤兴趣开场，问用户更想聊背景故事还是涂装；不加入具体背景事实，不考问用户。", "fallback":"战锤的背景故事和涂装，你更想聊哪一个呀？"},
		{"variant":"painting", "prompt":"偶尔从战锤兴趣开场，问用户会想给模型涂什么颜色；不预设用户拥有模型，不加入具体背景事实。", "fallback":"如果涂一个战锤模型，你想试试什么配色呀？"},
	],
	"rest": [
		{"variant":"short_rest", "prompt":"自然温柔地邀请用户休息、活动一下，不推断用户正在做什么，不做医疗判断，不催促。", "fallback":"要不要休息一小会儿，起来活动活动呀？"},
		{"variant":"relax", "prompt":"自然温柔地问用户要不要短暂休息、放松一下，不推断工作或身体情况，不催促。", "fallback":"想不想先休息一下，和猫猫一起放松一会儿呀？"},
	],
	"game": [
		{"variant":"game_feeling", "prompt":"用户刚结束桌宠小游戏，轻松问一句游戏感受，不催促再玩。", "fallback":"刚才玩得怎么样，有没有觉得有趣的地方呀？"},
		{"variant":"game_chat", "prompt":"用户刚结束桌宠小游戏，邀请聊一句刚才的游戏感受，不编造输赢或催促再玩。", "fallback":"想不想和猫猫聊聊刚才玩游戏的感觉呀？"},
		{"variant":"neutral_chat", "prompt":"轻松问用户想聊点什么，不推测用户活动，不提游戏刚结束，不责备或索取回应。", "fallback":"现在想不想和猫猫轻松聊两句呀？"},
		{"variant":"neutral_topic", "prompt":"轻松问用户有没有感兴趣的话题，不推测用户活动，不提游戏刚结束，不责备或索取回应。", "fallback":"有没有什么感兴趣的话题，想和猫猫聊聊呀？"},
	],
}

var _rng := RandomNumberGenerator.new()
var _last_topic := ""
var _last_fallback := ""

func _init() -> void:
	_rng.randomize()

func set_seed(value: int) -> void:
	_rng.seed = value
	_last_topic = ""
	_last_fallback = ""

func choose(reason: String, context: Dictionary = {}, shared: bool = true) -> Dictionary:
	var topic := reason if reason in ["rest", "game"] else _mixed_topic()
	var options := _available(topic, context, shared)
	var fresh: Array = []
	for option in options:
		if str(option.fallback) != _last_fallback: fresh.append(option)
	if not fresh.is_empty(): options = fresh
	var choice: Dictionary = options[_rng.randi_range(0, options.size() - 1)].duplicate()
	choice.topic = topic
	_last_topic = topic
	_last_fallback = str(choice.fallback)
	return choice

func canonical(reason: String, hint: Dictionary, context: Dictionary = {}, shared: bool = true) -> Dictionary:
	# Reconstruct from known IDs; never trust prompt text passed by the caller.
	var topic := str(hint.get("topic", ""))
	if reason in ["rest", "game"]:
		if topic != reason: return {}
	elif not WEIGHTS.has(topic): return {}
	for option in _available(topic, context, shared):
		if option.variant == hint.get("variant"):
			var result: Dictionary = option.duplicate()
			result.topic = topic
			return result
	return {}

func _mixed_topic() -> String:
	# Excluding the last category keeps the weighted Warhammer share near one
	# fifth while preventing consecutive invitations about the same topic.
	var total := 0
	for topic in WEIGHTS:
		if topic != _last_topic: total += int(WEIGHTS[topic])
	var pick := _rng.randi_range(0, total - 1)
	for topic in WEIGHTS:
		if topic == _last_topic: continue
		pick -= int(WEIGHTS[topic])
		if pick < 0: return topic
	return "daily"

static func _available(topic: String, context: Dictionary, shared: bool) -> Array:
	var result: Array = []
	for option in OPTIONS.get(topic, []):
		if option.variant == "grow" and not can_grow(context, shared): continue
		if topic == "game" and str(option.variant).begins_with("neutral_") == shared: continue
		result.append(option)
	return result

static func can_grow(context: Dictionary, shared: bool) -> bool:
	var size: Variant = context.get("size_percent")
	return shared and (size is int or size is float) and is_finite(float(size)) \
		and float(size) >= 50.0 and float(size) < 200.0
