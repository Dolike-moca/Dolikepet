extends RefCounted
## Bounded local memory. Only new, attributed user messages may strengthen facts.
## The caller owns persistence and rolls this state back if an atomic save fails.

const DAY := 86400
const MAX_FIXED := 24
const MAX_AUTO := 48
const MAX_TEXT := 300
const MAX_EXTRACT_TEXT := 80
const MAX_PENDING := 32
const MAX_SOURCE_TEXT := 1200
const MAX_BATCH := 12
const MAX_FORGOTTEN := 512
const DAILY_NEW := 3

var last_error := ""
var _entries: Array = []
var _pending: Array = []
var _forgotten: Array = []
var _forget_guard_full := false
var _serial := 0
var _daily_day := ""
var _daily_new := 0

func load_state(raw: Variant, legacy: Array, now: int) -> void:
	_entries = []; _pending = []; _forgotten = []
	_forget_guard_full = false; _serial = 0; _daily_day = ""; _daily_new = 0
	last_error = ""
	if not raw is Dictionary or not raw.get("entries") is Array:
		for value in legacy:
			if value is String and _count_tier("fixed") < MAX_FIXED:
				add_fixed(str(value).strip_edges().left(MAX_TEXT), now)
		last_error = ""
		return
	_serial = clampi(_number(raw.get("serial")), 0, 1000000000)
	_daily_day = _day(raw.get("daily_day", ""))
	_daily_new = clampi(_number(raw.get("daily_new")), 0, DAILY_NEW)
	_forget_guard_full = raw.get("forget_guard_full", false) == true
	var seen := {}
	for value in raw.entries:
		if not value is Dictionary: continue
		var entry := _clean_entry(value, now)
		if entry.is_empty() or seen.has(entry.id): continue
		if entry.tier == "fixed" and _count_tier("fixed") >= MAX_FIXED: continue
		if entry.tier != "fixed" and _auto_count() >= MAX_AUTO: continue
		seen[entry.id] = true
		_entries.append(entry)
		_track_id(entry.id)
	if raw.get("pending") is Array:
		for value in raw.pending:
			if _pending.size() >= MAX_PENDING: break
			if not value is Dictionary or not value.get("text") is String: continue
			var text := str(value.text).strip_edges().left(MAX_SOURCE_TEXT)
			var id := str(value.get("id", "")).left(32)
			var day := _day(value.get("day", ""))
			if text.is_empty() or _sensitive(text) or not _valid_id(id, "s") or seen.has(id) or day.is_empty(): continue
			seen[id] = true
			_pending.append({"id":id, "text":text, "at":clampi(_number(value.get("at")), 0, now), "day":day})
			_track_id(id)
	if raw.get("forgotten") is Array:
		for value in raw.forgotten:
			if not value is Dictionary or _forgotten.size() >= MAX_FORGOTTEN: continue
			var digest := str(value.get("hash", ""))
			if digest.length() != 64 or not digest.is_valid_hex_number(): continue
			var marker := {"hash":digest, "length":clampi(_number(value.get("length")), 0, MAX_TEXT)}
			if not _forgotten.has(marker): _forgotten.append(marker)

func dump_state() -> Dictionary:
	return {"schema":1, "entries":_entries.duplicate(true), "pending":_pending.duplicate(true),
		"forgotten":_forgotten.duplicate(true), "forget_guard_full":_forget_guard_full,
		"serial":_serial, "daily_day":_daily_day, "daily_new":_daily_new}

func enqueue(text: String, now: int, day: String) -> bool:
	var clean := text.strip_edges()
	if clean.is_empty() or _day(day).is_empty() or _sensitive(clean) or _non_fact(clean): return false
	# Truncation is explicit: the extractor can only cite the retained prefix.
	clean = clean.left(MAX_SOURCE_TEXT)
	_pending.append({"id":_next_id("s"), "text":clean, "at":maxi(0, now), "day":day})
	while _pending.size() > MAX_PENDING: _pending.pop_front()
	return true

