class_name BEngine
## 대회 팀 싱글 대전 엔진 (순수 함수, 상태는 Dictionary).
## 레벨 50 능력치와 기술별 PP 규칙을 사용한다.
##
## 상태: { turn, over, winner(-1 무승부), rng, sides:[{active, mons:[...], choice, need}] }
## 행동: { k:"move", id } | { k:"swap", to }
## 사건: turn / swap / use / dmg / heal / status / stage / faint / need / over  (화면 연출용)

const SET := "pokemon"

static func rules() -> Dictionary:
	return Data.battle_rules

static func create(picks0: Array, picks1: Array, rng_seed: int, set_id: String = SET, allow_gmax := false) -> Dictionary:
	var sides := []
	for picks in [picks0, picks1]:
		var seat := sides.size()
		var mons := []
		for member in picks:
			var id := str(member["species"])
			var listed := str(member.get("form", "base"))
			var mega := listed if listed.begins_with("mega") else ""
			var form := str(member.get("preMegaForm", "eternal" if id == "floette" else "base")) if mega != "" else listed
			var detail := Data.form(set_id, id, form)
			var gmax := Data.form(set_id, id, "gmax")
			var training: Dictionary = member.get("training", {})
			var sp := Data.species(set_id, id)
			var base_stats: Dictionary = detail["baseStats"]
			var stats := Data.battle_stats(base_stats, training)
			var hp := int(stats["hp"])
			var moves := _configured_moves(set_id, member, sp)
			var pp := {}
			for id_move in moves:
				pp[id_move] = max_pp(set_id, str(id_move))
			mons.append({ "id": id, "set": set_id, "form": form, "types": Data.types(set_id, id, form),
				"moves": moves, "pp": pp, "stats": stats,
				"seat": seat, "mega": mega, "gmax": gmax.get("id") == "gmax", "gmaxTurns": 0, "training": training,
				"ability": member.get("ability", detail.get("battleAbility", "")), "item": member.get("item", ""),
				"itemUsed": false, "choiceMove": "", "fresh": true, "status": "", "sleep": 0, "hp": hp, "max": hp,
				"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0, "dot": 0, "slow": 0,
				"guard": false, "guardChain": 0, "seen": false })
		mons[0]["seen"] = true
		sides.append({ "active": 0, "mons": mons, "choice": null, "need": false, "usedGimmick": false, "tailwind": 0, "gmaxResidual": "", "gmaxResidualTurns": 0 })
	var state := { "turn": 1, "over": false, "winner": -1, "rng": rng_seed & 0x7fffffff, "sides": sides,
		"weather": "", "weatherTurns": 0, "terrain": "", "terrainTurns": 0, "trickRoom": 0, "allowGmax": allow_gmax }
	var first := 0 if _stat(active(state, 0), "spe") >= _stat(active(state, 1), "spe") else 1
	_enter(state, first, [])
	_enter(state, 1 - first, [])
	return state

static func _rand(s: Dictionary) -> float:
	s["rng"] = (int(s["rng"]) * 1103515245 + 12345) & 0x7fffffff
	return float(int(s["rng"]) >> 8) / float(0x800000)

static func active(s: Dictionary, seat: int) -> Dictionary:
	var side: Dictionary = s["sides"][seat]
	return side["mons"][int(side["active"])]

static func move(set_id: String, id: String) -> Dictionary:
	if id == "practice_struggle":
		return { "ko": "발버둥", "type": "노말", "power": 50, "typeless": true,
			"effects": [{ "kind": "struggle" }], "desc": "사용할 수 있는 기술이 없을 때 공격하고 최대 HP의 ¼을 잃습니다." }
	if id == "practice_recharge":
		return { "ko": "반동으로 쉬기", "type": "노말", "desc": "직전 기술의 반동으로 이번 턴에 쉽니다." }
	return Data.move(set_id, id)

static func max_pp(set_id: String, id: String) -> int:
	return int(move(set_id, id).get("pp", 0))

static func _configured_moves(set_id: String, member: Dictionary, species: Dictionary) -> Array:
	var sets: Dictionary = Data.sets[set_id]["practice_sets"]
	var id := str(member["species"])
	var form_key := "%s:%s" % [id, member.get("form", "base")]
	var roster: Array = sets.get(form_key, sets.get(id, species.get("moves", [])))
	var recorded: Array = member.get("moves", [])
	var configured := recorded.filter(func(move_id): return max_pp(set_id, str(move_id)) > 0)
	return configured if not configured.is_empty() else roster.filter(func(move_id): return max_pp(set_id, str(move_id)) > 0)

static func _field(s: Dictionary, key: String, value: String, ev: Array) -> void:
	s[key] = value
	s[key + "Turns"] = 5
	ev.append({ "e": "field", "what": value })
	if key == "terrain":
		for seat in 2:
			_activate_seed(s, seat, ev)

static func _activate_seed(s: Dictionary, seat: int, ev: Array) -> void:
	var mon := active(s, seat)
	if mon["itemUsed"]:
		return
	if mon["item"] == "Grassy Seed" and s["terrain"] == "그래스필드":
		mon["itemUsed"] = true
		_stage(mon, seat, "def", 1, ev)
	if mon["item"] == "Psychic Seed" and s["terrain"] == "사이코필드":
		mon["itemUsed"] = true
		_stage(mon, seat, "spd", 1, ev)

static func _stage(mon: Dictionary, seat: int, stat: String, delta: int, ev: Array, opponent_effect := false) -> void:
	if int(mon["hp"]) <= 0:
		return
	var before := int(mon[stat])
	var applied := -delta if mon["ability"] == "Contrary" else delta
	mon[stat] = clampi(before + applied, -6, 6)
	if int(mon[stat]) != before:
		ev.append({ "e": "stage", "seat": seat, "stat": stat, "delta": int(mon[stat]) - before })
		if applied < 0 and opponent_effect and mon["ability"] in ["Defiant", "Competitive"]:
			_stage(mon, seat, "atk" if mon["ability"] == "Defiant" else "spa", 2, ev)

