extends SceneTree
## Offline, synthetic text only. Compaction must preserve facts and evidence.
const Ledger = preload("res://scripts/ai_memory_ledger.gd")
const Extract = preload("res://scripts/ai_memory_extract.gd")
const DAY := 86400
var checks := 0
var failures: Array[String] = []
var start := int(Time.get_unix_time_from_datetime_string("2026-11-01T12:00:00"))

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func day(at: int) -> String:
	return Time.get_date_string_from_unix_time(at)

func _initialize() -> void:
	var ledger = Ledger.new()
	var original := "我每周三和周五晚上九点散步30分钟，雨天不出门，称呼我为小铃。"
	for offset in 3: ledger.enqueue(original, start + offset * DAY, day(start + offset * DAY))
	ledger.enqueue("我每周三散步20分钟，下雨时也会出门。", start + 2 * DAY, day(start + 2 * DAY))
	var sources: Array = ledger.batch()
	var snapshot: Dictionary = ledger.dump_state()
	var request: Array = Extract.input(sources, [], start + 2 * DAY, day(start + 2 * DAY))
	var body: Dictionary = JSON.parse_string(request[0].content)
	check(body.sources.size() == sources.size(), "wire compaction retains every source ID")
	check(body.sources[1].same_as == sources[0].id and body.sources[2].same_as == sources[0].id, "only identical source texts share a direct reference")
	check(body.sources[3].text == sources[3].text, "different quantity and negation remain distinct source text")
	var by_id := {}
	for source in sources: by_id[source.id] = source
	for index in sources.size():
		var expanded: Dictionary = body.sources[index].duplicate(true)
		if expanded.has("same_as"):
			expanded.text = by_id[expanded.same_as].text
			expanded.erase("same_as")
		expanded.at = int(expanded.at) # JSON numbers decode as floats in Godot.
		check(expanded == sources[index], "source round-trip preserves exact text, ID, date and timestamp")
	check(ledger.dump_state() == snapshot and ledger.batch() == sources, "wire compaction never rewrites stored or in-flight evidence")
	check(not ledger.apply_result({"items":[]}, body.sources.slice(1, 3), start + 2 * DAY, day(start + 2 * DAY)), "wire references alone cannot authorize altered source evidence")
	var remembered := "用户每周三、五21点散步30分钟，雨天不出门；称呼小铃"
	var result := {"items":[{"text":remembered, "kind":"habit", "subject":"散步习惯",
		"source_ids":[sources[0].id, sources[1].id, sources[2].id, sources[3].id], "quote":original}]}
	check(ledger.apply_result(result, sources, start + 2 * DAY, day(start + 2 * DAY)), "compact wire still accepts original validated batch")
	var entry: Dictionary = ledger.list_entries()[0]
	check(entry.tier == "long" and entry.days.size() == 3 and entry.sources.size() == 3, "all independent days promote while a mismatched quote adds no evidence")
	check(entry.last_seen == start + 2 * DAY and entry.text == remembered, "newest source time and all supplied fact qualifiers are retained")
	var context: Array = ledger.extraction_context()
	check(context[0].subject == entry.subject and context[0].kind == entry.kind and not context[0].has("tier"), "matching subject and kind survive omission of automatic tier")
	var long_fixed := "请称呼我为小铃。" + "周三不喝咖啡，每周只喝两杯茶，11月6日以后再调整；".repeat(4)
	check(long_fixed.length() > 80 and ledger.add_fixed(long_fixed, start + 2 * DAY), "manual fixed memory can exceed automatic summary length")
	check(ledger.extraction_context()[1].text == long_fixed and not ledger.extraction_context()[1].has("subject"), "only duplicate subject metadata is omitted from fixed extraction context")
	check(ledger.recall_context(start + 2 * DAY).fixed[0] == long_fixed, "long manual wording is recalled without truncation")
	var fixed_id: String = ledger.list_entries()[1].id
	var corrected_fixed := long_fixed.replace("两杯茶", "三杯茶")
	ledger.enqueue("纠正，" + corrected_fixed, start + 2 * DAY + 1, day(start + 2 * DAY))
	var correction_sources: Array = ledger.batch()
	ledger.apply_result({"items":[{"op":"correct", "target_id":fixed_id, "text":corrected_fixed, "subject":"称呼与喝茶安排", "kind":"habit", "source_ids":[correction_sources[0].id], "quote":corrected_fixed.left(80)}]}, correction_sources, start + 2 * DAY + 1, day(start + 2 * DAY))
	check(ledger.list_entries()[1].tier == "fixed" and ledger.list_entries()[1].text == corrected_fixed, "explicit correction of long fixed memory preserves every detail within manual length budget")
	var changed := snapshot.duplicate(true)
	changed.entries = ledger.list_entries()
	var duplicate: Dictionary = changed.entries[0].duplicate(true)
	duplicate.id = "m800"
	duplicate.tier = "fixed"
	changed.entries.append(duplicate)
	var distinct: Dictionary = duplicate.duplicate(true)
	distinct.id = "m801"
	distinct.text = "用户11月6日前不喝咖啡，每周喝2杯茶"
	changed.entries.append(distinct)
	var other_date: Dictionary = distinct.duplicate(true)
	other_date.id = "m802"
	other_date.text = "用户11月7日起喝咖啡，每周喝3杯茶"
	changed.entries.append(other_date)
	var recall_ledger = Ledger.new()
	recall_ledger.load_state(changed, [], start + 2 * DAY)
	var before_recall: Dictionary = recall_ledger.dump_state()
	var recalled: Dictionary = recall_ledger.recall_context(start + 2 * DAY)
	check(recalled.fixed.has(remembered) and not recalled.has("long"), "identical recall text occurs once with fixed precedence")
	check(recalled.fixed.has(distinct.text) and recalled.fixed.has(other_date.text), "different dates, quantities and negations are never merged")
	check(recall_ledger.dump_state() == before_recall, "recall compaction cannot migrate or overwrite historical entries")
	var bounded = Ledger.new()
	bounded.enqueue(original, start, day(start))
	var pending: Array = bounded.batch()
	var too_long := result.duplicate(true)
	too_long.items[0].source_ids = [pending[0].id]
	too_long.items[0].text = "字".repeat(81)
	bounded.apply_result(too_long, pending, start, day(start))
	check(bounded.texts().is_empty(), "overlong automatic summary is rejected rather than silently truncated")
	bounded.enqueue(original, start + 1, day(start))
	pending = bounded.batch()
	too_long.items[0].source_ids = [pending[0].id]
	too_long.items[0].text = "字".repeat(80)
	bounded.apply_result(too_long, pending, start + 1, day(start))
	check(bounded.texts() == ["字".repeat(80)], "necessary automatic detail may use the complete eighty-character limit")
	measure_payloads()
	print("AI memory compaction: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func measure_payloads() -> void:
	var ledger = Ledger.new()
	for index in 8: ledger.add_fixed("请保留第%d个手动偏好及原始措辞" % index, start)
	for offset in 3:
		for index in 4:
			ledger.enqueue("我每周第%d天晚上九点散步30分钟，雨天不出门，以后称呼我为小铃。" % index, start + offset * DAY, day(start + offset * DAY))
	var original_existing: Array = []
	var original_recall: Array = []
	for entry in ledger.list_entries():
		original_existing.append({"id":entry.id, "text":entry.text, "subject":entry.subject, "kind":entry.kind, "tier":entry.tier})
	for entry in ledger.recall_entries(start): original_recall.append({"text":entry.text, "tier":entry.tier})
	var before := JSON.stringify({"now":start + 2 * DAY, "local_day":day(start + 2 * DAY), "sources":ledger.batch(), "existing":original_existing})
	var after: String = Extract.input(ledger.batch(), ledger.extraction_context(), start + 2 * DAY, day(start + 2 * DAY))[0].content
	check(after.length() < before.length() and after.to_utf8_buffer().size() < before.to_utf8_buffer().size(), "synthetic extraction input reduces both characters and UTF-8 bytes")
	print("MEMORY_INPUT_SIZE chars=%d->%d utf8_bytes=%d->%d" % [before.length(), after.length(), before.to_utf8_buffer().size(), after.to_utf8_buffer().size()])
	before = JSON.stringify(original_recall)
	after = JSON.stringify(ledger.recall_context(start))
	check(after.length() < before.length() and after.to_utf8_buffer().size() < before.to_utf8_buffer().size(), "grouped recall reduces repeated field names without shortening facts")
	print("MEMORY_RECALL_SIZE chars=%d->%d utf8_bytes=%d->%d" % [before.length(), after.length(), before.to_utf8_buffer().size(), after.to_utf8_buffer().size()])