func batch() -> Array:
	return _pending.slice(0, mini(MAX_BATCH, _pending.size())).duplicate(true)

func clear_pending() -> void:
	_pending.clear()

func discard_batch(sources: Array) -> void:
	var ids := {}
	for source in sources:
		if source is Dictionary: ids[str(source.get("id", ""))] = true
	_pending = _pending.filter(func(source: Dictionary): return not ids.has(source.id))

func extraction_context() -> Array:
	var result: Array = []
	for entry in _entries:
		var item := {"id":entry.id, "text":entry.text, "kind":entry.kind}
		if entry.subject != entry.text: item.subject = entry.subject
		if entry.tier == "fixed": item.tier = "fixed"
		result.append(item)
	return result

func list_entries() -> Array:
	return _entries.duplicate(true)

func texts() -> Array:
	var result: Array = []
	for entry in _entries: result.append(str(entry.text))
	return result

func recall_entries(now: int) -> Array:
	var entries := list_entries().filter(func(entry: Dictionary):
		if entry.tier == "fixed": return true
		if entry.tier == "long": return now - int(entry.last_seen) < 210 * DAY
		return int(entry.expires_at) <= 0 or now < int(entry.expires_at))
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		var left := _priority(a, now)
		var right := _priority(b, now)
		return left > right if left != right else int(a.last_seen) > int(b.last_seen))
	var result: Array = []
	var automatic := 0
	for entry in entries:
		if entry.tier == "fixed": result.append(entry)
		elif automatic < 12:
			result.append(entry)
			automatic += 1
	return result

func recall_context(now: int) -> Dictionary:
	var result := {}
	var seen := {}
	for entry in recall_entries(now):
		# Deduplicate exact text only; retain distinct qualifiers and manual wording.
		if seen.has(entry.text): continue
		seen[entry.text] = true
		if not result.has(entry.tier): result[entry.tier] = []
		result[entry.tier].append(entry.text)
	return result

func add_fixed(text: String, now: int) -> bool:
	last_error = ""
	var clean := _checked_text(text)
	if clean.is_empty(): return false
	for entry in _entries:
		if _normalized(entry.text) == _normalized(clean):
			if entry.tier != "fixed": return pin(entry.id, now)
			return _error("这条记忆已经保存")
	if _count_tier("fixed") >= MAX_FIXED: return _error("最多固定 24 条记忆，请先整理已有记忆")
	var entry := _new_entry(clean, clean, "preference", maxi(0, now))
	entry.tier = "fixed"
	entry.authority_serial = _serial
	entry.sources = [{"id":"manual", "quote":clean.left(200), "at":maxi(0, now), "day":""}]
	_entries.append(entry)
	return true

func edit(id: String, text: String, now: int) -> bool:
	last_error = ""
	var index := _find(id)
	if index < 0: return _error("这条记忆已不存在")
	var clean := _checked_text(text)
	if clean.is_empty(): return false
	for other in _entries:
		if other.id != id and _normalized(other.text) == _normalized(clean): return _error("这条记忆已经保存")
	var entry: Dictionary = _entries[index]
	# User editing is authoritative; old evidence must not be presented as proof.
	entry.text = clean
	entry.last_seen = maxi(int(entry.last_seen), now)
	entry.sources = [{"id":"manual", "quote":clean.left(200), "at":maxi(0, now), "day":""}]
	entry.days = []
	entry.demoted_at = 0
	entry.faded = false
	entry.authority_serial = _serial
	if entry.tier != "fixed":
		entry.tier = "recent"
		entry.expires_at = now + (3 * DAY if entry.kind == "state" else 60 * DAY)
	return true

func pin(id: String, now: int) -> bool:
	last_error = ""
	var index := _find(id)
	if index < 0: return _error("这条记忆已不存在")
	if _entries[index].tier == "fixed": return true
	if _count_tier("fixed") >= MAX_FIXED: return _error("最多固定 24 条记忆，请先整理已有记忆")
	_entries[index].tier = "fixed"
	_entries[index].expires_at = 0
	_entries[index].demoted_at = 0
	_entries[index].faded = false
	_entries[index].last_seen = maxi(int(_entries[index].last_seen), now)
	_entries[index].authority_serial = _serial
	return true

