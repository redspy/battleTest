extends Control
## 앱 진입점: 화면 스택을 준비하고 첫 화면을 띄운다.
## 실행 인자 (PC 확인용, `Godot --headless --path godot -- <인자>`):
##   --selftest   화면을 차례로 열어 보고, AI 끼리 대전을 여러 판 돌린 뒤 종료
##   --shots      화면을 차례로 열며 user://shot_*.png 로 저장 (창이 있어야 함)

func _ready() -> void:
	var stack := Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.clip_contents = true
	add_child(stack)
	Nav.setup(stack)
	Nav.push(HomeScreen.new(), false)
	var args := OS.get_cmdline_user_args()
	if "--selftest" in args:
		_selftest.call_deferred()
	if "--specialtest" in args:
		_specialtest_only.call_deferred()
	if "--shots" in args:
		_shots.call_deferred()
	var ni := args.find("--nettest")
	if ni >= 0 and args.size() > ni + 1:
		_nettest.call_deferred(args[ni + 1])

## 두 기기 연결 자가 테스트: 한쪽은 `--nettest host`, 다른 쪽은 `--nettest 127.0.0.1`
## 로비 → 팀·준비 → 선출 → 대전 종료 를 자동으로 진행한다.
func _nettest(target: String) -> void:
	var tag := "[nettest %s]" % ("host" if target == "host" else "join")
	var err := Net.start("host") if target == "host" else Net.join(target)
	if err != "":
		print("%s 시작 실패: %s" % [tag, err])
		get_tree().quit(1)
		return
	var six := "--six" in OS.get_cmdline_user_args()
	if target == "host" and six:
		Net.send({"t": "rules", "pickCount": Net.FULL_TEAM_COUNT, "allowGmax": false})
	var sent := ""
	var acts := 0
	for i in 600:
		await _wait(0.05)
		var v: Dictionary = Net.view
		if v.is_empty() or not v["players"][1]["here"]:
			continue
		var me: Dictionary = v["players"][int(v["seat"])]
		match str(v["phase"]):
			"lobby":
				if me["team"] == "":
					Net.send({ "t": "team", "id": Data.sets[Net.SET_ID]["teams"][int(v["seat"])]["id"] })
				elif not me["ready"]:
					Net.send({ "t": "ready", "v": true })
			"pick":
				if not me["picked"] and sent != "picks":
					sent = "picks"
					Net.send({ "t": "picks", "picks": range(int(Net.view.get("pickCount", Net.DEFAULT_PICK_COUNT))) })
			"battle":
				if six and (int(v["pickCount"]) != Net.FULL_TEAM_COUNT or bool(v["allowGmax"]) or v["battle"]["sides"][0]["mons"].size() != Net.FULL_TEAM_COUNT):
					print("%s 6인 규칙 동기화 실패" % tag)
					get_tree().quit(1)
					return
				if v["battle"]["over"]:
					print("%s 대전 끝: 승자 자리 %d, 내 자리 %d, 턴 %d, 내 입력 %d번" % [tag, int(v["battle"]["winner"]), int(v["seat"]), int(v["battle"]["turn"]), acts])
					await _wait(0.5)
					get_tree().quit(0)
					return
				if v["battle"]["waiting"]:
					var legal: Array = (v["battle"]["legal"] as Array).filter(func(x): return x["ok"])
					acts += 1
					Net.send({ "t": "act", "a": legal[randi() % legal.size()] })
	print("%s 시간 초과 (단계 %s)" % [tag, Net.view.get("phase", "연결 안 됨")])
	get_tree().quit(1)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _specialtest_only() -> void:
	var ok := _specialtest()
	print("[specialtest] ", ok)
	get_tree().quit(0 if ok else 1)

func _specialtest() -> bool:
	var team := Data.team(Net.SET_ID, "ptc26-1")
	var charizard: Dictionary = team["members"].filter(func(m): return m["species"] == "charizard")[0]
	var incineroar: Dictionary = team["members"].filter(func(m): return m["species"] == "incineroar")[0]
	var mega := BEngine.create([charizard], [incineroar], 2)
	var mon := BEngine.active(mega, 0)
	if mon["form"] != "base" or BEngine.view(mega, 0)["gimmicks"] != ["mega"]:
		return false
	BEngine.submit(mega, 0, { "k": "move", "id": "Protect", "gimmick": "mega" })
	BEngine.submit(mega, 1, { "k": "move", "id": "Flare Blitz" })
	if mon["form"] != "megay" or mega["weather"] != "쾌청" or not BEngine.view(mega, 0)["gimmicks"].is_empty():
		return false
	var gmax := BEngine.create([charizard], [incineroar], 2, Net.SET_ID, true)
	var giant := BEngine.active(gmax, 0)
	var normal_hp := int(giant["hp"])
	if not ("gmax" in BEngine.view(gmax, 0)["gimmicks"]):
		return false
	BEngine._transform(gmax, 0, "gmax", [])
	if giant["max"] != normal_hp * 2 or BEngine.preview_move(gmax, giant, "Heat Wave", "")["ko"] != "거다이옥염":
		return false
	for i in 3:
		BEngine._end_turn(gmax, 0, [])
	if giant["form"] != "base" or giant["max"] != normal_hp:
		return false
	var events: Array = Data.sets[Net.SET_ID]["info"]["events"]
	if events.filter(func(event): return event["id"] != "CUSTOM").slice(0, 2).map(func(event): return event["id"]) != ["SINGLES", "PTC26"]:
		return false
	var members := 0
	for t in Data.sets[Net.SET_ID]["teams"]:
		if t["event"] != "PTC26":
			continue
		if t["members"].size() != 6:
			return false
		for member in t["members"]:
			members += 1
			for id in member["moves"]:
				if BEngine.move(Net.SET_ID, id).is_empty():
					return false
	return members == 48

func _pp_test() -> bool:
	var member := { "species": "charizard", "moves": ["Protect", "Solar Beam"] }
	var defender := { "species": "charizard", "ability": "Pressure", "moves": ["Protect"] }
	var state := BEngine.create([member, member], [defender], 13)
	var actor := BEngine.active(state, 0)
	var events := []
	if int(actor["pp"]["Protect"]) != 8:
		return false
	BEngine._use(state, 0, "Protect", events)
	if int(actor["pp"]["Protect"]) != 7:
		return false
	var beam_pp := int(actor["pp"]["Solar Beam"])
	BEngine._use(state, 0, "Solar Beam", events)
	if actor.get("charge", "") != "Solar Beam" or int(actor["pp"]["Solar Beam"]) != beam_pp - 2:
		return false
	BEngine._use(state, 0, "Solar Beam", events)
	if int(actor["pp"]["Solar Beam"]) != beam_pp - 2:
		return false
	BEngine._field(state, "weather", "비", events)
	var view := BEngine.view(state, 0)
	if view["weather"] != "비" or view["weatherTurns"] != 5:
		return false
	actor["pp"]["Solar Beam"] = 0
	actor["pp"]["Protect"] = 0
	if view["sides"][0]["mons"][0]["pp"]["Protect"] != 7:
		return false
	var legal := BEngine.legal(state, 0).filter(func(action): return action["ok"] and action["k"] == "move")
	if legal.size() != 1 or legal[0]["id"] != "practice_struggle":
		return false
	BEngine._swap(state, 0, 1, events)
	BEngine._swap(state, 0, 0, events)
	return int(actor["pp"]["Protect"]) == 0

