class_name BBot
## 연습용 AI: 예상 피해가 큰 기술을 고르고, 체력 상황에 따라 보조 기술을 쓴다.

static func pick_team(set_id: String) -> String:
	var teams: Array = Data.sets[set_id]["teams"]
	return str(teams[randi() % teams.size()]["id"])

## 팀 6마리 중 n 마리의 번호를 고른다 (상대 팀에 대한 속성 상성이 좋은 순, 약간의 무작위)
static func pick_members(set_id: String, team_id: String, foe_team_id: String, n: int) -> Array:
	var team := Data.team(set_id, team_id)
	var members: Array = team["members"]
	if team_id.begins_with("singles-"):
		return range(n)
	var idx := range(members.size())
	var foes: Array = Data.team(set_id, foe_team_id)["members"]
	var score := {}
	for i in idx:
		var types := Data.types(set_id, members[i]["species"], members[i]["form"])
		var v := randf() * 1.5
		for f in foes:
			var foe_types := Data.types(set_id, f["species"], f["form"])
			v += TypeChart.edge(types, foe_types)
		score[i] = v
	idx.sort_custom(func(a, b): return score[a] > score[b])
	return idx.slice(0, n)

static func choose(s: Dictionary, seat: int) -> Dictionary:
	var acts: Array = BEngine.legal(s, seat).filter(func(a): return a["ok"])
	if acts.is_empty():
		return {}
	var side: Dictionary = s["sides"][seat]
	var me := BEngine.active(s, seat)
	var foe := BEngine.active(s, 1 - seat)
	var best := {}
	var best_v := -INF
	for a in acts:
		var v := randf() * 6.0
		if a["k"] == "swap":
			var cand: Dictionary = side["mons"][int(a["to"])]
			if side["need"]:
				v += float(cand["hp"]) / float(cand["max"]) * 20.0
				v += (float(BEngine.effectiveness(BEngine._type_of(cand), foe)[0]) - float(BEngine.effectiveness(BEngine._type_of(foe), cand)[0])) * 30.0
			elif me["id"] == "indeedee" and cand["id"] == "blastoise" and s["terrain"] == "사이코필드" and s["terrainTurns"] >= 4:
				v += 55.0 if float(BEngine.effectiveness(BEngine._type_of(foe), cand)[0]) <= 1.0 else 0.0
			else:
				# 상성이 나쁘고 체력이 남아 있을 때만 가끔 교체
				var bad := float(BEngine.effectiveness(BEngine._type_of(foe), me)[0]) > 1.0
				v += 22.0 if bad and float(me["hp"]) / float(me["max"]) > 0.5 else -30.0
		else:
			var mv := BEngine.preview_move(s, me, str(a["id"]), "")
			var dmg := BEngine.estimate(me, foe, mv, s)
			if mv.get("power") != null and dmg == 0.0:
				continue
			v += dmg
			if dmg >= float(foe["hp"]):
				v += 60.0
			for e in mv.get("effects", []):
				match str(e["kind"]):
					"revival":
						var target: Dictionary = side["mons"][int(a["target"])]
						v += 100.0 if target["id"] == "banette" else 70.0
					"destinyBond":
						v += 55.0 if not me.get("destinyBond", false) and int(me["hp"]) * 2 <= int(me["max"]) else -30.0
					"selfStages":
						if a["id"] == "Shell Smash" and int(me["spa"]) < 2 and int(me["hp"]) * 2 > int(me["max"]):
							v += 55.0
					"heal", "weatherHeal":
						v += 70.0 if float(me["hp"]) / float(me["max"]) < 0.45 else -20.0
					"buff":
						v += 28.0 if int(me[e["stat"]]) < 1 and float(me["hp"]) / float(me["max"]) > 0.6 else -10.0
					"guard":
						v += 4.0 if me["guardChain"] == 0 else -15.0
					"dot":
						v += 10.0 if int(foe["dot"]) == 0 else -8.0
					"slow":
						v += 12.0 if int(foe["slow"]) == 0 else -8.0
		if v > best_v:
			best_v = v
			best = a
	var action: Dictionary = (best if not best.is_empty() else acts[0]).duplicate()
	var options := BEngine._gimmicks(s, seat)
	if action["k"] == "move" and not options.is_empty() and not action.has("target"):
		action["gimmick"] = options[0]
	return action