func forget(id: String, _now: int) -> bool:
	last_error = ""
	var index := _find(id)
	if index < 0: return _error("这条记忆已不存在")
	var entry: Dictionary = _entries[index]
	_block(entry.text, false)
	_block(entry.subject, false)
	# All queued pre-delete conversations can contain alternate phrasings. Dropping
	# this small unprocessed queue is safer than retaining data that may relearn it.
	_pending.clear()
	_entries.remove_at(index)
	return true

func forget_text(query: String, now: int) -> int:
	last_error = ""
	var needles := _forget_variants(query)
	if needles.is_empty(): return 0
	var targets: Array = []
	for entry in _entries:
		for needle in needles:
			if _normalized(entry.text).contains(needle) or _normalized(entry.subject).contains(needle):
				targets.append(entry.id)
				break
	for id in targets: forget(str(id), now)
	for needle in needles: _block(needle, true)
	_pending.clear()
	return targets.size()

func advance(now: int) -> bool:
	var changed := false
	var kept: Array = _pending.filter(func(source: Dictionary): return now - int(source.at) < 7 * DAY)
	if kept.size() != _pending.size():
		_pending = kept
		changed = true
	for i in range(_entries.size() - 1, -1, -1):
		var entry: Dictionary = _entries[i]
		if entry.tier == "fixed": continue
		var age := maxi(0, now - int(entry.last_seen))
		if entry.tier == "long" and age >= 180 * DAY:
			entry.tier = "recent"
			entry.demoted_at = int(entry.last_seen) + 180 * DAY
			entry.expires_at = int(entry.demoted_at) + 30 * DAY
			changed = true
		if entry.tier == "recent" and int(entry.expires_at) > 0 and now >= int(entry.expires_at):
			_entries.remove_at(i)
			changed = true
			continue
		var faded: bool = entry.tier == "recent" and (int(entry.demoted_at) > 0 or age >= 30 * DAY)
		if entry.faded != faded:
			entry.faded = faded
			changed = true
	return changed

func apply_result(raw: Variant, sources: Array, now: int, day: String) -> bool:
	last_error = ""
	if raw is String: raw = JSON.parse_string(raw)
	if not raw is Dictionary or not raw.get("items") is Array or raw.items.size() > 32:
		return _error("记忆整理结果格式不正确")
	if _day(day).is_empty(): return _error("记忆整理日期无效")
	var current := {}
	for source in _pending: current[source.id] = source
	var allowed := {}
	for source in sources:
		if not source is Dictionary: continue
		var id := str(source.get("id", ""))
		if current.has(id) and source == current[id]: allowed[id] = source
	if allowed.is_empty(): return _error("这批对话已处理或已取消")
	advance(now)
	# A backwards clock must not reset the daily allowance.
	if _daily_day.is_empty() or day > _daily_day:
		_daily_day = day; _daily_new = 0
	for item in raw.items:
		if item is Dictionary: _apply_item(item, allowed, now)
	advance(now)
	discard_batch(allowed.values())
	last_error = ""
	return true