func _singles_test() -> bool:
	var terrain_team: Dictionary = Data.team(Net.SET_ID, "singles-1")
	var revival_team: Dictionary = Data.team(Net.SET_ID, "singles-2")
	var attacker := { "species": "garchomp", "moves": ["Earthquake", "Protect"] }
	var events := []
	var terrain := BEngine.create(terrain_team["members"].slice(0, 3), [attacker], 7)
	if terrain["terrain"] != "사이코필드" or terrain["terrainTurns"] != 8:
		return false
	var field_view := BEngine.view(terrain, 0)
	if not str(field_view["effectSources"]["terrain"]).contains("사이코메이커") or not str(field_view["effectSources"]["terrain"]).contains("그라운드코트"):
		return false
	BEngine._swap(terrain, 0, 1, events)
	BEngine._transform(terrain, 0, "mega", events)
	var blastoise := BEngine.active(terrain, 0)
	BEngine._use(terrain, 0, "Shell Smash", events)
	var pulse := BEngine.preview_move(terrain, blastoise, "Terrain Pulse", "")
	if blastoise["form"] != "mega" or blastoise["spa"] != 2 or blastoise["def"] != -1 or pulse["type"] != "에스퍼" or pulse["power"] != 100:
		return false
	var staged: Array = BEngine.view(terrain, 0)["sides"][0]["mons"][1]["stageHistory"]
	if staged.size() != 5 or not staged.all(func(event): return str(event["source"]).contains("껍질깨기")):
		return false
	BEngine._swap(terrain, 0, 0, events)
	if not blastoise["stageHistory"].is_empty() or staged.size() != 5:
		return false
	var revival := BEngine.create(revival_team["members"].slice(0, 3), [attacker, attacker], 7)
	var banette := BEngine.active(revival, 0)
	banette["hp"] = 1
	BEngine.submit(revival, 0, { "k": "move", "id": "Destiny Bond", "gimmick": "mega" })
	BEngine.submit(revival, 1, { "k": "move", "id": "Earthquake" })
	if not revival["sides"][0]["need"] or not revival["sides"][1]["need"]:
		return false
	BEngine.submit(revival, 0, { "k": "swap", "to": 1 })
	BEngine.submit(revival, 1, { "k": "swap", "to": 1 })
	var revive := { "k": "move", "id": "Revival Blessing", "target": 0 }
	BEngine.submit(revival, 0, revive)
	BEngine.submit(revival, 1, { "k": "move", "id": "Protect" })
	if banette["hp"] != floori(float(banette["max"]) / 2.0) or banette["form"] != "mega" or banette.get("down", false):
		return false
	if BEngine.active(revival, 0)["pp"]["Revival Blessing"] != 0:
		return false
	BEngine._swap(revival, 0, 0, events)
	banette["hp"] = 0
	BEngine._faints(revival, events)
	BEngine._swap(revival, 0, 2, events)
	return BEngine.preview_move(revival, BEngine.active(revival, 0), "Last Respects", "")["power"] == 150

func _daeul_test() -> bool:
	var team := Data.team(Net.SET_ID, "daeul")
	var members: Array = team["members"]
	if members.size() != 6:
		return false
	for member: Dictionary in members:
		var state := BEngine.create([member], [members[4]], 7)
		if BEngine.active(state, 0)["moves"].size() != 4:
			return false
	var battle := BEngine.create([members[0]], [members[4]], 7)
	var user := BEngine.active(battle, 0)
	var target := BEngine.active(battle, 1)
	var foul_play := BEngine.move(Net.SET_ID, "Foul Play")
	var damage := BEngine.damage(user, target, foul_play, 100, battle)
	user["atk"] = 2
	if BEngine.damage(user, target, foul_play, 100, battle) != damage:
		return false
	target["atk"] = 2
	return BEngine.damage(user, target, foul_play, 100, battle) > damage

func _pivot_test() -> bool:
	var pivot := {"species": "scizor", "moves": ["U-turn"]}
	var flyer := {"species": "charizard", "moves": ["Protect"]}
	var ground := {"species": "garchomp", "moves": ["Earthquake", "Protect"]}
	var state := BEngine.create([pivot, flyer], [ground], 7)
	var outgoing := BEngine.active(state, 0)
	var opponent := BEngine.active(state, 1)
	outgoing["stats"]["spe"] = 999
	var original_hp := int(outgoing["hp"])
	var earthquake_pp := int(opponent["pp"]["Earthquake"])
	BEngine.submit(state, 0, {"k": "move", "id": "U-turn"})
	var first := BEngine.submit(state, 1, {"k": "move", "id": "Earthquake"})
	if not first.any(func(event): return event.get("pivot", false)) or not BEngine.waiting_for(state, 0) or BEngine.waiting_for(state, 1):
		return false
	if state["turn"] != 1 or opponent["pp"]["Earthquake"] != earthquake_pp or outgoing["hp"] != original_hp:
		return false
	var resumed := BEngine.submit(state, 0, {"k": "swap", "to": 1})
	var swap_at := resumed.find_custom(func(event): return event["e"] == "swap")
	var earth_at := resumed.find_custom(func(event): return event["e"] == "use" and event["move"] == "Earthquake")
	if swap_at < 0 or earth_at <= swap_at or state["turn"] != 2 or opponent["pp"]["Earthquake"] != earthquake_pp - 1:
		return false
	if BEngine.active(state, 0)["hp"] != BEngine.active(state, 0)["max"]:
		return false
	var slow := BEngine.create([pivot, flyer], [ground], 7)
	var slow_user := BEngine.active(slow, 0)
	slow_user["stats"]["spe"] = 1
	BEngine.submit(slow, 0, {"k": "move", "id": "U-turn"})
	BEngine.submit(slow, 1, {"k": "move", "id": "Earthquake"})
	if not BEngine.view(slow, 0)["pivotSwitch"] or slow_user["hp"] >= slow_user["max"] or slow["turn"] != 1:
		return false
	BEngine.submit(slow, 0, {"k": "swap", "to": 1})
	var blocked := BEngine.create([pivot, flyer], [ground], 7)
	BEngine.submit(blocked, 0, {"k": "move", "id": "U-turn"})
	BEngine.submit(blocked, 1, {"k": "move", "id": "Protect"})
	if BEngine.view(blocked, 0)["pivotSwitch"] or blocked["turn"] != 2:
		return false
	var alone := BEngine.create([pivot], [ground], 7)
	BEngine.submit(alone, 0, {"k": "move", "id": "U-turn"})
	BEngine.submit(alone, 1, {"k": "move", "id": "Earthquake"})
	return alone["turn"] == 2 and not BEngine.view(alone, 0)["pivotSwitch"]

