extends RefCounted
## M2-01：内容 schema 校验。
## 只检查"能否安全接入世界"，不检查文案好坏。
## 错误格式：{code, path, message}，path 精确到文件、下标、字段。

const EVENT_FIELDS := ["id", "name", "min_age", "max_age", "weight", "cooldown", "cond", "text", "effects"]
const EVENT_REQUIRED := ["id", "name", "min_age", "weight", "cooldown"]
const EFFECT_FIELDS := ["money", "health", "fame", "story"]
## 只允许已经实现的条件；加新条件必须同时实现 _event_ok 分支
const CONDITIONS := ["", "farm", "famous", "parent"]


static func _is_number(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return true
	return false


static func _is_int_like(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return float(v) == floor(float(v))
	return false


static func _err(code: String, path: String, message: String) -> Dictionary:
	return {"code": code, "path": path, "message": message}


static func validate_events(events: Variant, source: String = "data/events.json") -> Array:
	var errors: Array = []
	if not (events is Array):
		errors.append(_err("bad_root", source, "根必须是数组"))
		return errors
	var seen := {}
	var arr: Array = events
	for i in range(arr.size()):
		var at := "%s[%d]" % [source, i]
		var raw: Variant = arr[i]
		if not (raw is Dictionary):
			errors.append(_err("bad_type", at, "事件必须是对象"))
			continue
		var ev: Dictionary = raw
		for f in EVENT_REQUIRED:
			if not ev.has(f):
				errors.append(_err("missing_field", at + "." + f, "缺少必填字段 " + f))
		for f in ev.keys():
			if not EVENT_FIELDS.has(str(f)):
				errors.append(_err("unknown_field", at + "." + str(f), "未知字段 " + str(f)))
		var eid := ""
		if ev.has("id"):
			if not (ev["id"] is String) or str(ev["id"]) == "":
				errors.append(_err("bad_type", at + ".id", "id 必须是非空字符串"))
			else:
				eid = str(ev["id"])
				if seen.has(eid):
					errors.append(_err("duplicate_id", at + ".id", "id 重复：" + eid))
				seen[eid] = true
		if ev.has("name") and not (ev["name"] is String):
			errors.append(_err("bad_type", at + ".name", "name 必须是字符串"))
		if ev.has("min_age") and not _is_int_like(ev["min_age"]):
			errors.append(_err("bad_type", at + ".min_age", "min_age 必须是整数"))
		elif ev.has("min_age") and (int(ev["min_age"]) < 0 or int(ev["min_age"]) > 120):
			errors.append(_err("bad_age_range", at + ".min_age", "min_age 必须在 0..120"))
		if ev.has("max_age"):
			if not _is_int_like(ev["max_age"]):
				errors.append(_err("bad_type", at + ".max_age", "max_age 必须是整数"))
			elif ev.has("min_age") and _is_int_like(ev["min_age"]) and int(ev["max_age"]) < int(ev["min_age"]):
				errors.append(_err("bad_age_range", at + ".max_age", "max_age 不能小于 min_age"))
		if ev.has("weight") and (not _is_int_like(ev["weight"]) or int(ev["weight"]) < 1):
			errors.append(_err("bad_type", at + ".weight", "weight 必须是 >=1 的整数"))
		if ev.has("cooldown") and (not _is_int_like(ev["cooldown"]) or int(ev["cooldown"]) < 0):
			errors.append(_err("bad_type", at + ".cooldown", "cooldown 必须是 >=0 的整数"))
		if ev.has("cond") and not (ev["cond"] is String):
			errors.append(_err("bad_type", at + ".cond", "cond 必须是字符串"))
		elif ev.has("cond") and not CONDITIONS.has(str(ev["cond"])):
			errors.append(_err("unknown_condition", at + ".cond", "未实现的条件：" + str(ev["cond"])))
		if ev.has("text") and not (ev["text"] is String):
			errors.append(_err("bad_type", at + ".text", "text 必须是字符串"))
		if ev.has("effects"):
			if not (ev["effects"] is Dictionary):
				errors.append(_err("bad_type", at + ".effects", "effects 必须是对象"))
			else:
				var eff: Dictionary = ev["effects"]
				for k in eff.keys():
					var key := str(k)
					var ep := at + ".effects." + key
					if not EFFECT_FIELDS.has(key):
						errors.append(_err("unknown_effect", ep, "未实现的效果：" + key))
						continue
					if key == "story":
						if not (eff[k] is String) or str(eff[k]) == "":
							errors.append(_err("bad_type", ep, "story 必须是非空字符串"))
					elif not _is_number(eff[k]):
						errors.append(_err("bad_type", ep, key + " 必须是数字"))
	return errors


static func format_errors(errors: Array) -> String:
	var lines: Array = []
	for e in errors:
		var d: Dictionary = e
		lines.append("%s: %s (%s)" % [str(d.get("path", "?")), str(d.get("message", "")), str(d.get("code", ""))])
	return "\n".join(lines)