func _apply_item(item: Dictionary, allowed: Dictionary, now: int) -> void:
	var op := str(item.get("op", "remember"))
	if op not in ["remember", "correct", "forget", "pin"]: return
	if not item.get("source_ids") is Array or item.source_ids.is_empty() or item.source_ids.size() > MAX_BATCH: return
	if not item.get("quote") is String: return
	var quote := str(item.quote).strip_edges()
	if quote.length() < 2 or quote.length() > MAX_EXTRACT_TEXT or _sensitive(quote): return
	var evidence: Array = []
	var evidence_ids := {}
	var live_sources := {}
	for source in _pending: live_sources[source.id] = true
	for source_id in item.source_ids:
		if not source_id is String or not allowed.has(source_id) or not live_sources.has(source_id) or evidence_ids.has(source_id): continue
		var source: Dictionary = allowed[source_id]
		if not str(source.text).contains(quote) or _non_fact(source.text): continue
		evidence.append({"id":source.id, "quote":quote.left(200), "at":source.at, "day":source.day})
		evidence_ids[source_id] = true
	if evidence.is_empty(): return
	var explicit_pin := false
	var explicit_forget := false
	var explicit_correct := false
	for source in evidence:
		var original: String = allowed[source.id].text
		explicit_pin = explicit_pin or _pin_requested(original)
		explicit_forget = explicit_forget or _forget_requested(original)
		explicit_correct = explicit_correct or _correction(original)
	var index := _find(str(item.get("target_id", "")))
	if op == "forget":
		if explicit_forget and index >= 0 and _related(quote, _entries[index]): forget(_entries[index].id, now)
		return
	if op == "pin" and not explicit_pin: return
	if op == "pin" and index >= 0 and not _related(quote, _entries[index]): return
	if op == "correct" and (not explicit_correct or index < 0): return
	if op == "correct" and not _related(quote, _entries[index]): return
	if not item.get("text") is String or not item.get("subject") is String: return
	var text := str(item.text).strip_edges()
	var subject := str(item.subject).strip_edges()
	var kind := str(item.get("kind", ""))
	# An explicit correction of user-fixed detail retains the manual length budget.
	var text_limit := MAX_TEXT if op == "correct" and index >= 0 and _entries[index].tier == "fixed" else MAX_EXTRACT_TEXT
	if text.is_empty() or text.length() > text_limit or subject.is_empty() or subject.length() > MAX_EXTRACT_TEXT: return
	if kind not in ["preference", "habit", "event", "state"] or _sensitive(text) or _sensitive(subject): return
	if op == "pin" and not _related(quote, {"text":text}): return
	if op != "pin" and (_blocked(text) or _blocked(subject)): return
	if index < 0:
		for i in _entries.size():
			if _normalized(_entries[i].subject) == _normalized(subject) or _normalized(_entries[i].text) == _normalized(text):
				index = i
				break
	if index >= 0:
		var existing: Dictionary = _entries[index]
		if not _related(quote, existing): return
		# A contradiction must be an explicit correction, never reinforcement of
		# the obsolete fact merely because it shares the same topic.
		if op == "remember" and explicit_correct and _normalized(existing.text) != _normalized(text): return
		# An old queued chat must not overwrite or strengthen a later manual edit.
		var authority := int(existing.get("authority_serial", 0))
		evidence = evidence.filter(func(source: Dictionary):
			return int(str(source.id).substr(1)) > authority and (op != "correct" or int(source.at) >= int(existing.last_seen)))
		if evidence.is_empty(): return
		if op == "correct":
			existing.text = text
			existing.subject = subject
			existing.kind = kind
			existing.days = []
			existing.sources = []
			if existing.tier != "fixed": existing.tier = "recent"
		elif _normalized(existing.text) != _normalized(text):
			# Same-topic paraphrases can strengthen, but cannot silently replace a fact.
			if existing.tier == "fixed": return
		if op == "pin" and not pin(existing.id, now): return
		_strengthen(existing, evidence, item, now)
		return
	if op == "correct": return
	if op == "pin":
		if _count_tier("fixed") >= MAX_FIXED: return
	else:
		if _daily_new >= DAILY_NEW: return
		if _auto_count() >= MAX_AUTO: _evict_oldest_auto()
	var entry := _new_entry(text, subject, kind, now)
	entry.last_seen = 0
	if op == "pin": entry.tier = "fixed"
	else: _daily_new += 1
	_strengthen(entry, evidence, item, now)
	_entries.append(entry)