func _pivot_variants_test() -> bool:
	var bench := {"species": "charizard", "moves": ["Protect"]}
	var defender := {"species": "garchomp", "moves": ["Earthquake"]}
	for skill in ["Volt Switch", "Flip Turn"]:
		var user := {"species": "raichu", "moves": [skill]}
		var foe := defender if skill == "Flip Turn" else {"species": "scizor", "moves": ["Iron Head"]}
		var state := BEngine.create([user, bench], [foe], 7)
		BEngine.active(state, 0)["stats"]["spe"] = 999
		BEngine.submit(state, 0, {"k": "move", "id": skill})
		BEngine.submit(state, 1, {"k": "move", "id": foe["moves"][0]})
		if not BEngine.view(state, 0)["pivotSwitch"]:
			return false
		BEngine.submit(state, 0, {"k": "swap", "to": 1})
		if int(state["turn"]) != 2:
			return false
	var grounded := BEngine.create([{"species": "raichu", "moves": ["Volt Switch"]}, bench], [defender], 7)
	BEngine.submit(grounded, 0, {"k": "move", "id": "Volt Switch"})
	BEngine.submit(grounded, 1, {"k": "move", "id": "Earthquake"})
	if BEngine.view(grounded, 0)["pivotSwitch"]:
		return false
	var absorber := {"species": "pawmot", "ability": "Volt Absorb", "moves": ["Iron Head"]}
	var absorbed := BEngine.create([{"species": "raichu", "moves": ["Volt Switch"]}, bench], [absorber], 7)
	var absorbing_mon := BEngine.active(absorbed, 1)
	var recovery := floori(float(absorbing_mon["max"]) / 4.0)
	absorbing_mon["hp"] -= recovery + 1
	BEngine.submit(absorbed, 0, {"k": "move", "id": "Volt Switch"})
	BEngine.submit(absorbed, 1, {"k": "move", "id": "Iron Head"})
	if BEngine.view(absorbed, 0)["pivotSwitch"] or int(absorbing_mon["hp"]) != int(absorbing_mon["max"]) - 1:
		return false
	var taunt := {"species": "incineroar", "moves": ["Parting Shot"]}
	for ability in ["Clear Body", "Soundproof"]:
		var receiver := {"species": "garchomp", "ability": ability, "moves": ["Earthquake"]}
		var blocked := BEngine.create([taunt, bench], [receiver], 7)
		BEngine.active(blocked, 0)["stats"]["spe"] = 999
		BEngine.submit(blocked, 0, {"k": "move", "id": "Parting Shot"})
		BEngine.submit(blocked, 1, {"k": "move", "id": "Earthquake"})
		if BEngine.view(blocked, 0)["pivotSwitch"] or BEngine.active(blocked, 1)["atk"] != 0:
			return false
	var bounce := {"species": "garchomp", "ability": "Magic Bounce", "moves": ["Earthquake"]}
	var reflected := BEngine.create([taunt, bench], [bounce, bench], 7)
	var actor := BEngine.active(reflected, 0)
	var bouncer := BEngine.active(reflected, 1)
	actor["stats"]["spe"] = 999
	BEngine.submit(reflected, 0, {"k": "move", "id": "Parting Shot"})
	BEngine.submit(reflected, 1, {"k": "move", "id": "Earthquake"})
	if not BEngine.view(reflected, 1)["pivotSwitch"] or actor["atk"] != -1 or actor["spa"] != -1:
		return false
	BEngine.submit(reflected, 1, {"k": "swap", "to": 1})
	return int(reflected["turn"]) == 2 and bouncer["pp"]["Earthquake"] == BEngine.max_pp(Net.SET_ID, "Earthquake")

func _daeul_two_test() -> bool:
	var team := Data.team(Net.SET_ID, "daeul-2")
	if team.is_empty():
		return false
	var members: Array = team["members"]
	if members.size() != 6:
		return false
	var state := BEngine.create(members, members, 7)
	for mon: Dictionary in state["sides"][0]["mons"]:
		if mon["moves"].size() != 4:
			return false
	var events := []
	var closer := BEngine.active(state, 0)
	for fainted in [0, 2, 5]:
		state["sides"][0]["faints"] = fainted
		if BEngine.preview_move(state, closer, "Last Respects", "")["power"] != 50 * (fainted + 1):
			return false
	BEngine._swap(state, 0, 5, events)
	BEngine._use(state, 0, "Reflect", events)
	BEngine._use(state, 0, "Light Screen", events)
	var side: Dictionary = state["sides"][0]
	if int(side.get("reflect", 0)) != 8 or int(side.get("lightScreen", 0)) != 8:
		return false
	BEngine._swap(state, 0, 1, events)
	BEngine._transform(state, 0, "mega", events)
	var charizard := BEngine.active(state, 0)
	if state["weather"] != "쾌청" or charizard["ability"] != "Drought":
		return false
	BEngine._use(state, 0, "Solar Beam", events)
	return not charizard.has("charge") and charizard["pp"]["Solar Beam"] == BEngine.max_pp(Net.SET_ID, "Solar Beam") - 1

func _nangman_test() -> bool:
	var team := Data.team(Net.SET_ID, "nangman")
	var members: Array = team["members"]
	if members.size() != 6:
		return false
	for member: Dictionary in members:
		var match_state := BEngine.create([member], [members[0]], 7)
		if BEngine.active(match_state, 0)["moves"].size() != 4:
			return false
	var events := []
	var state := BEngine.create([members[0]], [members[3]], 7)
	var wobbuffet := BEngine.active(state, 0)
	var foe := BEngine.active(state, 1)
	BEngine._use(state, 1, "Psycho Cut", events)
	var initial := int(foe["hp"])
	var received := int(wobbuffet["lastDirectHit"]["damage"])
	BEngine._use(state, 0, "Mirror Coat", events)
	if foe["hp"] != initial:
		return false
	BEngine._use(state, 0, "Counter", events)
	if foe["hp"] != initial - received * 2:
		return false
	wobbuffet["lastDirectHit"] = {"turn": state["turn"], "category": "special", "damage": 12}
	BEngine._use(state, 0, "Mirror Coat", events)
	if foe["hp"] != initial - received * 2:
		return false # 악 타입은 미러코트를 무효화한다.
	BEngine._use(state, 1, "Superpower", events)
	if foe["atk"] != 1 or foe["def"] != 1:
		return false
	wobbuffet["spa"] = 2
	BEngine._use(state, 1, "Topsy-Turvy", events)
	if wobbuffet["spa"] != -2:
		return false
	var test := BEngine.create([members[1]], [members[4]], 7)
	var pikachu := BEngine.active(test, 0)
	var dedenne := BEngine.active(test, 1)
	var surf := BEngine.move(Net.SET_ID, "Surf")
	var boosted := BEngine.damage(pikachu, dedenne, surf, 100, test)
	pikachu["itemUsed"] = true
	if boosted <= BEngine.damage(pikachu, dedenne, surf, 100, test):
		return false
	var maximum := int(dedenne["max"])
	dedenne["hp"] = 1
	BEngine._check_sitrus(dedenne, 1, pikachu, events)
	return dedenne["itemUsed"] and int(dedenne["hp"]) == 1 + floori(maximum / 4.0) + floori(maximum / 3.0)

func _soeul_test() -> bool:
	var team := Data.team(Net.SET_ID, "soeul")
	var members: Array = team["members"]
	if members.size() != 6:
		return false
	for member: Dictionary in members:
		var state := BEngine.create([member], [members[5]], 7)
		if BEngine.active(state, 0)["moves"].size() != 4:
			return false
	var events := []
	var state := BEngine.create([members[1]], [members[3]], 7)
	var xerneas := BEngine.active(state, 0)
	BEngine._use(state, 0, "Geomancy", events)
	if not xerneas["itemUsed"] or xerneas["spa"] != 2 or xerneas["spd"] != 2 or xerneas["spe"] != 2:
		return false
	BEngine._use(state, 0, "Geomancy", events)
	if xerneas.get("charge") != "Geomancy" or xerneas["spa"] != 2:
		return false
	BEngine._use(state, 0, "Geomancy", events)
	if xerneas.get("charge", "") != "" or xerneas["spa"] != 4 or xerneas["pp"]["Geomancy"] != 8:
		return false
	var trace := BEngine.create([members[0], members[2]], [members[5]], 7)
	if BEngine.active(trace, 0)["ability"] != "Intimidate":
		return false
	BEngine._swap(trace, 0, 1, events)
	BEngine._transform(trace, 0, "mega", events)
	if BEngine.active(trace, 0)["ability"] != "Thick Fat":
		return false
	var sword := BEngine.create([members[4]], [members[3]], 7)
	var gallade := BEngine.active(sword, 0)
	var target := BEngine.active(sword, 1)
	var skill := BEngine.move(Net.SET_ID, "Sacred Sword")
	var sharp_damage := BEngine.damage(gallade, target, skill, 100, sword)
	target["def"] = 4
	if sharp_damage != BEngine.damage(gallade, target, skill, 100, sword):
		return false
	gallade["ability"] = ""
	return sharp_damage > BEngine.damage(gallade, target, skill, 100, sword)