static func _enter(s: Dictionary, seat: int, ev: Array) -> void:
	var mon := active(s, seat)
	var side: Dictionary = s["sides"][seat]
	_activate_seed(s, seat, ev)
	if side.get("toxicSpikes", 0) > 0 and _grounded(mon):
		if "독" in mon["types"]:
			side["toxicSpikes"] = 0
		else:
			_apply_status(mon, seat, "독", ev)
	match str(mon["ability"]):
		"Drought": _field(s, "weather", "쾌청", ev)
		"Drizzle": _field(s, "weather", "비", ev)
		"Sand Stream": _field(s, "weather", "모래바람", ev)
		"Snow Warning": _field(s, "weather", "눈", ev)
		"Grassy Surge": _field(s, "terrain", "그래스필드", ev)
		"Psychic Surge": _field(s, "terrain", "사이코필드", ev)
		"Electric Surge": _field(s, "terrain", "일렉트릭필드", ev)
		"Misty Surge": _field(s, "terrain", "미스트필드", ev)
		"Intimidate":
			var foe := active(s, 1 - seat)
			if foe["ability"] == "Mirror Armor":
				_stage(mon, seat, "atk", -1, ev, true)
			elif foe["ability"] not in ["Clear Body", "White Smoke", "Hyper Cutter", "Inner Focus", "Own Tempo", "Oblivious", "Scrappy"]:
				_stage(foe, 1 - seat, "atk", -1, ev, true)
		"Hospitality": pass # 아군이 동시에 나와 있을 때만 발동한다.

static func _gimmicks(s: Dictionary, seat: int) -> Array:
	var side: Dictionary = s["sides"][seat]
	if side["usedGimmick"] or side["need"] or active(s, seat)["hp"] <= 0:
		return []
	var mon := active(s, seat)
	var result := []
	if mon["mega"] != "" and mon["form"] != mon["mega"]:
		var next := Data.form(mon["set"], mon["id"], mon["mega"])
		if next.get("requiresItem", "") == mon["item"] and mon["item"] != "":
			result.append("mega")
	if s["allowGmax"] and mon["gmax"]:
		result.append("gmax")
	return result

static func _transform(s: Dictionary, seat: int, kind: String, ev: Array) -> void:
	var mon := active(s, seat)
	s["sides"][seat]["usedGimmick"] = true
	if kind == "mega":
		_set_form(mon, mon["mega"])
		var detail := Data.form(mon["set"], mon["id"], mon["form"])
		var former: String = mon["ability"]
		mon["ability"] = detail.get("battleAbility", former)
		ev.append({ "e": "transform", "seat": seat, "mon": mon.duplicate(true), "what": "메가진화" })
		if mon["ability"] != former:
			_enter(s, seat, ev)
	else:
		mon["previousForm"] = mon["form"]
		mon["form"] = "gmax"
		mon["gmaxTurns"] = 3
		mon["hp"] = int(mon["hp"]) * 2
		mon["max"] = int(mon["max"]) * 2
		ev.append({ "e": "transform", "seat": seat, "mon": mon.duplicate(true), "what": "거다이맥스" })

static func _set_form(mon: Dictionary, form: String) -> void:
	mon["form"] = form
	mon["types"] = Data.types(mon["set"], mon["id"], form)
	mon["stats"] = Data.battle_stats(Data.form(mon["set"], mon["id"], form)["baseStats"], mon["training"])

static func preview_combatant(mon: Dictionary, gimmick: String) -> Dictionary:
	if gimmick == "":
		return mon
	var preview := mon.duplicate()
	if gimmick == "gmax":
		preview["form"] = "gmax"
		preview["gmaxTurns"] = 3
	elif gimmick == "mega":
		_set_form(preview, preview["mega"])
		preview["ability"] = Data.form(preview["set"], preview["id"], preview["form"]).get("battleAbility", preview["ability"])
	return preview

static func preview_move(s: Dictionary, mon: Dictionary, id: String, gimmick: String) -> Dictionary:
	return _effective_move(s, preview_combatant(mon, gimmick), id)

static func move_name(mv: Dictionary) -> String:
	return str(mv.get("en", ""))

static func _end_gmax(mon: Dictionary, seat: int, ev: Array) -> void:
	mon["form"] = mon["previousForm"]
	mon["gmaxTurns"] = 0
	mon["hp"] = ceili(float(mon["hp"]) / 2.0)
	mon["max"] = int(mon["stats"]["hp"])
	ev.append({ "e": "transform", "seat": seat, "mon": mon.duplicate(true), "what": "거다이맥스 종료" })

static func _grounded(mon: Dictionary) -> bool:
	return "비행" not in mon["types"] and mon["ability"] != "Levitate"

static func _speed(s: Dictionary, seat: int) -> int:
	var mon := active(s, seat)
	var speed := _stat(mon, "spe")
	if mon["item"] == "Choice Scarf" and mon["gmaxTurns"] == 0:
		speed = floori(speed * 1.5)
	if s["sides"][seat]["tailwind"] > 0:
		speed *= 2
	if (mon["ability"] == "Sand Rush" and s["weather"] == "모래바람") or (mon["ability"] == "Swift Swim" and s["weather"] == "비") or (mon["ability"] == "Chlorophyll" and s["weather"] == "쾌청") or (mon["ability"] == "Unburden" and mon["itemUsed"]):
		speed *= 2
	return speed

static func _stat(mon: Dictionary, key: String) -> int:
	var base := int(mon["stats"][key])
	var stage := int(mon[key])
	var value := floori(base * (2.0 + stage) / 2.0) if stage >= 0 else floori(base * 2.0 / (2 - stage))
	if key == "spe" and (int(mon["slow"]) > 0 or mon.get("status") == "마비"):
		value = floori(value / 2.0)
	return maxi(1, value)

static func effectiveness(move_type: String, defender: Dictionary, attacker := {}) -> Array:
	var levitates: bool = move_type == "땅" and defender.get("ability") == "Levitate" and attacker.get("ability") != "Mold Breaker"
	var multiplier := 0.0 if levitates else TypeChart.mult(move_type, defender["types"])
	var label := "immune" if multiplier == 0.0 else ("strong" if multiplier > 1.0 else ("weak" if multiplier < 1.0 else ""))
	return [multiplier, label]

static func _type_of(mon: Dictionary) -> String:
	return str(mon["types"][0])