func _strengthen(entry: Dictionary, evidence: Array, item: Dictionary, now: int) -> void:
	var latest := int(entry.last_seen)
	for source in evidence:
		latest = maxi(latest, mini(now, int(source.at)))
		var found := false
		for day in entry.days:
			if day.day == source.day: found = true; break
		if not found: entry.days.append({"day":source.day, "at":mini(now, int(source.at))})
		var duplicate := false
		for prior in entry.sources:
			if prior.id == source.id: duplicate = true; break
		if not duplicate: entry.sources.append(source.duplicate(true))
	entry.last_seen = latest
	entry.days = entry.days.filter(func(day: Dictionary): return latest - int(day.at) <= 30 * DAY and int(day.at) <= latest)
	while entry.days.size() > 31: entry.days.pop_front()
	while entry.sources.size() > 3: entry.sources.pop_front()
	entry.demoted_at = 0
	entry.faded = false
	if entry.tier != "fixed" and entry.kind in ["preference", "habit"] and entry.days.size() >= 3: entry.tier = "long"
	if entry.tier in ["fixed", "long"]:
		entry.expires_at = 0
		return
	var lifetime := 3 * DAY if entry.kind == "state" else 60 * DAY
	entry.expires_at = latest + lifetime
	if entry.kind in ["state", "event"] and _numeric(item.get("expires_at")):
		var end := int(item.expires_at)
		# Event dates come from the extractor but cannot create unbounded retention.
		if end > latest:
			entry.expires_at = clampi(end, latest + DAY, latest + lifetime) if entry.kind == "state" else mini(end, latest + lifetime)

func _new_entry(text: String, subject: String, kind: String, now: int) -> Dictionary:
	return {"id":_next_id("m"), "text":text, "subject":subject, "kind":kind,
		"tier":"recent", "created_at":now, "last_seen":now, "days":[], "sources":[],
		"expires_at":now + 60 * DAY, "demoted_at":0, "faded":false, "authority_serial":0}

func _clean_entry(raw: Dictionary, now: int) -> Dictionary:
	if not raw.get("text") is String or not raw.get("subject") is String: return {}
	var text := str(raw.text).strip_edges().left(MAX_TEXT)
	var subject := str(raw.subject).strip_edges().left(100)
	var id := str(raw.get("id", ""))
	if text.is_empty() or subject.is_empty() or not _valid_id(id, "m"): return {}
	if raw.get("tier") not in ["recent", "long", "fixed"] or raw.get("kind") not in ["preference", "habit", "event", "state"]: return {}
	var created := clampi(_number(raw.get("created_at")), 0, now)
	# Creation records extraction time; the source may have been said earlier.
	var seen := clampi(_number(raw.get("last_seen")), 0, now)
	var entry := {"id":id, "text":text, "subject":subject, "kind":raw.kind, "tier":raw.tier,
		"created_at":created, "last_seen":seen, "days":[], "sources":[],
		"expires_at":clampi(_number(raw.get("expires_at")), 0, now + 60 * DAY),
		"demoted_at":clampi(_number(raw.get("demoted_at")), 0, now), "faded":raw.get("faded", false) == true,
		"authority_serial":clampi(_number(raw.get("authority_serial")), 0, 1000000000)}
	if entry.tier == "recent" and entry.expires_at <= 0:
		entry.expires_at = seen + (3 * DAY if entry.kind == "state" else 60 * DAY)
	if raw.get("days") is Array:
		var seen_days := {}
		for value in raw.days:
			if not value is Dictionary or entry.days.size() >= 31: continue
			var day := _day(value.get("day", ""))
			if day.is_empty() or seen_days.has(day): continue
			seen_days[day] = true
			entry.days.append({"day":day, "at":clampi(_number(value.get("at")), 0, now)})
	if raw.get("sources") is Array:
		for value in raw.sources:
			if not value is Dictionary or not value.get("quote") is String or entry.sources.size() >= 3: continue
			entry.sources.append({"id":str(value.get("id", "")).left(32), "quote":str(value.quote).left(200),
				"at":clampi(_number(value.get("at")), 0, now), "day":_day(value.get("day", ""))})
	return entry