func _advanced_mechanics_test() -> bool:
	var test_team := Data.team(Net.SET_ID, "mechanics-practice")
	var members: Array = test_team["members"]
	var events := []
	var state := BEngine.create([members[0]], [members[1], members[5]], 7)
	var attacker := BEngine.active(state, 0)
	var defender := BEngine.active(state, 1)
	var quake := BEngine.move(Net.SET_ID, "Earthquake")
	var regular := BEngine.damage(attacker, defender, quake, 100, state)
	state["sides"][1]["reflect"] = 5
	if BEngine.damage(attacker, defender, quake, 100, state) != floori(regular / 2.0):
		return false
	attacker["atk"] = -3
	defender["def"] = 3
	var protected_crit := BEngine.damage(attacker, defender, quake, 100, state, true)
	state["sides"][1].erase("reflect")
	attacker["atk"] = 0
	defender["def"] = 0
	if BEngine.damage(attacker, defender, quake, 100, state, true) != protected_crit:
		return false
	BEngine._use(state, 0, "Spikes", events)
	BEngine._use(state, 0, "Toxic Spikes", events)
	BEngine._use(state, 0, "Toxic Spikes", events)
	BEngine._use(state, 0, "Sticky Web", events)
	BEngine._enter(state, 1, events)
	if defender["hp"] != defender["max"] or defender["status"] != "" or defender["spe"] != 0:
		return false
	defender["item"] = ""
	BEngine._enter(state, 1, events)
	if defender["hp"] >= defender["max"] or defender["status"] != "맹독" or defender["spe"] != -1:
		return false
	BEngine._end_turn(state, 1, events)
	BEngine._end_turn(state, 1, events)
	if defender.get("toxicStage") != 2:
		return false
	BEngine._use(state, 0, "Defog", events)
	if state["sides"][1].has("spikes") or state["sides"][1].has("toxicSpikes") or defender["evasion"] != -1:
		return false
	defender["status"] = ""
	state["terrain"] = "미스트필드"
	BEngine._apply_status(defender, 1, "화상", events, state)
	if defender["status"] != "":
		return false
	BEngine._use(state, 1, "Substitute", events)
	var remaining := int(defender["hp"])
	if defender.get("substitute", 0) <= 0:
		return false
	BEngine._use(state, 0, "Thunder Wave", events)
	if defender["status"] != "":
		return false
	attacker["ability"] = "No Guard"
	attacker["stats"]["atk"] = 999
	BEngine._use(state, 0, "Dual Wingbeat", events)
	if defender.get("substitute", -1) != 0 or int(defender["hp"]) >= remaining:
		return false
	BEngine._swap(state, 1, 1, events)
	if BEngine.view(state, 0)["sides"][1]["mons"][1].has("teraType"):
		return false
	BEngine._transform(state, 1, "tera", events)
	var transformed := BEngine.active(state, 1)
	return transformed["types"] == ["강철"] and BEngine.preview_move(state, transformed, "Tera Blast", "")["type"] == "강철"

func _rank_drop_test() -> bool:
	var espathra := { "species": "espathra", "moves": ["Lumina Crash"] }
	var target := { "species": "blastoise", "moves": ["Protect"] }
	var state := BEngine.create([espathra], [target], 7)
	var events := []
	BEngine._use(state, 0, "Lumina Crash", events)
	var defender := BEngine.active(state, 1)
	var drops := events.filter(func(event): return event["e"] == "stage")
	return defender["spd"] == -2 and defender["def"] == 0 and drops.size() == 1 and drops[0]["delta"] == -2 and drops[0]["seat"] == 1

func _team_profile_test() -> bool:
	for team in Data.sets[Net.SET_ID]["teams"]:
		for member in team["members"]:
			var training: Dictionary = member.get("training", {})
			if str(member.get("ability", "")).is_empty() or str(training.get("nature", "")).is_empty():
				return false
			if team["event"] != "CUSTOM":
				if str(member.get("abilitySource", "")).is_empty() or str(training.get("natureSource", "")).is_empty():
					return false
	var raichu := { "species": "raichu", "ability": "Lightning Rod", "moves": ["Thunderbolt", "Protect"] }
	var farigiraf := { "species": "farigiraf", "ability": "Armor Tail", "moves": ["Protect"] }
	var scizor := { "species": "scizor", "ability": "Technician", "moves": ["Bullet Punch"] }
	var events := []
	var lightning := BEngine.create([raichu], [raichu], 7)
	var rod := BEngine.active(lightning, 1)
	BEngine._use(lightning, 0, "Thunderbolt", events)
	if rod["spa"] != 1 or rod["hp"] != rod["max"]:
		return false
	var priority := BEngine.create([scizor], [farigiraf], 7)
	BEngine._use(priority, 0, "Bullet Punch", events)
	var armor := BEngine.active(priority, 1)
	if armor["hp"] != armor["max"]:
		return false
	var espathra := { "species": "espathra", "ability": "Speed Boost", "moves": ["Protect"] }
	var speed := BEngine.create([espathra], [farigiraf], 7)
	BEngine._end_turn(speed, 0, events)
	return BEngine.active(speed, 0)["spe"] == 1

func _late_substitute_test() -> bool:
	var defender := {"species": "blastoise", "moves": ["Substitute"]}
	for scenario in ["success", "low_hp", "flinch"]:
		var skill := "Fake Out" if scenario == "flinch" else "Earthquake"
		var attacker := {"species": "garchomp", "moves": [skill]}
		var state := BEngine.create([attacker], [defender], 7)
		var mon := BEngine.active(state, 1)
		var cost := floori(float(mon["max"]) / 4.0)
		var initial_pp := int(mon["pp"]["Substitute"])
		BEngine.active(state, 0)["stats"]["atk"] = 35
		if scenario == "low_hp":
			mon["hp"] = cost + 1
		BEngine.submit(state, 0, {"k": "move", "id": skill})
		var events := BEngine.submit(state, 1, {"k": "move", "id": "Substitute"})
		var hp_after_hit := -1
		var expected_status := "풀죽어서 움직이지 못했다" if scenario == "flinch" else "대타출동에 필요한 HP가 부족하다"
		var outcome_seen := false
		for event in events:
			if event.get("seat", -1) != 1:
				continue
			if event["e"] == "dmg":
				hp_after_hit = int(event["hp"])
			if scenario == "success" and event["e"] == "substitute":
				outcome_seen = hp_after_hit > cost and int(event["userHp"]) == hp_after_hit - cost
			if scenario != "success" and event["e"] == "status" and event["what"] == expected_status:
				outcome_seen = hp_after_hit > 0
		var expected_pp := initial_pp if scenario == "flinch" else initial_pp - 1
		if not outcome_seen or int(mon.get("substitute", 0)) != (cost if scenario == "success" else 0) or int(mon["pp"]["Substitute"]) != expected_pp:
			print("[selftest] 후공 대타출동 오류 (%s)" % scenario)
			return false
	return true

func _move_order_test() -> bool:
	for scenario in ["normal", "trick_room", "prankster", "higher_priority"]:
		var opponent_move := "Fake Out" if scenario == "higher_priority" else "Earthquake"
		var caster := {"species": "blastoise", "moves": ["Will-O-Wisp"]}
		var attacker := {"species": "garchomp", "moves": [opponent_move]}
		var state := BEngine.create([caster], [attacker], 7)
		BEngine.active(state, 0)["stats"]["spe"] = 50
		BEngine.active(state, 1)["stats"]["spe"] = 150
		if scenario == "prankster" or scenario == "higher_priority":
			BEngine.active(state, 0)["ability"] = "Prankster"
		if scenario == "trick_room":
			state["trickRoom"] = 2
		BEngine.submit(state, 0, {"k": "move", "id": "Will-O-Wisp"})
		var events := BEngine.submit(state, 1, {"k": "move", "id": opponent_move})
		var expected := ["Will-O-Wisp", opponent_move]
		if scenario == "normal":
			expected.reverse()
		elif scenario == "higher_priority":
			expected = [opponent_move]
		var move_order: Array = []
		for event in events:
			if event["e"] == "use":
				move_order.append(event["move"])
		if move_order != expected:
			print("[selftest] 도깨비불 행동 순서 오류 (%s): %s" % [scenario, str(move_order)])
			return false
	return true