## 싱글의 기본 피해, 난수, 자속, 상성. 수비 태세는 앱의 배율을 사용한다.
static func damage(att: Dictionary, defender: Dictionary, mv: Dictionary, roll: int, s := {}) -> int:
	if mv.get("power") == null:
		return 0
	var multiplier := 1.0 if mv.get("typeless", false) else float(effectiveness(str(mv["type"]), defender, att)[0])
	if multiplier == 0.0:
		return 0
	var special: bool = mv.get("damageClass") == "special"
	var attack := _stat(att, "spa" if special else "atk")
	var defense := _stat(defender, "spd" if special else "def")
	if att.get("gmaxTurns", 0) == 0 and att.get("item") == ("Choice Specs" if special else "Choice Band"):
		attack = floori(attack * 1.5)
	if special and att.get("ability") == "Solar Power" and s.get("weather") == "쾌청":
		attack = floori(attack * 1.5)
	var power := int(mv["power"])
	if att.get("ability") == "Technician" and power <= 60 and not mv.get("typeless", false):
		power = floori(power * 1.5)
	var booster: String = { "Charcoal": "불꽃", "Magnet": "전기", "Sharp Beak": "비행", "Fairy Feather": "페어리", "Mystic Water": "물", "Black Glasses": "악", "Miracle Seed": "풀" }.get(att.get("item", ""), "")
	if booster == mv["type"]:
		power = floori(power * 1.2)
	if att.get("ability") == "Tough Claws" and mv.get("contact", false) and not mv.get("maxMove", false):
		power = floori(power * 1.3)
	if mv["type"] == "페어리" and (att.get("ability") == "Fairy Aura" or defender.get("ability") == "Fairy Aura"):
		power = floori(power * (4.0 / 3.0))
	var pinch_type: String = { "Blaze": "불꽃", "Overgrow": "풀", "Torrent": "물", "Swarm": "벌레" }.get(att.get("ability", ""), "")
	if pinch_type == mv["type"] and int(att["hp"]) * 3 <= int(att["max"]):
		power = floori(power * 1.5)
	if move_name(mv) == "Earthquake" and s.get("terrain") == "그래스필드" and _grounded(defender):
		power = floori(power * 0.5)
	if _grounded(att) and { "풀": "그래스필드", "전기": "일렉트릭필드", "에스퍼": "사이코필드" }.get(mv["type"], "") == s.get("terrain", "-"):
		power = roundi(power * 1.3)
	if special and "바위" in defender["types"] and s.get("weather") == "모래바람":
		defense = floori(defense * 1.5)
	if not special and "얼음" in defender["types"] and s.get("weather") == "눈":
		defense = floori(defense * 1.5)
	var base := floori(floori(22.0 * power * attack / defense) / 50.0) + 2
	var weather: String = s.get("weather", "")
	if (mv["type"] == "불꽃" and weather == "쾌청") or (mv["type"] == "물" and weather == "비"):
		base = floori(base * 1.5)
	elif (mv["type"] == "불꽃" and weather == "비") or (mv["type"] == "물" and weather == "쾌청"):
		base = floori(base * 0.5)
	var result := floori(base * roll / 100.0)
	if not mv.get("typeless", false) and mv["type"] in att["types"]:
		result = floori(result * (2.0 if att.get("ability") == "Adaptability" else 1.5))
	result = floori(result * multiplier)
	if not special and att.get("status") == "화상":
		result = floori(result * 0.5)
	if att.get("item") == "Life Orb":
		result = floori(result * 1.3)
	if defender.get("ability") == "Multiscale" and defender["hp"] == defender["max"] and att.get("ability") != "Mold Breaker":
		result = floori(result * 0.5)
	if defender["guard"]:
		return maxi(1, floori(result * 0.25)) if mv.get("maxMove", false) and defender.get("guardMove") != "max" else 0
	return maxi(1, result)

static func estimate(att: Dictionary, defender: Dictionary, mv: Dictionary, s := {}) -> float:
	return float(damage(att, defender, mv, 92, s) + damage(att, defender, mv, 93, s)) / 2.0

## 이 자리가 지금 할 수 있는 행동 [{k, id|to, ok, why}]
static func legal(s: Dictionary, seat: int) -> Array:
	var out := []
	if s["over"]:
		return out
	var side: Dictionary = s["sides"][seat]
	var need_phase := bool(s["sides"][0]["need"]) or bool(s["sides"][1]["need"])
	if not need_phase:
		var mon := active(s, seat)
		if mon.get("recharge", false):
			return [{ "k": "move", "id": "practice_recharge", "ok": true, "why": "" }]
		for id in mon["moves"]:
			var mv := move(mon["set"], str(id))
			var why := ""
			if mv.get("singlesUnavailable", false) and mon["gmaxTurns"] == 0:
				why = "더블 배틀 전용"
			if mon.get("charge", "") != "" and mon["charge"] != id:
				why = "충전 중인 기술"
			if id == "Fake Out" and not mon["fresh"] and mon["gmaxTurns"] == 0:
				why = "등장한 첫 턴에만 가능"
			if mon["choiceMove"] != "" and mon["choiceMove"] != id and int(mon["gmaxTurns"]) == 0:
				why = "구애 도구로 기술 고정"
			if int(mon["pp"].get(id, 0)) == 0 and mon.get("charge") != id:
				why = "PP 소진"
			out.append({ "k": "move", "id": str(id), "ok": why == "", "why": why })
		if not out.any(func(a): return a["ok"]):
			out.append({ "k": "move", "id": "practice_struggle", "ok": true, "why": "" })
	if (not need_phase and active(s, seat).get("charge", "") != "") or (need_phase and not side["need"]):
		return out
	var mon := active(s, seat)
	var trapped: bool = "고스트" not in mon["types"] and (mon.get("trapped", false) or (active(s, 1 - seat)["ability"] == "Shadow Tag" and mon["ability"] != "Shadow Tag"))
	for i in side["mons"].size():
		if i != int(side["active"]) and int(side["mons"][i]["hp"]) > 0 and (need_phase or not trapped):
			out.append({ "k": "swap", "to": i, "ok": true, "why": "" })
	return out

static func waiting_for(s: Dictionary, seat: int) -> bool:
	if s["over"]:
		return false
	var side: Dictionary = s["sides"][seat]
	var need_phase := bool(s["sides"][0]["need"]) or bool(s["sides"][1]["need"])
	if need_phase:
		return bool(side["need"]) and side["choice"] == null
	return side["choice"] == null