func _evict_oldest_auto() -> void:
	var candidate := -1
	for i in _entries.size():
		if _entries[i].tier == "fixed": continue
		if candidate < 0 or (_entries[i].tier == "recent" and _entries[candidate].tier == "long") or (_entries[i].tier == _entries[candidate].tier and int(_entries[i].last_seen) < int(_entries[candidate].last_seen)): candidate = i
	if candidate >= 0: _entries.remove_at(candidate)

func _block(text: String, fragment: bool) -> void:
	var normalized := _normalized(text)
	if normalized.is_empty(): return
	var marker := {"hash":normalized.sha256_text(), "length":normalized.length() if fragment else 0}
	if _forgotten.has(marker): return
	if _forgotten.size() >= MAX_FORGOTTEN:
		# Fail closed rather than drop an old intentional-forgetting rule.
		_forget_guard_full = true
		return
	_forgotten.append(marker)

func _blocked(text: String) -> bool:
	if _forget_guard_full: return true
	var normalized := _normalized(text)
	var whole := normalized.sha256_text()
	for marker in _forgotten:
		if marker.hash == whole: return true
		var width := int(marker.length)
		if width < 2 or width > normalized.length(): continue
		for i in range(normalized.length() - width + 1):
			if normalized.substr(i, width).sha256_text() == marker.hash: return true
	return false

func _find(id: String) -> int:
	for i in _entries.size():
		if _entries[i].id == id: return i
	return -1

func _count_tier(tier: String) -> int:
	var count := 0
	for entry in _entries:
		if entry.tier == tier: count += 1
	return count

func _auto_count() -> int:
	return _entries.size() - _count_tier("fixed")

func _next_id(prefix: String) -> String:
	_serial += 1
	return prefix + str(_serial)

func _track_id(id: String) -> void:
	_serial = maxi(_serial, int(id.substr(1)))

func _checked_text(text: String) -> String:
	var clean := text.strip_edges()
	if clean.is_empty() or clean.length() > MAX_TEXT:
		last_error = "每条记忆需要 1—300 字"
		return ""
	return clean

func _error(message: String) -> bool:
	last_error = message
	return false

static func _priority(entry: Dictionary, now: int) -> int:
	if entry.tier == "fixed": return 400
	if entry.tier == "long": return 300
	return 100 if entry.faded or now - int(entry.last_seen) >= 30 * DAY else 200

static func _numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _number(value: Variant) -> int:
	return int(value) if _numeric(value) else 0