func _priority_guard_test() -> bool:
	var attacker := {"species": "raichu", "moves": ["Feint", "Quick Attack"]}
	var defender := {"species": "blastoise", "moves": ["Protect", "Quick Guard"]}
	for scenario in ["Protect", "Quick Guard", "Max Guard", "Psychic Terrain"]:
		var state := BEngine.create([attacker], [defender], 7)
		var foe := BEngine.active(state, 1)
		var initial_hp := int(foe["hp"])
		var events := []
		match scenario:
			"Max Guard":
				foe["guard"] = true
				foe["guardMove"] = "max"
			"Psychic Terrain":
				state["terrain"] = "사이코필드"
			_:
				BEngine._use(state, 1, scenario, events)
		if scenario == "Quick Guard":
			BEngine._use(state, 0, "Quick Attack", events)
			if int(foe["hp"]) != initial_hp:
				return false
		BEngine._use(state, 0, "Feint", events)
		if (int(foe["hp"]) < initial_hp) != (scenario != "Psychic Terrain"):
			return false
		if foe["guard"] != (scenario == "Max Guard") or foe.get("quickGuard", false):
			return false
	return true

func _trick_room_team_test() -> bool:
	var team := Data.team(Net.SET_ID, "trick-room")
	if team.is_empty() or Data.sets[Net.SET_ID]["teams"][0]["id"] != "trick-room":
		return false
	var members: Array = team["members"]
	var target := {"species": "garchomp", "moves": ["Earthquake"]}
	var state := BEngine.create(members.slice(0, 3), [target], 7, Net.SET_ID, true)
	var lead := BEngine.active(state, 0)
	var air := BEngine.preview_move(state, lead, "Air Slash", "gmax")
	if "gmax" not in BEngine.view(state, 0)["gimmicks"] or air["ko"] != "다이제트" or air["power"] != 130:
		return false
	BEngine._transform(state, 0, "gmax", [])
	if lead["form"] != "base" or lead["max"] != lead["stats"]["hp"] * 2:
		return false
	var lapras := BEngine.create([members[3]], [target], 7, Net.SET_ID, true)
	BEngine._transform(lapras, 0, "gmax", [])
	BEngine._use(lapras, 0, "Freeze-Dry", [])
	if lapras["sides"][0].get("auroraVeil", 0) != 5 or lapras["weather"] != "":
		return false
	var trap := BEngine.create([members[1], members[2]], [target], 7)
	BEngine._use(trap, 0, "Trick Room", [])
	if trap["trickRoom"] != 5:
		return false
	var mimic := BEngine.active(trap, 0)
	BEngine._use(trap, 0, "Curse", [])
	if mimic["hp"] >= mimic["max"] or not BEngine.active(trap, 1).get("cursed", false):
		return false
	var rend_damage: Array = []
	for already_acted in [false, true]:
		var rend := BEngine.create([members[2]], [target], 7)
		var attacker := BEngine.active(rend, 0)
		var foe := BEngine.active(rend, 1)
		foe["acted"] = already_acted
		foe["max"] = 1000
		foe["hp"] = 1000
		BEngine._use(rend, 0, "Fishious Rend", [])
		if attacker["choiceMove"] != "Fishious Rend":
			return false
		rend_damage.append(1000 - foe["hp"])
	return rend_damage[0] > rend_damage[1] and rend_damage[1] > 0

func _trick_room_duration_test() -> bool:
	var slow := {"species": "mimikyu", "moves": ["Trick Room", "Swords Dance"]}
	var fast := {"species": "raichu", "moves": ["Nasty Plot", "Quick Attack"]}
	var state := BEngine.create([slow], [fast], 7)
	BEngine.active(state, 0)["stats"]["spe"] = 70
	BEngine.active(state, 1)["stats"]["spe"] = 180
	for round_index in 6:
		var slow_move := "Trick Room" if round_index == 0 else "Swords Dance"
		var fast_move := "Quick Attack" if round_index == 2 else "Nasty Plot"
		BEngine.submit(state, 0, {"k": "move", "id": slow_move})
		var events := BEngine.submit(state, 1, {"k": "move", "id": fast_move})
		var moves := events.filter(func(event): return event["e"] == "use")
		var first := 1 if round_index in [0, 2, 5] else 0
		if moves.size() != 2 or moves[0]["seat"] != first or state["trickRoom"] != maxi(0, 4 - round_index):
			return false
		if round_index == 4 and not events.any(func(event): return event.get("key") == "trickRoom" and event["turns"] == 0):
			return false
	BEngine._use(state, 0, "Trick Room", [])
	BEngine._use(state, 0, "Trick Room", [])
	return state["trickRoom"] == 0 and not state["effectSources"].has("trickRoom")

func _face_forms_test() -> bool:
	var attacker := {"species": "garchomp", "moves": ["Earthquake", "Flamethrower"]}
	var mimic := {"species": "mimikyu", "moves": ["Trick Room"]}
	var ice := {"species": "eiscue", "moves": ["Snowscape"]}
	var team := Data.team(Net.SET_ID, "form-practice")
	if team.is_empty() or team["members"].size() != 6:
		return false
	for species_form in [["mimikyu", "busted"], ["eiscue", "base"], ["eiscue", "noice"]]:
		var file := str(Data.form(Net.SET_ID, species_form[0], species_form[1]).get("file", ""))
		if int(Data.sprite_meta(Net.SET_ID, file, false).get("frames", 0)) < 2:
			return false
	var state := BEngine.create([attacker], [mimic, ice], 7)
	var target := BEngine.active(state, 1)
	var hp := int(target["hp"])
	var events := []
	BEngine._use(state, 0, "Flamethrower", events)
	if target["form"] != "busted" or target["hp"] != hp - floori(hp / 8.0) or not events.any(func(event): return event.get("effect") == "disguise_break"):
		return false
	BEngine._swap(state, 1, 1, [])
	BEngine._swap(state, 1, 0, [])
	if target["form"] != "busted":
		return false
	BEngine._swap(state, 1, 1, [])
	target = BEngine.active(state, 1)
	var ice_speed := int(target["stats"]["spe"])
	BEngine._use(state, 0, "Flamethrower", [])
	if target["form"] != "base" or target["hp"] >= target["max"]:
		return false
	hp = int(target["hp"])
	BEngine._use(state, 0, "Earthquake", events)
	if target["form"] != "noice" or target["hp"] != hp or target["stats"]["spe"] <= ice_speed or not events.any(func(event): return event.get("effect") == "ice_break"):
		return false
	BEngine._use(state, 1, "Snowscape", events)
	if target["form"] != "base" or target["stats"]["spe"] != ice_speed or not events.any(func(event): return event.get("effect") == "ice_restore"):
		return false
	BEngine._use(state, 0, "Earthquake", [])
	BEngine._end_turn(state, 1, [])
	if target["form"] != "noice":
		return false
	BEngine._swap(state, 1, 0, [])
	BEngine._swap(state, 1, 1, [])
	if target["form"] != "base":
		return false
	attacker["ability"] = "Mold Breaker"
	for member in [mimic, ice]:
		var bypass := BEngine.create([attacker], [member], 7)
		var defender := BEngine.active(bypass, 1)
		BEngine._use(bypass, 0, "Earthquake", [])
		if defender["form"] != "base" or defender["hp"] >= defender["max"]:
			return false
	return true