## 행동을 받는다. 필요한 선택이 모두 모이면 처리하고 사건 목록을 돌려준다 (아니면 빈 배열).
static func submit(s: Dictionary, seat: int, action: Dictionary) -> Array:
	if not waiting_for(s, seat):
		return []
	var ok := false
	for a in legal(s, seat):
		if a["ok"] and a["k"] == action.get("k") and str(a.get("id", "")) == str(action.get("id", "")) and int(a.get("to", -1)) == int(action.get("to", -1)):
			ok = true
	if not ok:
		return []
	var gimmick := str(action.get("gimmick", ""))
	if gimmick != "" and (action["k"] != "move" or gimmick not in _gimmicks(s, seat)):
		return []
	s["sides"][seat]["choice"] = action
	if waiting_for(s, 0) or waiting_for(s, 1):
		return []
	var need_phase := bool(s["sides"][0]["need"]) or bool(s["sides"][1]["need"])
	return _resolve_need(s) if need_phase else _resolve_turn(s)

static func _swap(s: Dictionary, seat: int, to: int, ev: Array) -> void:
	var side: Dictionary = s["sides"][seat]
	var old: Dictionary = side["mons"][int(side["active"])]
	for k in Data.RANK_STATS:
		old[k] = 0
	if int(old["gmaxTurns"]) > 0:
		_end_gmax(old, seat, ev)
	if old["ability"] == "Stance Change":
		_set_form(old, "base")
	old["slow"] = 0
	old["choiceMove"] = ""
	for flag in ["trapped", "leechSeed", "recharge", "quickGuard"]:
		old.erase(flag)
	old.erase("charge")
	old.erase("throatChop")
	old.erase("confusion")
	if old["ability"] == "Regenerator":
		old["hp"] = mini(int(old["max"]), int(old["hp"]) + floori(float(old["max"]) / 3.0))
	old["guard"] = false
	old["guardChain"] = 0
	side["active"] = to
	side["mons"][to]["seen"] = true
	side["mons"][to]["fresh"] = true
	ev.append({ "e": "swap", "seat": seat, "to": to, "id": side["mons"][to]["id"] })
	_enter(s, seat, ev)

static func _resolve_need(s: Dictionary) -> Array:
	var ev := []
	for seat in 2:
		var side: Dictionary = s["sides"][seat]
		if side["need"]:
			_swap(s, seat, int(side["choice"]["to"]), ev)
			side["need"] = false
		side["choice"] = null
	return ev

static func _resolve_turn(s: Dictionary) -> Array:
	var r := rules()
	var ev := [{ "e": "turn", "n": int(s["turn"]) }]
	# 순서: 교체(우선도 9) → 기술 우선도 → 스피드 → 무작위
	var order := []
	var switches := []
	for seat in 2:
		var selected: Dictionary = s["sides"][seat]["choice"]
		if selected["k"] == "swap":
			switches.append({ "seat": seat, "to": int(selected["to"]), "speed": _speed(s, seat), "tie": _rand(s) })
	switches.sort_custom(func(a, b): return a["speed"] > b["speed"] if a["speed"] != b["speed"] else a["tie"] > b["tie"])
	for entry in switches:
		_swap(s, int(entry["seat"]), int(entry["to"]), ev)
	for seat in 2:
		var option: Dictionary = s["sides"][seat]["choice"]
		if not str(option.get("gimmick", "")).is_empty():
			_transform(s, seat, option["gimmick"], ev)
	for seat in 2:
		var c: Dictionary = s["sides"][seat]["choice"]
		if c["k"] != "move":
			continue
		var pri := 0
		if c["k"] == "move":
			var mon := active(s, seat)
			var mv := _effective_move(s, mon, str(c["id"]))
			pri = int(mv.get("priority", 0))
			if mon["ability"] == "Prankster" and mv.get("power") == null and not mv.get("maxMove", false):
				pri += 1
			if mon["ability"] == "Gale Wings" and mv["type"] == "비행" and mon["hp"] == mon["max"]:
				pri += 1
		var speed := _speed(s, seat)
		order.append({ "seat": seat, "pri": pri, "spd": -speed if s["trickRoom"] > 0 and c["k"] == "move" else speed, "tie": _rand(s) })
	order.sort_custom(func(a, b):
		if a["pri"] != b["pri"]: return a["pri"] > b["pri"]
		if a["spd"] != b["spd"]: return a["spd"] > b["spd"]
		return a["tie"] > b["tie"])
	for o in order:
		var seat: int = o["seat"]
		var c: Dictionary = s["sides"][seat]["choice"]
		if int(active(s, seat)["hp"]) > 0 and not active(s, seat).get("flinch", false):
			_use(s, seat, str(c["id"]), ev)
		active(s, seat)["acted"] = true
	# 턴 끝: 그을음 피해와 지속 시간
	for seat in 2:
		var mon := active(s, seat)
		if int(mon["hp"]) > 0 and int(mon["dot"]) > 0:
			var d := maxi(1, int(float(mon["max"]) * float(r["dotPct"]) / 100.0))
			mon["hp"] = maxi(0, int(mon["hp"]) - d)
			ev.append({ "e": "dmg", "seat": seat, "amount": d, "hp": mon["hp"], "eff": "", "src": "dot" })
			mon["dot"] = int(mon["dot"]) - 1
		if int(mon["slow"]) > 0:
			mon["slow"] = int(mon["slow"]) - 1
		_end_turn(s, seat, ev)
		mon["guardChain"] = int(mon["guardChain"]) + 1 if mon["guard"] else 0
		mon["guard"] = false
		var side: Dictionary = s["sides"][seat]
		side["choice"] = null
	for key in ["weather", "terrain"]:
		if int(s[key + "Turns"]) > 0:
			s[key + "Turns"] -= 1
			if s[key + "Turns"] == 0:
				s[key] = ""
	s["trickRoom"] = maxi(0, int(s["trickRoom"]) - 1)
	_faints(s, ev)
	_check_over(s, ev)
	if not s["over"]:
		s["turn"] = int(s["turn"]) + 1
		if int(s["turn"]) > int(r["turnLimit"]):
			var ratio := [0.0, 0.0]
			for seat in 2:
				for m in s["sides"][seat]["mons"]:
					ratio[seat] += float(m["hp"]) / float(m["max"])
			s["over"] = true
			s["winner"] = -1 if is_equal_approx(ratio[0], ratio[1]) else (0 if ratio[0] > ratio[1] else 1)
			ev.append({ "e": "over", "winner": s["winner"], "why": "limit" })
	return ev

