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
					Net.send({ "t": "picks", "picks": range(Net.PICK_COUNT) })
			"battle":
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

func _selftest() -> void:
	var fails := 0
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
		if i != lead and picks.size() < Net.PICK_COUNT:
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

func _shot(name: String) -> void:
	await _wait(0.6)
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
	get_tree().quit()