func _selftest() -> void:
	var fails := 0
	if not _trick_room_duration_test():
		print("[selftest] 트릭룸 순서 또는 종료 오류")
		fails += 1
	if not _face_forms_test():
		print("[selftest] 탈 또는 아이스페이스 폼 전환 오류")
		fails += 1
	if not _trick_room_team_test():
		print("[selftest] 트릭룸 덱 또는 다이맥스 판정 오류")
		fails += 1
	if not _priority_guard_test():
		print("[selftest] 선공기 및 방어 기술 상호작용 오류")
		fails += 1
	if not _move_order_test():
		fails += 1
	if not _late_substitute_test():
		fails += 1
	if not _pivot_test() or not _pivot_variants_test():
		print("[selftest] 유턴 및 같은 턴 교체 판정 오류")
		fails += 1
	if not _daeul_two_test():
		print("[selftest] 다을 2 팀 또는 후반 운영 오류")
		fails += 1
	if not _nangman_test():
		print("[selftest] 낭만 팀 또는 신규 효과 오류")
		fails += 1
	if not _soeul_test():
		print("[selftest] 소을 팀 또는 신규 특성·기술 오류")
		fails += 1
	if not _advanced_mechanics_test():
		print("[selftest] 진영 효과, 급소, 대타 또는 테라스탈 오류")
		fails += 1
	if not _daeul_test():
		print("[selftest] 다을 팀 또는 속임수 오류")
		fails += 1
	if not _rank_drop_test():
		print("[selftest] 루미나콜리전 랭크 하락 오류")
		fails += 1
	if not _team_profile_test():
		print("[selftest] 대회 팀 특성·성격 자료 오류")
		fails += 1
	if not _singles_test():
		print("[selftest] 싱글 추천 덱 전투 규칙 오류")
		fails += 1
	if not _pp_test():
		print("[selftest] 기술 PP 규칙 오류")
		fails += 1
	if not _specialtest():
		print("[selftest] PTC2026 또는 특수 규칙 오류")
		fails += 1
	await _wait(0.3)
	# 1) 뷰어 화면 열기: 세트마다 팀 선택 → 모든 팀 상세 → 멤버 크게 보기(넘기기·폼 전환) → 도감
	for set_id in Data.SETS:
		Nav.push(TeamSelectScreen.new(set_id), false)
		await _wait(0.1)
		for t in Data.sets[set_id]["teams"]:
			for m in t["members"]:
				var f := Data.form(set_id, m["species"], m.get("form", "base"))
				if Data.species(set_id, m["species"]).is_empty() or (not str(f.get("file", "")).begins_with("emblem:") and not ResourceLoader.exists(Data.sprite_path(set_id, str(f.get("file", "")), false))):
					print("[selftest] 그림/종 없음: %s %s" % [t["id"], m])
					fails += 1
		var t0: Dictionary = Data.sets[set_id]["teams"][0]
		Nav.push(TeamDetailScreen.new(set_id, t0), false)
		await _wait(0.1)
		var viewer := MemberViewer.new(set_id, t0["members"], 0)
		Nav.push(viewer, false)
		await _wait(0.1)
		for i in 7:
			viewer.go(1)
			await _wait(0.05)
		Nav.push(DexScreen.new(set_id), false)
		await _wait(0.2)
		print("[selftest] %s 화면 열기 완료 (팀 %d)" % [set_id, Data.sets[set_id]["teams"].size()])
		while Nav.depth() > 1:
			Nav.pop()
			await _wait(Nav.DURATION + 0.1)

	# 2) 엔진: 모든 대회 팀 조합을 AI끼리 대전한다. 끝까지 가는지, 턴 수·승률 분포
	var teams: Array = Data.sets[Net.SET_ID]["teams"]
	var turns := 0
	var wins := {}
	var games := 0
	for a in teams:
		for b in teams:
			for rep in 2:
				var pa := BBot.pick_members(Net.SET_ID, a["id"], b["id"], 3).map(func(i): return a["members"][i])
				var pb := BBot.pick_members(Net.SET_ID, b["id"], a["id"], 3).map(func(i): return b["members"][i])
				var s := BEngine.create(pa, pb, randi())
				var guard := 0
				while not s["over"] and guard < 2000:
					guard += 1
					for seat in 2:
						if BEngine.waiting_for(s, seat):
							BEngine.submit(s, seat, BBot.choose(s, seat))
				if not s["over"]:
					print("[selftest] 끝나지 않은 대전: %s vs %s" % [a["id"], b["id"]])
					fails += 1
				games += 1
				turns += int(s["turn"])
				if int(s["winner"]) == 0: wins[a["id"]] = int(wins.get(a["id"], 0)) + 1
				if int(s["winner"]) == 1: wins[b["id"]] = int(wins.get(b["id"], 0)) + 1
	print("[selftest] 엔진 %d판, 평균 %.1f턴, 팀별 승수 %s" % [games, float(turns) / games, wins])

	# 대회 팀 구성원마다 선택할 수 있는 기술이 있는지 확인한다.
	for team in teams:
		for member in team["members"]:
			var state := BEngine.create([member], [member], 1)
			var moves := BEngine.legal(state, 0)
			if moves.is_empty() or not moves.any(func(action): return action["ok"]):
				fails += 1
				print("[selftest] 대회 팀 기술 구성 오류: %s/%s" % [team["id"], member["species"]])

	# 공개 배분으로 계산한 실수치와 물리·특수 피해 경로 검증.
	var sneasler: Dictionary = Data.team(Net.SET_ID, "vrnc1-1")["members"].filter(func(m): return m["species"] == "sneasler")[0]
	var hippowdon: Dictionary = Data.team(Net.SET_ID, "vrnc1-2")["members"].filter(func(m): return m["species"] == "hippowdon")[0]
	var reference := BEngine.create([sneasler], [hippowdon], 1)
	var attacker := BEngine.active(reference, 0)
	var defender := BEngine.active(reference, 1)
	var physical := { "power": 120, "type": "격투", "damageClass": "physical" }
	var special := { "power": 120, "type": "격투", "damageClass": "special" }
	if int(attacker["max"]) != 183 or int(attacker["stats"]["spe"]) != 162 or int(defender["max"]) != 208:
		fails += 1
		print("[selftest] 공개 배분 레벨 50 실수치 오류")
	if BEngine.damage(attacker, defender, physical, 85) != 81 or BEngine.damage(attacker, defender, physical, 100) != 96 or BEngine.damage(attacker, defender, special, 100) != 36:
		fails += 1
		print("[selftest] 피해 계산 오류")
	var electric := { "power": 100, "type": "전기", "damageClass": "special" }
	if BEngine.damage(attacker, defender, electric, 100) != 0:
		fails += 1
		print("[selftest] 타입 면역 오류")

	# 3) 혼자 하기 흐름: 로비 → 선출 → 대전 끝까지 (Net 을 통해)
	Net.start("solo")
	Net.send({ "t": "ai_team", "id": "singles-2" })
	Net.send({ "t": "ai_team", "id": "missing" })
	if Net.view["players"][1]["team"] != "singles-2":
		fails += 1
		print("[selftest] AI 상대 팀 선택 오류")
	var gmax_team := Data.team(Net.SET_ID, "ptc26-1")
	var lead := (gmax_team["members"] as Array).find_custom(func(member): return member["species"] == "charizard")
	Net.send({ "t": "team", "id": gmax_team["id"] })
	Net.send({ "t": "ready", "v": true })
	Net.send({ "t": "picks", "picks": [0, 1, 2, 3] })
	if Net.view["phase"] != "pick" or not Net.view["players"][0]["picks"].is_empty():
		fails += 1
		print("[selftest] 4마리 선출을 허용함")
	var picks := [lead]
	for i in 3:
		if i != lead and picks.size() < Net.DEFAULT_PICK_COUNT:
			picks.append(i)
	Net.send({ "t": "picks", "picks": picks })
	if Net.view.get("phase") == "battle":
		var battle_view: Dictionary = Net.view["battle"]
		var ai_members: Array = Net._s["battle"]["sides"][1]["mons"]
		if not "gmax" in battle_view["gimmicks"] or ai_members.map(func(m): return m["id"]) != ["banette", "pawmot", "basculegion"]:
			fails += 1
			print("[selftest] 거다이맥스 또는 AI 팀 적용 오류")
	var steps := 0
	while Net.view["phase"] == "battle" and not Net.view["battle"]["over"] and steps < 500:
		steps += 1
		var legal: Array = (Net.view["battle"]["legal"] as Array).filter(func(x): return x["ok"])
		Net.send({ "t": "act", "a": legal[randi() % legal.size()] })
	var ok: bool = Net.view["phase"] == "battle" and Net.view["battle"]["over"]
	print("[selftest] AI와 연습: 단계 %s, %d번 입력, %s" % [Net.view["phase"], steps, "정상" if ok else "실패"])
	if not ok:
		fails += 1
	else:
		Net.send({ "t": "again" })
		if Net.view["phase"] != "lobby" or Net.view["players"][1]["team"] != "singles-2":
			fails += 1
			print("[selftest] 재대전에서 AI 팀 유지 오류")
	Net.leave()
	Net.start("solo")
	Net.send({"t": "rules", "pickCount": Net.FULL_TEAM_COUNT, "allowGmax": false})
	Net._handle(1, {"t": "rules", "pickCount": Net.DEFAULT_PICK_COUNT, "allowGmax": true})
	Net.send({"t": "team", "id": gmax_team["id"]})
	Net.send({"t": "ready", "v": true})
	Net.send({"t": "rules", "pickCount": Net.DEFAULT_PICK_COUNT, "allowGmax": true})
	Net.send({"t": "picks", "picks": picks})
	if Net.view["phase"] != "pick" or Net.view["pickCount"] != Net.FULL_TEAM_COUNT or Net.view["allowGmax"]:
		fails += 1
		print("[selftest] 6인 규칙 또는 호스트 권한 오류")
	var full_picks := [lead]
	for index in Net.FULL_TEAM_COUNT:
		if index != lead:
			full_picks.append(index)
	Net.send({"t": "picks", "picks": full_picks})
	var six: Dictionary = Net.view.get("battle", {})
	if six.is_empty() or six["sides"][0]["mons"].size() != 6 or six["sides"][1]["mons"].size() != 6 or "gmax" in six["gimmicks"] or not "mega" in six["gimmicks"]:
		fails += 1
		print("[selftest] 6인 배틀 기믹 또는 로스터 오류")
	Net.leave()
	print("[selftest] 끝: 실패 %d" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _audit_visible_controls(screen_name: String) -> void:
	var current := Nav.current()
	if current == null:
		return
	var viewport := get_viewport_rect()
	for node in current.find_children("*", "Control", true, false):
		if not (node is TapArea or node is LineEdit) or not node.is_visible_in_tree():
			continue
		var rect: Rect2 = node.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		if rect.position.x < viewport.position.x - 2.0 or rect.end.x > viewport.end.x + 2.0:
			push_error("[ui-overflow] %s %s %s %s" % [screen_name, node.name, rect, viewport])

func _shot(name: String, delay := 0.6) -> void:
	if delay > 0.0:
		await _wait(delay)
	await RenderingServer.frame_post_draw
	_audit_visible_controls(name)
	var dir := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			dir = arg.trim_prefix("--shots-dir=")
	var absolute_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var path := absolute_dir.path_join("shot_%s.png" % name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		push_error("화면을 저장하지 못했습니다: " + path)
		get_tree().quit(2)
	print("[shots] %s" % path)

func _back_to_home() -> void:
	Nav.pop_to_root()
	await _wait(Nav.DURATION + 0.16)

func _shots() -> void:
	var set_id := Net.SET_ID
	await _shot("home")
	Nav.open_tab(TeamSelectScreen.new(set_id, false, "", true))
	await _shot("teams")
	for id in ["singles-1", "singles-2"]:
		Nav.push(TeamDetailScreen.new(set_id, Data.team(set_id, id)), false)
		await _shot(id)
		Nav.pop()
		await _wait(Nav.DURATION + 0.16)
	var team := Data.team(set_id, "ptc26-1")
	Nav.push(TeamDetailScreen.new(set_id, team), false)
	await _shot("detail")
	Nav.push(MemberViewer.new(set_id, team["members"], 0), false)
	await _shot("viewer")
	var layout: Control = Nav.current().get_meta("layout")
	var viewer_scroll := layout.get_child(1) as ScrollContainer
	viewer_scroll.scroll_vertical = 720
	await _shot("viewer_stats")
	(Nav.current() as MemberViewer).go(1)
	viewer_scroll.scroll_vertical = 0
	await _shot("viewer_new_species")
	await _back_to_home()

	Nav.open_tab(DexScreen.new(set_id, true))
	await _shot("dex")
	Nav.open_tab(HomeScreen.new(true))
	await _shot("battle_tab")
	await _back_to_home()
	Nav.push(SessionScreen.new("host"), false)
	await _shot("host")
	await _back_to_home()
	Nav.push(SessionScreen.new("join"), false)
	await _shot("join")
	await _back_to_home()

	var battle := SessionScreen.new("solo")
	Nav.push(battle, false)
	Net.send({ "t": "ai_team", "id": "ptc26-4" })
	Net.send({ "t": "team", "id": team["id"] })
	await _shot("lobby")
	battle._open_team_picker(true)
	await _wait(Nav.DURATION + 0.16)
	await _shot("opponent_team_picker")
	(Nav.current() as TeamSelectScreen).picked.emit("ptc26-4")
	Nav.pop()
	await _wait(Nav.DURATION + 0.16)
	Net.send({ "t": "ready", "v": true })
	await _shot("pick")
	Net.send({ "t": "picks", "picks": [3, 0, 2] })
	await _wait(1.0)
	await _shot("battle")
	var screen := Nav.current() as BattleScreen
	var original := screen._b
	var decoy_demo := BEngine.create(
		[{ "species": "blastoise", "moves": ["Substitute"] }],
		[{ "species": "garchomp", "moves": ["Earthquake"] }], 7)
	screen._b = BEngine.view(decoy_demo, 0)
	screen._draw_all()
	var decoy_events := []
	BEngine._use(decoy_demo, 0, "Substitute", decoy_events)
	for event in decoy_events:
		if event["e"] == "substitute":
			await screen._play(event, BEngine.view(decoy_demo, 0))
	await _shot("substitute")
	screen._b = original
	screen._draw_all()
	screen._b = original.duplicate(true)
	var hp_slot := screen._slot(screen._me)
	var hp_bar := screen._hp_bars[hp_slot]
	var lead := screen._active(screen._me)
	var full := hp_bar.value
	lead["hp"] = int(lead["max"]) / 2
	screen._draw_side(screen._me)
	assert(is_equal_approx(hp_bar.value, full))
	await _wait(0.24)
	assert(hp_bar.value < full and hp_bar.value > 0.5)
	await screen._hp_tweens[hp_slot].finished
	assert(is_equal_approx(hp_bar.value, float(lead["hp"]) / float(lead["max"])))
	screen._b = original
	screen._draw_side(screen._me)
	await screen._hp_tweens[hp_slot].finished
	assert(is_equal_approx(hp_bar.value, full))
	screen._show_roster()
	var roster := screen._status_content
	var labels := roster.find_children("*", "Label", true, false)
	assert(labels.filter(func(label): return label.text == "미공개").size() == 2)
	assert(labels.filter(func(label): return label.text == "선출 확인").size() == 4)
	assert(labels.filter(func(label): return label.text == "선출 미공개").size() == 5)
	assert(labels.filter(func(label): return label.text == "미선출").size() == 3)
	await _shot("battle_roster")
	var roster_scroll := roster.get_parent().get_parent() as ScrollContainer
	roster_scroll.scroll_vertical = int(roster_scroll.get_v_scroll_bar().max_value)
	await _shot("battle_public_rosters")
	screen.on_back()
	var room_demo := BEngine.create(
		[{ "species": "pelipper", "ability": "Drizzle", "moves": ["Protect"] }],
		[{ "species": "farigiraf", "moves": ["Trick Room"] }], 7)
	screen._b = BEngine.view(room_demo, 0)
	screen._draw_all()
	var room_events := []
	BEngine._use(room_demo, 1, "Trick Room", room_events)
	for event in room_events:
		if event["e"] == "field":
			await screen._play(event, BEngine.view(room_demo, 0))
	assert(screen._b["trickRoom"] == 5 and screen._b["weather"] == room_demo["weather"])
	assert(screen._conditions.get_child_count() == 2)
	await _shot("trick_room_rain")
	room_events.clear()
	BEngine._use(room_demo, 1, "Trick Room", room_events)
	for event in room_events:
		if event["e"] == "field":
			await screen._play(event, BEngine.view(room_demo, 0))
	assert(screen._b["trickRoom"] == 0 and screen._conditions.get_child_count() == 1)
	var face_attacker := {"species": "garchomp", "moves": ["Earthquake"]}
	for face_species in ["mimikyu", "eiscue"]:
		var face_demo := BEngine.create([face_attacker], [{"species": face_species, "moves": ["Snowscape"]}], 7)
		screen._b = BEngine.view(face_demo, 0)
		screen._draw_all()
		var face_events := []
		BEngine._use(face_demo, 0, "Earthquake", face_events)
		for event in face_events:
			if event.get("effect") in ["disguise_break", "ice_break"]:
				screen._play(event, BEngine.view(face_demo, 0))
				await _wait(0.44)
				await _shot(face_species + "_face_break", 0.0)
				await _wait(0.46)
				assert(screen._active(1)["form"] == event["mon"]["form"])
			elif event["e"] == "dmg":
				await screen._play(event, BEngine.view(face_demo, 0))
		if face_species == "eiscue":
			face_events.clear()
			BEngine._use(face_demo, 1, "Snowscape", face_events)
			for event in face_events:
				if event.get("effect") == "ice_restore":
					screen._play(event, BEngine.view(face_demo, 0))
					await _wait(0.44)
					assert(screen._active(1)["form"] == "base")
					await _shot("eiscue_face_restored", 0.0)
					await _wait(0.46)
	var caster := { "species": "espathra", "moves": ["Lumina Crash"] }
	var target := { "species": "pelipper", "moves": ["Protect"] }
	var rank_demo := BEngine.create([caster], [target], 7)
	screen._b = BEngine.view(rank_demo, 0)
	screen._draw_all()
	await _wait(0.1)
	var events := []
	BEngine._use(rank_demo, 0, "Lumina Crash", events)
	screen._play(events[0], BEngine.view(rank_demo, 0))
	await _shot("rank_cast")
	await _wait(0.40)
	var stages := events.filter(func(event): return event["e"] == "stage")
	screen._play(stages[0], BEngine.view(rank_demo, 0))
	await _shot("rank_drop")
	await _wait(0.40)
	var boost_examples := {
		"Nasty Plot": "gholdengo", "Calm Mind": "floette", "Swords Dance": "sneasler",
		"Dragon Dance": "salamence", "Quiver Dance": "volcarona", "Shell Smash": "blastoise",
		"Iron Defense": "archaludon", "Bulk Up": "corviknight", "Acid Armor": "toxapex",
		"Clangorous Soul": "kommoo",
	}
	for move: String in boost_examples:
		var boost_demo := BEngine.create([{ "species": boost_examples[move], "moves": [move] }], [target], 7)
		screen._b = BEngine.view(boost_demo, 0)
		screen._draw_all()
		await _wait(0.08)
		var cast_events := []
		BEngine._use(boost_demo, 0, move, cast_events)
		screen._play(cast_events[0], BEngine.view(boost_demo, 0))
		await _shot("rank_up_" + move.to_snake_case())
		await _wait(0.78)
	screen._b = original
	screen._draw_all()
	screen._show_status()
	await _shot("battle_status")
	screen.on_back()
	var battle_view := screen._b
	var singles: Dictionary = Data.team(set_id, "singles-1")
	var status_demo := BEngine.create(singles["members"].slice(0, 3), [team["members"][3]], 13)
	BEngine._swap(status_demo, 0, 1, [])
	BEngine._transform(status_demo, 0, "mega", [])
	BEngine._use(status_demo, 0, "Shell Smash", [])
	screen._b = BEngine.view(status_demo, 0)
	screen._show_status()
	await _shot("battle_status_causes")
	screen.on_back()
	screen._b = battle_view
	screen._gimmick = "mega"
	screen._draw_actions()
	await _shot("mega_preview")
	screen._gimmick = ""
	Net.send({ "t": "act", "a": { "k": "move", "id": "Protect", "gimmick": "mega" } })
	for i in 100:
		await _wait(0.06)
		if not screen._playing:
			break
	await _shot("mega")
	Engine.time_scale = 10.0
	for i in 65:
		if Net.view["battle"]["over"]:
			break
		var state: Dictionary = Net._s["battle"]
		var action := BBot.choose(state, 0)
		if not action.is_empty():
			Net.send({ "t": "act", "a": action })
		await _wait(0.03)
	for i in 600:
		await _wait(0.09)
		if not screen._playing:
			break
	Engine.time_scale = 1.0
	await _shot("result")
	assert(Net.view["battle"]["over"])
	Net.send({ "t": "again", "rematch": true })
	await _wait(Nav.DURATION + 0.16)
	assert(Net.view["phase"] == "pick" and Net.view["players"][1]["picked"])
	await _shot("rematch_pick")
	Net.leave()
	await _back_to_home()
	var gmax := SessionScreen.new("solo")
	Nav.push(gmax, false)
	Net.send({ "t": "team", "id": team["id"] })
	Net.send({ "t": "ai_team", "id": "ptc26-4" })
	Net.send({ "t": "ready", "v": true })
	Net.send({ "t": "picks", "picks": [3, 0, 2] })
	await _wait(1.0)
	var giant := Nav.current() as BattleScreen
	giant._gimmick = "gmax"
	giant._draw_actions()
	await _shot("gmax_preview")
	giant._gimmick = ""
	Net.send({ "t": "act", "a": { "k": "move", "id": "Heat Wave", "gimmick": "gmax" } })
	for i in 100:
		await _wait(0.07)
		if not giant._playing:
			break
	await _shot("gmax")
	Net.leave()
	await _back_to_home()
	var six_session := SessionScreen.new("solo")
	Nav.push(six_session, false)
	Net.send({"t": "team", "id": team["id"]})
	Net.send({"t": "rules", "pickCount": Net.FULL_TEAM_COUNT, "allowGmax": false})
	await _shot("six_lobby")
	Net.send({"t": "ready", "v": true})
	await _shot("six_lead")
	six_session._sel = [3]
	six_session._refresh()
	var confirm := six_session._footer.get_child(-1) as TapArea
	confirm.tapped.emit()
	await _wait(1.0)
	assert(Net.view["battle"]["sides"][0]["mons"].size() == 6)
	await _shot("six_battle")
	get_tree().quit()