static func _heal(mon: Dictionary, seat: int, amount: int, ev: Array) -> void:
	amount = mini(amount, int(mon["max"]) - int(mon["hp"]))
	if amount > 0 and mon["hp"] > 0:
		mon["hp"] += amount
		ev.append({ "e": "heal", "seat": seat, "hp": mon["hp"], "amount": amount })

static func _end_turn(s: Dictionary, seat: int, ev: Array) -> void:
	var mon := active(s, seat)
	var side: Dictionary = s["sides"][seat]
	side["tailwind"] = maxi(0, int(side["tailwind"]) - 1)
	if mon["hp"] > 0:
		if mon["ability"] == "Moody":
			var up: String = Data.RANK_STATS[int(_rand(s) * Data.RANK_STATS.size())]
			var down: Array = Data.RANK_STATS.filter(func(k): return k != up)
			_stage(mon, seat, up, 2, ev)
			_stage(mon, seat, down[int(_rand(s) * down.size())], -1, ev)
		if mon["item"] == "Leftovers":
			_heal(mon, seat, maxi(1, floori(float(mon["max"]) / 16.0)), ev)
		if mon["ability"] == "Solar Power" and s["weather"] == "쾌청":
			_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 8.0)), ev, "weather")
		if s["terrain"] == "그래스필드" and _grounded(mon):
			_heal(mon, seat, maxi(1, floori(float(mon["max"]) / 16.0)), ev)
		if s["weather"] == "모래바람" and not mon["types"].any(func(t): return t in ["바위", "땅", "강철"]) and mon["ability"] != "Sand Rush":
			_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 16.0)), ev, "weather")
		if mon["status"] in ["화상", "독"]:
			_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / (16.0 if mon["status"] == "화상" else 8.0))), ev, "status")
	if int(side["gmaxResidualTurns"]) > 0:
		if side["gmaxResidual"] not in mon["types"]:
			_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 6.0)), ev, "거다이맥스")
		side["gmaxResidualTurns"] -= 1
	if int(mon["gmaxTurns"]) > 0:
		mon["gmaxTurns"] -= 1
		if mon["gmaxTurns"] == 0:
			_end_gmax(mon, seat, ev)
	if mon.get("leechSeed", false):
		var amount := maxi(1, floori(float(mon["max"]) / 8.0))
		amount = mini(amount, int(mon["hp"]))
		_chip_damage(mon, seat, amount, ev, "seed")
		_heal(active(s, 1 - seat), 1 - seat, amount, ev)
	if mon.get("throatChop", 0) > 0:
		mon["throatChop"] -= 1
	if mon.get("acted", false):
		mon["fresh"] = false
	mon["acted"] = false
	mon["flinch"] = false
	mon["quickGuard"] = false

static func _chip_damage(mon: Dictionary, seat: int, amount: int, ev: Array, source: String) -> void:
	if mon["hp"] > 0:
		mon["hp"] = maxi(0, int(mon["hp"]) - amount)
		ev.append({ "e": "dmg", "seat": seat, "amount": amount, "hp": mon["hp"], "eff": "", "src": source })

static func _effective_move(s: Dictionary, mon: Dictionary, id: String) -> Dictionary:
	var mv := move(mon["set"], id).duplicate()
	if mon["ability"] in ["Pixilate", "Aerilate", "Refrigerate", "Dragonize"] and mv.get("power") != null and mv["type"] == "노말" and not mv.get("typeless", false):
		mv["type"] = { "Pixilate": "페어리", "Aerilate": "비행", "Refrigerate": "얼음", "Dragonize": "드래곤" }[mon["ability"]]
		mv["power"] = floori(int(mv["power"]) * 1.2)
	if id == "Last Respects":
		var side: Dictionary = s["sides"][int(mon["seat"])]
		mv["power"] = 50 + 50 * side["mons"].filter(func(x): return x.get("hp", 1) <= 0).size()
	if id == "Stomping Tantrum" and mon.get("lastFailed", false):
		mv["power"] = 150
	if id == "Acrobatics" and (mon["item"] == "" or mon["itemUsed"]):
		mv["power"] = 110
	if id == "Weather Ball" and s.get("weather", "") != "":
		mv["power"] = 100
		mv["type"] = { "쾌청": "불꽃", "비": "물", "모래바람": "바위", "눈": "얼음" }.get(s["weather"], "노말")
	if mon["form"] == "gmax" and id in mon["moves"]:
		mv["maxMove"] = true
		mv["accuracy"] = 100
		if mv.get("power") == null:
			mv["ko"] = "다이월"
			mv["desc"] = "이번 턴 공격 기술과 다이맥스 기술을 막습니다."
			mv["priority"] = 4
			mv["effects"] = [{ "kind": "guard" }]
		else:
			mv["ko"] = "다이맥스 " + str(mv["type"])
			mv["priority"] = 0
			var power := int(mv["power"])
			mv["power"] = 90 if power < 65 else (120 if power < 85 else (130 if power < 110 else 140))
			var weather: String = { "불꽃": "쾌청", "물": "비", "바위": "모래바람", "얼음": "눈" }.get(mv["type"], "")
			var terrain: String = { "풀": "그래스필드", "전기": "일렉트릭필드", "에스퍼": "사이코필드", "페어리": "미스트필드" }.get(mv["type"], "")
			var raised: String = { "격투": "atk", "강철": "def", "독": "spa", "땅": "spd", "비행": "spe" }.get(mv["type"], "")
			var lowered: String = { "드래곤": "atk", "고스트": "def", "벌레": "spa", "악": "spd", "노말": "spe" }.get(mv["type"], "")
			if weather != "":
				mv["effects"] = [{ "kind": "weather", "value": weather }]
			elif terrain != "":
				mv["effects"] = [{ "kind": "terrain", "value": terrain }]
			elif raised != "":
				mv["effects"] = [{ "kind": "buff", "stat": raised, "stages": 1 }]
			elif lowered != "":
				mv["effects"] = [{ "kind": "debuff", "stat": lowered, "stages": 1 }]
			else:
				mv["effects"] = []
			if [mon["id"], mv["type"]] in [["charizard", "불꽃"], ["venusaur", "풀"], ["gengar", "고스트"], ["rillaboom", "풀"]]:
				mv["ko"] = { "charizard": "거다이옥염", "venusaur": "거다이편달", "gengar": "거다이환영", "rillaboom": "거다이난타" }[mon["id"]]
				if mon["id"] in ["charizard", "venusaur"]:
					mv["effects"] = [{ "kind": "gmaxResidual", "type": mv["type"] }]
				if mon["id"] == "gengar":
					mv["effects"] = [{ "kind": "trap" }]
				if mon["id"] == "rillaboom":
					mv["power"] = 160
					mv["effects"] = []
			mv["desc"] = "변신 위력 %d." % int(mv["power"])
	return mv