static func _valid_id(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() <= 16 and value.substr(1).is_valid_int() and int(value.substr(1)) > 0

static func _day(value: Variant) -> String:
	if not value is String or value.length() != 10: return ""
	var parts := str(value).split("-")
	if parts.size() != 3 or parts[0].length() != 4 or parts[1].length() != 2 or parts[2].length() != 2: return ""
	for part in parts:
		if not str(part).is_valid_int(): return ""
	var year := int(parts[0]); var month := int(parts[1]); var day := int(parts[2])
	if year < 2000 or year > 2200 or month < 1 or month > 12: return ""
	var lengths := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return str(value) if day >= 1 and day <= lengths[month - 1] else ""

static func _normalized(text: String) -> String:
	var result := text.strip_edges().to_lower()
	for value in [" ", "\t", "\n", "\r", "。", "，", "！", "？", ",", ".", "!", "?", "：", ":", "；", ";", "“", "”", "\"", "'", "、"]: result = result.replace(value, "")
	return result

static func _forget_variants(query: String) -> Array:
	var original := _normalized(query)
	if original.length() < 2: return []
	var result: Array = [original]
	var topic := original.trim_prefix("关于")
	for suffix in ["这件事情", "这件事", "这回事", "的事"]:
		if topic.ends_with(suffix) and topic.length() - suffix.length() >= 2:
			var shortened := topic.trim_suffix(suffix)
			# Do not turn an unspecified '我喜欢这件事' into a broad delete.
			if shortened not in ["我喜欢", "用户喜欢", "我讨厌", "用户讨厌", "我说", "用户说"]: topic = shortened
			break
	if topic.length() >= 2 and not result.has(topic): result.append(topic)
	for value in result.duplicate():
		if str(value).begins_with("我") and not str(value).begins_with("我们") and str(value).length() >= 3:
			var third_person := "用户" + str(value).substr(1)
			if not result.has(third_person): result.append(third_person)
	return result

static func _sensitive(text: String) -> bool:
	var lower := text.to_lower()
	for word in ["密码", "口令", "密钥", "私钥", "身份证", "银行卡", "api key", "api_key", "apikey", "access_token", "refresh_token", "bearer ", "sk-", "password", "private key", "验证码", "住址", "家庭地址", "我的地址", "我住在", "诊断", "病史", "患有", "抑郁症", "焦虑症", "怀孕", "病历", "肿瘤", "癌症", "糖尿病", "艾滋", "hiv", "medical record", "credit card", "social security", "my address"]:
		if lower.contains(word): return true
	var pattern := RegEx.new()
	pattern.compile("[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}|(?:\\+?86[- ]?)?1[3-9][0-9]{9}|[0-9]{13,19}|\\+?[0-9]{1,3}[ -]?\\(?[0-9]{3}\\)?[ -][0-9]{3}[ -][0-9]{4}")
	if pattern.search(lower) != null: return true
	return false

static func _non_fact(text: String) -> bool:
	var lower := text.to_lower()
	if _normalized(lower) in ["嗯", "嗯嗯", "哦", "好", "是", "是的", "对", "对的", "没错", "确实", "yes", "yeah", "ok", "okay", "yep", "sure"]: return true
	var affirmation := RegEx.new()
	affirmation.compile("^(嗯|啊|哦|唔|好|是的|是|对的|对|没错|确实)+$")
	if affirmation.search(_normalized(lower)) != null: return true
	for word in ["假如", "假设", "如果我", "开玩笑", "比如说", "例如：", "例如:", "角色扮演", "假装", "忽略上面", "ignore previous", "pretend that", "hypothetically"]:
		if lower.contains(word): return true
	return false

static func _pin_requested(text: String) -> bool:
	var lower := text.to_lower()
	for negation in ["不要记", "别记", "不想记", "不用记", "don't remember", "do not remember"]:
		if lower.contains(negation): return false
	for word in ["记住", "记着", "别忘", "remember that", "remember this"]:
		if lower.contains(word): return true
	return false

static func _forget_requested(text: String) -> bool:
	var lower := text.to_lower()
	for word in ["不要忘", "别忘", "不能忘", "don't forget", "do not forget"]:
		if lower.contains(word): return false
	for word in ["忘掉", "忘记", "不要记", "别记", "删除记忆", "forget", "don't remember", "do not remember"]:
		if lower.contains(word): return true
	return false

static func _related(quote: String, entry: Dictionary) -> bool:
	var source := _normalized(quote)
	var content := _normalized(str(entry.text))
	for generic in ["用户", "猫猫", "永久", "记住", "记着", "忘掉", "忘记", "删除", "记忆", "不喜欢", "喜欢", "喜爱", "偏爱", "现在", "已经", "关于", "这件事", "这个", "那件事", "一下", "请", "我", "你", "的", "是", "不", "了", "吃", "喝", "theuser", "user", "remember", "forget", "please", "likes", "like", "that", "this"]:
		content = content.replace(generic, "")
	if content.length() < 2: return false
	if source.contains(content): return true
	# For a longer fact, require a meaningful shared phrase rather than a generic
	# word like '喜欢'. The model never gets authority from an arbitrary target ID.
	var width := mini(4, content.length())
	for i in range(content.length() - width + 1):
		if source.contains(content.substr(i, width)): return true
	return false

static func _correction(text: String) -> bool:
	var lower := text.to_lower()
	for word in ["现在", "改成", "不再", "已经不", "不喜欢", "不是", "纠正", "instead", "no longer", "actually"]:
		if lower.contains(word): return true
	return false