static func _use(s: Dictionary, seat: int, move_id: String, ev: Array) -> void:
	var side: Dictionary = s["sides"][seat]
	var foe_seat := 1 - seat
	var foe_side: Dictionary = s["sides"][foe_seat]
	var mon := active(s, seat)
	var foe := active(s, foe_seat)
	if mon.get("recharge", false):
		mon["recharge"] = false
		ev.append({ "e": "status", "seat": seat, "what": "반동으로 쉬었다" })
		return
	var mv := _effective_move(s, mon, move_id)
	mon["lastFailed"] = true
	if mon.get("throatChop", 0) > 0 and mv.get("sound", false):
		ev.append({ "e": "status", "seat": seat, "what": "소리 기술을 사용할 수 없다" })
		return
	if mon["ability"] == "Stance Change" and (move_id == "King's Shield" or mv.get("power") != null):
		var form := "base" if move_id == "King's Shield" else "blade"
		if form != mon["form"]:
			_set_form(mon, form)
			ev.append({ "e": "transform", "seat": seat, "mon": mon.duplicate(true), "what": "배틀스위치" })
	if mon["sleep"] > 0:
		mon["sleep"] -= 1
		ev.append({ "e": "status", "seat": seat, "what": "잠들어 있다" })
		return
	if mon.get("confusion", 0) > 0:
		mon["confusion"] -= 1
		if _rand(s) < 1.0 / 3.0:
			_chip_damage(mon, seat, floori(22.0 * 40 * _stat(mon, "atk") / _stat(mon, "def") / 50.0) + 2, ev, "혼란")
			return
	if mon["status"] == "마비" and _rand(s) < 0.125:
		ev.append({ "e": "status", "seat": seat, "what": "마비로 움직이지 못했다" })
		return
	if move_id in mon["moves"] and mon["item"] in ["Choice Scarf", "Choice Specs", "Choice Band"] and not mv.get("maxMove", false):
		mon["choiceMove"] = move_id
	var charged: bool = mon.get("charge") == move_id
	if not charged and move_id in mon["pp"]:
		var pressure: bool = foe["ability"] == "Pressure" and mv.get("target", "") in ["normal", "any", "allAdjacentFoes", "allAdjacent", "foeSide", "all"]
		mon["pp"][move_id] = maxi(0, int(mon["pp"][move_id]) - (2 if pressure else 1))
	mon.erase("charge")
	ev.append({ "e": "use", "seat": seat, "move": move_id, "name": mv["ko"] })
	if not mv.get("maxMove", false) and move_id in ["Solar Beam", "Electro Shot"]:
		if not charged and move_id == "Electro Shot":
			_stage(mon, seat, "spa", 1, ev)
		var weather_skip: bool = (move_id == "Solar Beam" and s["weather"] == "쾌청") or (move_id == "Electro Shot" and s["weather"] == "비")
		if not charged and not weather_skip:
			mon["charge"] = move_id
			ev.append({ "e": "status", "seat": seat, "what": "힘을 모으고 있다" })
			return
	var accuracy := int(mv.get("accuracy", 100))
	if move_id in ["Thunder", "Hurricane"] and s["weather"] == "비":
		accuracy = 100
	if mon["ability"] != "No Guard" and foe["ability"] != "No Guard" and _rand(s) * 100.0 >= accuracy:
		ev.append({ "e": "status", "seat": seat, "what": "기술이 빗나갔다" })
		return
	var priority := int(mv.get("priority", 0))
	if mon["ability"] == "Prankster" and mv.get("power") == null:
		priority += 1
	if mon["ability"] == "Gale Wings" and mv["type"] == "비행" and mon["hp"] == mon["max"]:
		priority += 1
	if priority > 0 and (foe.get("quickGuard", false) or (s["terrain"] == "사이코필드" and _grounded(foe))) and mv.get("target", "") in ["normal", "allAdjacentFoes", "allAdjacent"]:
		ev.append({ "e": "status", "seat": foe_seat, "what": "우선도 기술을 막았다" })
		return
	if move_id == "Feint":
		foe["guard"] = false
	if move_id == "Sucker Punch":
		var option = foe_side["choice"]
		if option == null or option.get("k") != "move" or foe.get("acted", false) or move(foe["set"], str(option.get("id", ""))).get("power") == null:
			ev.append({ "e": "status", "seat": seat, "what": "기습이 실패했다" })
			return
	if move_id == "Poltergeist" and (foe["item"] == "" or foe["itemUsed"]):
		ev.append({ "e": "status", "seat": seat, "what": "상대가 지닌 도구가 없다" })
		return
	if mon["ability"] == "Prankster" and mv.get("power") == null and mv.get("target", "") == "normal" and "악" in foe["types"]:
		ev.append({ "e": "status", "seat": foe_seat, "what": "효과가 없다" })
		return
	if move_id in ["Sleep Powder", "Rage Powder"] and "풀" in foe["types"]:
		ev.append({ "e": "status", "seat": foe_seat, "what": "가루 기술이 통하지 않는다" })
		return
	if foe["guard"] and not mv.get("maxMove", false) and (mv.get("power") != null or (mv.get("target", "") == "normal" and foe.get("guardMove") != "King's Shield")):
		if mv.get("contact", false) and foe.get("guardMove") == "King's Shield":
			_stage(mon, seat, "atk", -1, ev, true)
		if mv.get("contact", false) and foe.get("guardMove") == "Spiky Shield":
			_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 8.0)), ev, "반동")
		ev.append({ "e": "status", "seat": foe_seat, "what": "방어했다" })
		return
	var dealt := 0
	if mv.get("power") != null and int(foe["hp"]) > 0:
		var eff: Array = [1.0, ""] if mv.get("typeless", false) else effectiveness(str(mv["type"]), foe, mon)
		var weight := float(Data.form(foe["set"], foe["id"], foe["form"]).get("weightKg", 0))
		if move_id in ["Grass Knot", "Low Kick", "Heavy Slam"] and not mv.get("maxMove", false) and foe["gmaxTurns"] > 0:
			ev.append({ "e": "status", "seat": foe_seat, "what": "거다이맥스 상대에게 통하지 않는다" })
			return
		if move_id in ["Grass Knot", "Low Kick"] and not mv.get("maxMove", false):
			mv["power"] = 120 if weight >= 200 else (100 if weight >= 100 else (80 if weight >= 50 else (60 if weight >= 25 else (40 if weight >= 10 else 20))))
		if move_id == "Heavy Slam" and not mv.get("maxMove", false):
			var ratio := float(Data.form(mon["set"], mon["id"], mon["form"]).get("weightKg", 0)) / maxf(0.1, weight)
			mv["power"] = 120 if ratio >= 5 else (100 if ratio >= 4 else (80 if ratio >= 3 else (60 if ratio >= 2 else 40)))
		if move_id == "Knock Off" and foe["item"] != "" and not foe["itemUsed"] and foe["mega"] == "":
			mv["power"] = floori(int(mv["power"]) * 1.5)
		dealt = damage(mon, foe, mv, 85 + int(_rand(s) * 16.0), s)
		if move_id == "Dual Wingbeat" and int(dealt) > 0 and not mv.get("maxMove", false):
			dealt += damage(mon, foe, mv, 85 + int(_rand(s) * 16.0), s)
		if move_id == "Super Fang" and int(dealt) > 0:
			dealt = maxi(1, floori(float(foe["hp"]) / 2.0))
		var resist_berry: String = { "Chople Berry": "격투", "Passho Berry": "물", "Kasib Berry": "고스트", "Occa Berry": "불꽃", "Haban Berry": "드래곤" }.get(foe["item"], "")
		if resist_berry == mv["type"] and float(eff[0]) > 1.0 and not foe["itemUsed"] and mon["ability"] != "Unnerve":
			foe["itemUsed"] = true
			dealt = maxi(1, floori(dealt * 0.5))
		var sturdy: bool = foe["ability"] == "Sturdy" and mon["ability"] != "Mold Breaker"
		if dealt >= int(foe["hp"]) and foe["hp"] == foe["max"] and (sturdy or (foe["item"] == "Focus Sash" and not foe["itemUsed"])):
			dealt = int(foe["hp"]) - 1
			if not sturdy:
				foe["itemUsed"] = true
			ev.append({ "e": "status", "seat": foe_seat, "what": "쓰러지지 않고 버텼다" })
		dealt = mini(dealt, int(foe["hp"]))
		foe["hp"] = int(foe["hp"]) - dealt
		ev.append({ "e": "dmg", "seat": foe_seat, "amount": dealt, "hp": foe["hp"], "eff": eff[1], "guard": foe["guard"] })
		if dealt == 0:
			return
		if foe["ability"] == "Toxic Debris" and mv.get("damageClass") == "physical":
			side["toxicSpikes"] = mini(2, int(side.get("toxicSpikes", 0)) + 1)
		if foe["ability"] == "Stamina" and mon["ability"] != "Mold Breaker":
			_stage(foe, foe_seat, "def", 1, ev)
		if (foe["ability"] == "Weak Armor" or foe["ability"] == "Weak Armour") and mv.get("damageClass") == "physical":
			_stage(foe, foe_seat, "def", -1, ev)
			_stage(foe, foe_seat, "spe", 2, ev)
		if foe["ability"] == "Spicy Spray" and mon["ability"] != "Mold Breaker":
			_apply_status(mon, seat, "화상", ev)
		if mv.get("contact", false) and not mv.get("maxMove", false):
			if foe["ability"] == "Rough Skin":
				_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 8.0)), ev, "반동")
			if foe["item"] == "Rocky Helmet":
				_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 6.0)), ev, "item")
		if mon["item"] == "Life Orb":
			_chip_damage(mon, seat, maxi(1, floori(float(mon["stats"]["hp"]) / 10.0)), ev, "item")
	mon["lastFailed"] = false
	for e in mv.get("effects", []):
		if (foe["ability"] == "Shield Dust" and e.has("chance") and e["kind"] != "recoil") or _rand(s) * 100.0 >= int(e.get("chance", 100)):
			continue
		match str(e["kind"]):
			"randomStatus":
				_apply_status(foe, foe_seat, ["독", "마비", "잠듦"][int(_rand(s) * 3.0)], ev)
			"knockOff":
				if foe["mega"] == "":
					foe["item"] = ""
					foe["itemUsed"] = true
			"confuse":
				if foe["hp"] > 0 and foe["ability"] != "Own Tempo" and foe.get("confusion", 0) == 0:
					foe["confusion"] = 2 + int(_rand(s) * 4)
					ev.append({ "e": "status", "seat": foe_seat, "what": "혼란" })
			"bugBite":
				if str(foe["item"]).ends_with(" Berry") and not foe["itemUsed"]:
					foe["itemUsed"] = true
					if foe["item"] == "Sitrus Berry":
						_heal(mon, seat, floori(float(mon["max"]) / 4.0), ev)
					ev.append({ "e": "status", "seat": seat, "what": "상대의 나무열매를 먹었다" })
			"gmaxResidual":
				foe_side["gmaxResidual"] = e["type"]
				foe_side["gmaxResidualTurns"] = 4
			"trap":
				if "고스트" not in foe["types"]:
					foe["trapped"] = true
			"leechSeed":
				foe["leechSeed"] = "풀" not in foe["types"]
			"recharge":
				mon["recharge"] = true
			"struggle":
				_chip_damage(mon, seat, maxi(1, floori(float(mon["max"]) / 4.0)), ev, "반동")
			"priorityGuard":
				mon["quickGuard"] = true
			"throatChop":
				foe["throatChop"] = 2
			"pivot":
				if mon["hp"] > 0 and side["mons"].any(func(x): return x != mon and x["hp"] > 0):
					side["need"] = true
			"tailwind":
				side["tailwind"] = 4
				ev.append({ "e": "field", "what": "순풍" })
			"trickRoom":
				s["trickRoom"] = 0 if s["trickRoom"] > 0 else 5
				ev.append({ "e": "field", "what": "트릭룸" })
			"weather", "terrain":
				_field(s, str(e["kind"]), str(e["value"]), ev)
			"status":
				_apply_status(foe, foe_seat, str(e["status"]), ev)
			"flinch":
				if foe["ability"] != "Inner Focus" and (not e.get("firstTurn", false) or mon["fresh"]):
					foe["flinch"] = true
			"selfStages":
				for stat in e["stats"]:
					_stage(mon, seat, str(stat), int(e["stats"][stat]), ev)
			"dot":
				if int(foe["hp"]) > 0:
					foe["dot"] = int(e["turns"])
					ev.append({ "e": "status", "seat": foe_seat, "what": "그을음" })
			"slow":
				if int(foe["hp"]) > 0:
					foe["slow"] = int(e["turns"])
					ev.append({ "e": "status", "seat": foe_seat, "what": "둔화" })
			"heal", "lifesteal":
				var amount := int(float(mon["max"]) * float(e["pct"]) / 100.0) if e["kind"] == "heal" else int(dealt * float(e["pct"]) / 100.0)
				amount = mini(amount, int(mon["max"]) - int(mon["hp"]))
				if amount > 0:
					mon["hp"] = int(mon["hp"]) + amount
					ev.append({ "e": "heal", "seat": seat, "amount": amount, "hp": mon["hp"] })
			"recoil":
				var rc := maxi(1, int(dealt * float(e["pct"]) / 100.0))
				mon["hp"] = maxi(0, int(mon["hp"]) - rc)
				ev.append({ "e": "dmg", "seat": seat, "amount": rc, "hp": mon["hp"], "eff": "", "src": "recoil" })
			"buff", "debuff":
				var targets_self: bool = e["kind"] == "buff"
				if not targets_self and foe["ability"] in ["Clear Body", "White Smoke"]:
					continue
				if not targets_self and foe["ability"] == "Mirror Armor":
					_stage(mon, seat, str(e["stat"]), -int(e["stages"]), ev, true)
					continue
				var sign := 1 if targets_self else -1
				_stage(mon if targets_self else foe, seat if targets_self else foe_seat, str(e["stat"]), sign * int(e["stages"]), ev, not targets_self)
			"guard":
				if mon["guardChain"] > 0 and _rand(s) >= pow(1.0 / 3.0, int(mon["guardChain"])):
					mon["lastFailed"] = true
					ev.append({ "e": "status", "seat": seat, "what": "방어에 실패했다" })
					continue
				mon["guard"] = true
				mon["guardMove"] = "max" if mv.get("maxMove", false) else move_id
				ev.append({ "e": "status", "seat": seat, "what": "수비 태세" })
	for check in [[mon, seat], [foe, foe_seat]]:
		var holder: Dictionary = check[0]
		if holder["item"] == "White Herb" and not holder["itemUsed"] and Data.RANK_STATS.any(func(key): return holder[key] < 0):
			holder["itemUsed"] = true
			for key in Data.RANK_STATS:
				if holder[key] < 0:
					holder[key] = 0
			ev.append({ "e": "status", "seat": check[1], "what": "하양허브로 능력 저하를 회복했다" })
	if foe["item"] == "Sitrus Berry" and not foe["itemUsed"] and mon["ability"] != "Unnerve" and foe["hp"] > 0 and int(foe["hp"]) * 2 <= int(foe["max"]):
		foe["itemUsed"] = true
		_heal(foe, foe_seat, floori(float(foe["max"]) / 4.0), ev)
	_faints(s, ev)

static func _apply_status(mon: Dictionary, seat: int, status: String, ev: Array) -> void:
	if mon["hp"] <= 0 or mon["status"] != "" or mon["sleep"] > 0:
		return
	if (status == "화상" and "불꽃" in mon["types"]) or (status == "독" and ("독" in mon["types"] or "강철" in mon["types"])) or (status == "마비" and "전기" in mon["types"]):
		return
	if status == "잠듦":
		if mon["ability"] in ["Insomnia", "Vital Spirit"] or mon["gmaxTurns"] > 0:
			return
		mon["sleep"] = 1
	else:
		mon["status"] = status
	ev.append({ "e": "status", "seat": seat, "what": status })

## 쓰러진 몬스터를 기록하고 교체가 필요한 자리를 표시한다.
static func _faints(s: Dictionary, ev: Array) -> void:
	for seat in 2:
		var side: Dictionary = s["sides"][seat]
		var mon := active(s, seat)
		if int(mon["hp"]) > 0 or mon.get("down", false):
			continue
		mon["down"] = true
		ev.append({ "e": "faint", "seat": seat })
		var alive := false
		for m in side["mons"]:
			if int(m["hp"]) > 0:
				alive = true
		if alive:
			side["need"] = true

static func _check_over(s: Dictionary, ev: Array) -> void:
	var dead := [true, true]
	for seat in 2:
		for m in s["sides"][seat]["mons"]:
			if int(m["hp"]) > 0:
				dead[seat] = false
	if dead[0] or dead[1]:
		s["over"] = true
		s["winner"] = -1 if dead[0] and dead[1] else (1 if dead[0] else 0)
		s["sides"][0]["need"] = false
		s["sides"][1]["need"] = false
		ev.append({ "e": "over", "winner": s["winner"], "why": "ko" })
	else:
		for seat in 2:
			if s["sides"][seat]["need"]:
				ev.append({ "e": "need", "seat": seat })

## 이 자리에 보여 줄 상태. 상대가 아직 내보내지 않은 몬스터는 가린다.
static func view(s: Dictionary, seat: int) -> Dictionary:
	var sides := []
	for i in 2:
		var side: Dictionary = s["sides"][i]
		var mons := []
		for m in side["mons"]:
			if i != seat and not m["seen"]:
				mons.append({ "hidden": true })
			else:
				mons.append(m.duplicate(true))
		sides.append({ "tailwind": side["tailwind"], "gmaxResidual": side["gmaxResidual"], "gmaxResidualTurns": side["gmaxResidualTurns"], "active": side["active"], "mons": mons, "need": side["need"], "chosen": side["choice"] != null })
	return { "turn": s["turn"], "over": s["over"], "winner": s["winner"], "sides": sides,
		"legal": legal(s, seat), "waiting": waiting_for(s, seat), "gimmicks": _gimmicks(s, seat), "weather": s["weather"], "weatherTurns": s["weatherTurns"], "terrain": s["terrain"], "terrainTurns": s["terrainTurns"], "trickRoom": s["trickRoom"] }
