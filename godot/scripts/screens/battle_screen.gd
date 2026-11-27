class_name BattleScreen
extends Control
## 대회 팀 1:1 대전 화면. 위 = 상대, 아래 = 나. 상태는 Net.view["battle"], 연출은 Net.view["events"] 를 순서대로 재생한다.

var _set_id: String
const STAT_KO := Data.STAT_LABELS
const FieldBackdrop := preload("res://scripts/widgets/field_backdrop.gd")
const RankEffect := preload("res://scripts/widgets/rank_effect.gd")
const RANK_STYLES := {
	"Parting Shot": "voice", "Snarl": "voice", "Icy Wind": "wind", "Lumina Crash": "prism",
	"Chilling Water": "water", "Liquidation": "water", "Rock Tomb": "stones",
	"Earth Power": "stones", "Electroweb": "net", "Mystical Fire": "flame",
}
const SELF_RANK_STYLES := {
	"Nasty Plot": ["self_ideas", Color("#c18cff")],
	"Calm Mind": ["self_ripple", Color("#7ce9f7")],
	"Swords Dance": ["self_swords", Color("#d9f2ff")],
	"Dragon Dance": ["self_spiral", Color("#6ca6ff")],
	"Quiver Dance": ["self_wings", Color("#f7a5d7")],
	"Shell Smash": ["self_shell", Color("#ffbe7c")],
	"Iron Defense": ["self_plates", Color("#a6c5eb")],
	"Bulk Up": ["self_power", Color("#ff906c")],
	"Acid Armor": ["self_acid", Color("#a2e9b3")],
	"Clangorous Soul": ["self_beat", Color("#d8acff")],
}
const ANIMATION_PACE := 1.45
const PLAYBACK_RATES := [1.0, 1.5, 2.0]
const FIELD_EFFECTS := {
	"쾌청": "불꽃 기술이 강해지고 물 기술이 약해집니다.",
	"비": "물 기술이 강해지고 불꽃 기술이 약해집니다.",
	"모래바람": "일부 포켓몬이 턴 끝에 피해를 받고 바위 타입의 특수방어가 오릅니다.",
	"눈": "얼음 타입의 방어가 오릅니다.",
	"그래스필드": "지면에 있는 포켓몬의 풀 기술이 강해지고 턴 끝에 HP가 회복됩니다.",
	"일렉트릭필드": "지면에 있는 포켓몬의 전기 기술이 강해집니다.",
	"사이코필드": "지면에 있는 포켓몬의 에스퍼 기술이 강해지고 상대의 선공기를 막습니다.",
	"트릭룸": "같은 우선도에서는 스피드가 느린 포켓몬부터 행동합니다.",
}

var _b := {}                  # 지금 화면에 보이는 상태 (사건을 재생하며 따라간다)
var _me := 0
var _gimmick := ""
var _playing := false
var _playback_index := 0
var _pending := []            # 재생을 기다리는 보기
var _leave_armed := 0.0

var _turn: Label
var _conditions: HFlowContainer
var _backdrop: Control
var _log: Label
var _hp_bars: Array[ProgressBar] = [null, null]
var _hp_tweens: Array[Tween] = [null, null]
var _hp_occupants := ["", ""]
var _hp_targets := [-1.0, -1.0]
var _info := [null, null]     # 자리별 정보 칸 (VBoxContainer)
var _spr := [null, null]      # 자리별 그림
var _actions: VBoxContainer
var _bench: VBoxContainer
var _status_layer: Control
var _status_content: VBoxContainer
var _showing_roster := false

func _ready() -> void:
	_set_id = str(Net.view["set"])
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var m := UI.margin(20)
	m.add_theme_constant_override("margin_top", int(UI.safe_top(self)) + 16)
	m.add_theme_constant_override("margin_bottom", int(UI.safe_bottom(self)) + 16)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(m)
	var fit_columns := func():
		var side_margin := maxi(20, int((root.size.x - 1024.0) * 0.5))
		m.add_theme_constant_override("margin_left", side_margin)
		m.add_theme_constant_override("margin_right", side_margin)
	root.resized.connect(fit_columns)
	fit_columns.call()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	m.add_child(col)

	var head := HBoxContainer.new()
	_turn = UI.label("턴 1", 30, UI.ACCENT)
	_turn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_turn)
	var speed := UI.button("속도 1×", 22)
	var speed_label: Label = speed.get_meta("label")
	speed.tapped.connect(func():
		_playback_index = (_playback_index + 1) % PLAYBACK_RATES.size()
		speed_label.text = "속도 " + str(PLAYBACK_RATES[_playback_index]).trim_suffix(".0") + "×")
	head.add_child(speed)
	var details := UI.button("상태 보기", 22)
	details.tapped.connect(_show_status)
	head.add_child(details)
	var roster := UI.button("팀 현황", 22)
	roster.tapped.connect(_show_roster)
	head.add_child(roster)
	var quit := UI.button("나가기", 22)
	quit.tapped.connect(_ask_leave)
	head.add_child(quit)
	col.add_child(head)
	_conditions = HFlowContainer.new()
	_conditions.add_theme_constant_override("h_separation", 8)
	_conditions.add_theme_constant_override("v_separation", 4)
	col.add_child(_conditions)

	var arena := PanelContainer.new()
	arena.add_theme_stylebox_override("panel", UI.box(Color("#e0eee7"), 26))
	arena.clip_contents = true
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(arena)
	_backdrop = FieldBackdrop.new()
	arena.add_child(_backdrop)
	var positions := VBoxContainer.new()
	positions.add_theme_constant_override("separation", 10)
	arena.add_child(positions)

	# 위: 상대 (정보 왼쪽, 그림 오른쪽) / 아래: 나 (그림 왼쪽, 정보 오른쪽)
	for who in ["foe", "me"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var card := Lay.card(UI.PANEL, 14)
		(card[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(card[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var spr := SpriteAnim.new()
		spr.custom_minimum_size = Vector2(252, 188)
		spr.bottom = true
		spr.size_flags_vertical = Control.SIZE_SHRINK_END
		var i := 0 if who == "foe" else 1
		_info[i] = card[1]
		_spr[i] = spr
		if who == "foe":
			row.add_child(card[0])
			row.add_child(spr)
		else:
			row.add_child(spr)
			row.add_child(card[0])
		positions.add_child(row)

	var logp := UI.panel(UI.BG_DEEP, 14)
	var lm := UI.margin(12)
	_log = Lay.wrap("", 24, UI.TEXT)
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.custom_minimum_size = Vector2(0, 48)
	_log.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lm.add_child(_log)
	logp.add_child(lm)
	col.add_child(logp)

	var action_scroll := ScrollContainer.new()
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	action_scroll.scroll_deadzone = 10
	action_scroll.custom_minimum_size.y = 510
	col.add_child(action_scroll)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(_actions)
	_bench = VBoxContainer.new()
	_bench.add_theme_constant_override("separation", 4)
	col.add_child(_bench)

	Net.changed.connect(_on_changed)
	_me = int(Net.view.get("seat", 0))
	_b = Net.view.get("battle", {})
	_log.text = "대전 시작! 기술이나 교체를 고르세요."
	_draw_all()

func _process(delta: float) -> void:
	_leave_armed = maxf(0.0, _leave_armed - delta)

func on_back() -> bool:
	if is_instance_valid(_status_layer):
		_status_layer.hide()
		_status_layer.queue_free()
		_status_layer = null
		_status_content = null
		return true
	_ask_leave()
	return true

func _ask_leave() -> void:
	if _leave_armed > 0.0 or _b.get("over", false):
		Net.leave()
		Nav.pop_to_root()
	else:
		_leave_armed = 2.5
		_log.text = "한 번 더 누르면 대전에서 나갑니다."

func _on_changed() -> void:
	var v: Dictionary = Net.view
	if str(v.get("phase", "")) != "battle":
		if Nav.current() == self:
			Nav.pop()
		return
	_pending.append(v)
	if not _playing:
		_drain()

func _drain() -> void:
	_playing = true
	while not _pending.is_empty():
		var v: Dictionary = _pending.pop_front()
		var events: Array = v.get("events", [])
		if not events.is_empty():
			_actions_message("…")
			for e in _group_stage_events(events):
				if not is_inside_tree():
					return
				await _play(e, v["battle"])
		_b = v["battle"]
		if is_inside_tree():
			_draw_all()
	_playing = false

func _group_stage_events(events: Array) -> Array:
	var grouped := []
	for event: Dictionary in events:
		if event["e"] != "stage":
			grouped.append(event)
			continue
		var previous: Dictionary = grouped.back() if not grouped.is_empty() else {}
		if previous.get("e") == "stage" and previous["seat"] == event["seat"] and previous.get("source", "") == event.get("source", "") and signi(previous["delta"]) == signi(event["delta"]):
			previous["changes"].append(event)
		else:
			var entry := event.duplicate()
			entry["changes"] = [event]
			grouped.append(entry)
	return grouped

# ───────────── 그리기 ─────────────

## 자리(0/1) → 화면 칸(0 위 = 상대, 1 아래 = 나)
func _slot(seat: int) -> int:
	return 1 if seat == _me else 0

func _active(seat: int) -> Dictionary:
	var side: Dictionary = _b["sides"][seat]
	return side["mons"][int(side["active"])]

func _name(seat: int) -> String:
	var mon := _active(seat)
	return Data.display_name(_set_id, mon["id"], mon["form"])

func _draw_all() -> void:
	if _b.is_empty():
		return
	_turn.text = "턴 %d" % int(_b["turn"])
	_draw_conditions()
	for seat in 2:
		_draw_side(seat)
	_draw_actions()
	if is_instance_valid(_status_content):
		_draw_status()

func _draw_conditions() -> void:
	var weather := str(_b.get("weather", ""))
	var terrain := str(_b.get("terrain", ""))
	var room := int(_b.get("trickRoom", 0))
	_backdrop.show_field(weather, terrain, room > 0, _animation_time(0.38))
	for child in _conditions.get_children():
		_conditions.remove_child(child)
		child.queue_free()
	if weather != "":
		_condition_button(weather, int(_b.get("weatherTurns", 0)))
	if terrain != "":
		_condition_button(terrain, int(_b.get("terrainTurns", 0)))
	if room > 0:
		_condition_button("트릭룸", room)
	_conditions.visible = _conditions.get_child_count() > 0

func _condition_button(name: String, turns: int) -> void:
	var badge := UI.button("%s · %d턴" % [name, turns], 22)
	var label: Label = badge.get_meta("label")
	var tint: Color = FieldBackdrop.TINTS.get(name, UI.TEXT)
	label.add_theme_color_override("font_color", tint.lerp(UI.TEXT, 0.74))
	badge.tapped.connect(_show_status)
	_conditions.add_child(badge)

func _show_status() -> void:
	_open_status_sheet(false)

func _show_roster() -> void:
	_open_status_sheet(true)

func _open_status_sheet(roster: bool) -> void:
	if _b.is_empty() or is_instance_valid(_status_layer):
		return
	_leave_armed = 0.0
	_status_layer = Control.new()
	_status_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_status_layer)
	var veil := ColorRect.new()
	veil.color = Color("#182b3b66")
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status_layer.add_child(veil)
	var sheet := Control.new()
	_status_layer.add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.anchor_top = 0.16
	_showing_roster = roster
	_status_content = Lay.page(sheet, "팀 현황" if roster else "상태 보기")
	_draw_status()

func _draw_status() -> void:
	for child in _status_content.get_children():
		_status_content.remove_child(child)
		child.queue_free()
	if _showing_roster:
		_draw_roster()
		return
	var field := _status_card("필드 · 턴 %d" % int(_b["turn"]))
	var field_sources: Dictionary = _b.get("effectSources", {})
	for entry in [["날씨", "weather"], ["필드 효과", "terrain"]]:
		var key: String = entry[1]
		var name := str(_b.get(key, ""))
		_show_effect(field, str(entry[0]) + "  " + _timed_effect(name, int(_b.get(key + "Turns", 0))), field_sources.get(key, "") if name != "" else "", FIELD_EFFECTS.get(name, ""))
	var room := int(_b.get("trickRoom", 0))
	_show_effect(field, "트릭룸  " + _timed_effect("적용 중" if room > 0 else "", room), field_sources.get("trickRoom", "") if room > 0 else "", FIELD_EFFECTS["트릭룸"] if room > 0 else "")
	for seat in [_me, 1 - _me]:
		var side: Dictionary = _b["sides"][seat]
		var roster := _status_card("내 포켓몬" if seat == _me else "상대 포켓몬")
		var side_sources: Dictionary = side.get("effectSources", {})
		if side.get("stealthRock", false):
			_show_effect(roster, "스텔스록", side_sources.get("stealthRock", ""), "교체로 나온 포켓몬이 바위 타입 상성에 따라 피해를 받습니다.")
		if int(side.get("toxicSpikes", 0)) > 0:
			_show_effect(roster, "독압정 · %d겹" % int(side["toxicSpikes"]), side_sources.get("toxicSpikes", ""), "지면에 있는 포켓몬이 교체로 등장할 때 독에 걸릴 수 있습니다.")
		var tailwind := int(side.get("tailwind", 0))
		if tailwind > 0:
			_show_effect(roster, _timed_effect("순풍", tailwind), side_sources.get("tailwind", ""), "이 진영 포켓몬의 스피드가 두 배가 됩니다.")
		var residual_turns := int(side.get("gmaxResidualTurns", 0))
		if residual_turns > 0:
			_show_effect(roster, _timed_effect(str(side["gmaxResidual"]) + " 지속 피해", residual_turns), side_sources.get("gmaxResidual", ""), "해당 타입이 아닌 포켓몬이 턴 끝에 피해를 받습니다.")
		for index in side["mons"].size():
			var mon: Dictionary = side["mons"][index]
			if mon.get("hidden", false):
				roster.add_child(Lay.wrap("아직 등장하지 않은 포켓몬", 22, UI.TEXT_DIM))
				continue
			var deployed: bool = int(side["active"]) == index and int(mon["hp"]) > 0
			var name := Data.display_name(_set_id, str(mon["id"]), str(mon["form"]))
			roster.add_child(Lay.wrap(name + (" · 출전 중" if deployed else ""), 25, UI.ACCENT if deployed else UI.TEXT))
			var hp := "%d/%d" % [int(mon["hp"]), int(mon["max"])] if seat == _me else "%d%%" % ceili(100.0 * float(mon["hp"]) / float(mon["max"]))
			roster.add_child(Lay.wrap("HP %s  ·  %s" % [hp, _pokemon_status(mon)], 22, UI.TEXT_DIM))
			if deployed:
				var stages := PackedStringArray()
				for key in Data.RANK_STATS:
					if int(mon.get(key, 0)) != 0:
						stages.append("%s %+d" % [STAT_KO[key], int(mon[key])])
				roster.add_child(Lay.wrap("능력 변화  " + ("없음" if stages.is_empty() else " · ".join(stages)), 22, UI.TEXT_DIM))
				_show_stage_history(roster, mon.get("stageHistory", []))

func _draw_roster() -> void:
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 12)
	_status_content.add_child(teams)
	for seat in [_me, 1 - _me]:
		var side: Dictionary = _b["sides"][seat]
		var team := VBoxContainer.new()
		team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		team.add_theme_constant_override("separation", 10)
		teams.add_child(team)
		team.add_child(UI.label("내 팀" if seat == _me else "상대 팀", 27, UI.ACCENT))
		for index in side["mons"].size():
			var mon: Dictionary = side["mons"][index]
			var active: bool = index == int(side["active"])
			var card := Lay.card(UI.PANEL_HI if active else UI.PANEL, 14)
			team.add_child(card[0])
			var body: VBoxContainer = card[1]
			if mon.get("hidden", false):
				body.add_child(Lay.wrap("미공개", 23, UI.TEXT_DIM))
				continue
			var name := Data.display_name(_set_id, str(mon["id"]), str(mon["form"]))
			body.add_child(Lay.wrap(name, 25, UI.TEXT))
			var sprite := SpriteAnim.new(_set_id, str(Data.form(_set_id, mon["id"], mon["form"]).get("file", "")), true)
			sprite.custom_minimum_size.y = 84
			sprite.playing = false
			body.add_child(sprite)
			var hp := int(mon["hp"])
			var max_hp := maxi(1, int(mon["max"]))
			var health := "%d / %d" % [hp, max_hp] if seat == _me else "%d%%" % ceili(100.0 * hp / max_hp)
			body.add_child(Lay.wrap("HP " + health, 22))
			var position_label := "출전 중" if active else "대기 중"
			var condition := _pokemon_status(mon)
			body.add_child(Lay.wrap(condition if hp <= 0 else position_label + " · " + condition, 21, UI.TEXT_DIM))

	_draw_public_rosters()

func _draw_public_rosters() -> void:
	var players: Array = Net.view.get("players", [])
	if players.size() != 2:
		return
	_status_content.add_child(Lay.wrap("공개 로스터 · 6마리", 28, UI.ACCENT))
	for seat in [_me, 1 - _me]:
		var player: Dictionary = players[seat]
		var team := Data.team(_set_id, str(player["team"]))
		if team.is_empty():
			continue
		var side: Dictionary = _b["sides"][seat]
		var known: Array = side.get("knownRosterSlots", player.get("picks", []))
		_status_content.add_child(UI.label("내 로스터" if seat == _me else "상대 로스터", 25, UI.TEXT))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_status_content.add_child(grid)
		for index in team["members"].size():
			var member: Dictionary = team["members"][index]
			var selected: bool = index in known
			var card := Lay.card(UI.PANEL_HI if selected else UI.PANEL, 10)
			var panel: Control = card[0]
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(panel)
			var body: VBoxContainer = card[1]
			var form := str(member.get("form", "base"))
			var sprite := SpriteAnim.new(_set_id, str(Data.form(_set_id, member["species"], form).get("file", "")), true)
			sprite.custom_minimum_size.y = 72
			sprite.playing = false
			if not selected:
				sprite.modulate.a = 0.57
			body.add_child(sprite)
			body.add_child(Lay.wrap(Data.display_name(_set_id, member["species"], form), 20))
			var mark := "선출 확인" if selected else ("미선출" if seat == _me else "선출 미공개")
			body.add_child(Lay.wrap(mark, 19, UI.ACCENT if selected else UI.TEXT_DIM))

func _show_effect(col: VBoxContainer, title: String, source: String, effect: String) -> void:
	col.add_child(Lay.wrap(title, 24))
	if source != "":
		col.add_child(Lay.wrap("원인  " + source, 21, UI.TEXT_DIM))
	if effect != "":
		col.add_child(Lay.wrap(effect, 21, UI.TEXT_DIM))

func _show_stage_history(col: VBoxContainer, history: Array) -> void:
	if history.is_empty():
		return
	col.add_child(Lay.wrap("최근 능력 변화 원인", 21, UI.ACCENT))
	var groups: Array[Dictionary] = []
	for entry in history:
		var source := str(entry["source"])
		var change := "%s %+d" % [STAT_KO[entry["stat"]], int(entry["delta"])]
		if groups.is_empty() or groups.back()["source"] != source or groups.back()["stats"].has(entry["stat"]):
			groups.append({ "source": source, "changes": [], "stats": [] })
		groups.back()["changes"].append(change)
		groups.back()["stats"].append(entry["stat"])
	for entry in groups.slice(-5):
		col.add_child(Lay.wrap("%s\n%s" % [entry["source"], " · ".join(entry["changes"])], 20, UI.TEXT_DIM))

func _status_card(title: String) -> VBoxContainer:
	var card := Lay.card()
	_status_content.add_child(card[0])
	var content: VBoxContainer = card[1]
	content.add_child(Lay.wrap(title, 27, UI.ACCENT))
	return content

func _timed_effect(name: String, turns: int) -> String:
	if name.is_empty():
		return "없음"
	return "%s · %d턴 남음" % [name, turns] if turns > 0 else name

func _pokemon_status(mon: Dictionary) -> String:
	if int(mon["hp"]) <= 0:
		return "기절"
	var effects := PackedStringArray()
	if int(mon.get("sleep", 0)) > 0:
		effects.append("잠듦")
	elif str(mon.get("status", "")) != "":
		effects.append(str(mon["status"]))
	var volatile := {"confusion": "혼란", "destinyBond": "길동무", "encoreTurns": "앙코르", "taunt": "도발", "disableTurns": "기술 봉쇄", "leechSeed": "씨뿌리기", "trapped": "교체 제한", "throatChop": "소리 기술 제한", "charge": "충전 중", "recharge": "반동으로 휴식", "dot": "그을음", "slow": "둔화"}
	for flag in volatile:
		if mon.get(flag):
			effects.append(volatile[flag])
	if int(mon.get("gmaxTurns", 0)) > 0:
		effects.append(_timed_effect("거다이맥스", int(mon["gmaxTurns"])))
	return "정상" if effects.is_empty() else " · ".join(effects)

func _draw_side(seat: int) -> void:
	var slot := _slot(seat)
	var side: Dictionary = _b["sides"][seat]
	var mon := _active(seat)
	var spr: SpriteAnim = _spr[slot]
	var down := int(mon.get("hp", 0)) <= 0
	spr.show_sprite(_set_id, str(Data.form(_set_id, str(mon["id"]), mon["form"]).get("file", "")), false)
	spr.modulate.a = 0.0 if down else 1.0
	var col: VBoxContainer = _info[slot]
	var bar := _hp_bars[slot]
	for child in col.get_children():
		if child != bar:
			col.remove_child(child)
			child.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(Lay.wrap(("나 · " if seat == _me else "상대 · ") + _name(seat), 26, UI.TEXT))
	col.add_child(head)
	col.add_child(Lay.type_chips(mon["types"]))
	_update_hp_bar(col, slot, int(side["active"]), mon)
	col.add_child(UI.label("체력 %d / %d" % [int(mon["hp"]), int(mon["max"])], 21, UI.TEXT_DIM))
	if seat == _me:
		col.add_child(Lay.wrap("도구 " + _item_text(mon), 21, UI.TEXT_DIM if _item_spent(mon) else UI.ACCENT))
	var st := []
	if int(mon.get("dot", 0)) > 0: st.append("그을음 %d" % int(mon["dot"]))
	if int(mon.get("slow", 0)) > 0: st.append("둔화 %d" % int(mon["slow"]))
	if mon.get("guard", false): st.append("수비 태세")
	if mon.get("status", "") != "": st.append(mon["status"])
	if mon.get("sleep", 0) > 0: st.append("잠듦")
	if mon.get("gmaxTurns", 0) > 0: st.append("거다이맥스 %d" % int(mon["gmaxTurns"]))
	for k in Data.RANK_STATS:
		if int(mon.get(k, 0)) != 0:
			st.append("%s %+d" % [STAT_KO[k], int(mon[k])])
	if not st.is_empty():
		col.add_child(Lay.chips(st, func(_x): return Color(0.62, 0.82, 1.0)))
	# 팀: ● 남음 ✕ 쓰러짐 ？ 아직 안 나옴
	var team := ""
	for m in side["mons"]:
		team += "？ " if m.get("hidden", false) else ("✕ " if int(m["hp"]) <= 0 else "● ")

func _update_hp_bar(col: VBoxContainer, slot: int, index: int, mon: Dictionary) -> void:
	var bar := _hp_bars[slot]
	if not is_instance_valid(bar):
		bar = ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size.y = 22
		bar.add_theme_stylebox_override("background", UI.box(UI.BG_DEEP, 11))
		var fill := UI.box(Color("#5acf85"), 11)
		bar.add_theme_stylebox_override("fill", fill)
		bar.value_changed.connect(func(value: float):
			if value <= 0.34:
				fill.bg_color = Color("#f5736b").lerp(Color("#fac74d"), smoothstep(0.12, 0.34, value))
			else:
				fill.bg_color = Color("#fac74d").lerp(Color("#5acf85"), smoothstep(0.34, 0.65, value)))
		col.add_child(bar)
		_hp_bars[slot] = bar
	col.move_child(bar, 2)
	var occupant := "%d:%s" % [index, mon["id"]]
	var ratio := clampf(float(mon["hp"]) / maxf(1.0, float(mon["max"])), 0.0, 1.0)
	var changed_mon: bool = occupant != _hp_occupants[slot]
	if not changed_mon and is_equal_approx(_hp_targets[slot], ratio):
		return
	_hp_occupants[slot] = occupant
	_hp_targets[slot] = ratio
	if _hp_tweens[slot] != null:
		_hp_tweens[slot].kill()
	if changed_mon:
		bar.value = ratio
		return
	var tween := bar.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(bar, "value", ratio, _animation_time(0.42))
	_hp_tweens[slot] = tween

## 지닌 도구가 없거나 이미 써 버렸는지 (엔진: 소모·떨어뜨리기 모두 itemUsed)
func _item_spent(mon: Dictionary) -> bool:
	return str(mon.get("item", "")) == "" or mon.get("itemUsed", false)

## 우리 편 몬스터가 지닌 도구 이름. 한글 이름이 없으면 영문 이름을 쓴다.
func _item_text(mon: Dictionary) -> String:
	var item := str(mon.get("item", ""))
	if item == "":
		return "없음"
	var ko = Data.sets[_set_id]["items"].get(item, {}).get("ko")
	var text := str(ko) if ko != null and str(ko) != "" else item
	return text + " (사용함)" if mon.get("itemUsed", false) else text

func _clear_actions() -> void:
	for container in [_actions, _bench]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_bench.hide()

func _actions_message(text: String) -> void:
	_clear_actions()
	var l := UI.label(text, 26, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(0, 120)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_actions.add_child(l)

func _draw_actions() -> void:
	_clear_actions()
	if _b["over"]:
		var w := int(_b["winner"])
		var text := "무승부" if w < 0 else ("승리!" if w == _me else "패배")
		var surviving := [0, 0]
		for seat in 2:
			for mon: Dictionary in _b["sides"][seat]["mons"]:
				if int(mon.get("hp", 1)) > 0:
					surviving[seat] += 1
		_log.text = "대전이 끝났습니다."
		_actions.add_child(UI.label(text, 56, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		_actions.add_child(UI.label("%d턴 · 남은 포켓몬  나 %d / 상대 %d" % [int(_b["turn"]), surviving[_me], surviving[1 - _me]], 24, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
		var solo := bool(Net.view.get("solo", false))
		if solo:
			var replay := UI.button("다시 연습", 28, true, true)
			replay.tapped.connect(func(): Net.send({ "t": "again", "rematch": true }))
			_actions.add_child(replay)
		var again := UI.button("팀 변경", 28, not solo)
		again.tapped.connect(func(): Net.send({ "t": "again" }))
		_actions.add_child(again)
		return
	if not _b["waiting"]:
		_actions_message("상대를 기다리는 중…")
		return
	var need: bool = _b["sides"][_me]["need"]
	if need:
		_log.text = "다음에 내보낼 몬스터를 고르세요."
	var foe := _active(1 - _me)
	var me := _active(_me)
	var options: Array = _b.get("gimmicks", [])
	if _gimmick not in options:
		_gimmick = ""
	if not options.is_empty():
		var row := HBoxContainer.new()
		for option in options:
			var kind := str(option)
			var text := "메가진화" if kind == "mega" else "거다이맥스"
			var button := UI.button(text + (" ✓" if kind == _gimmick else ""), 24, kind == _gimmick)
			button.tapped.connect(func():
				_gimmick = "" if _gimmick == kind else kind
				_draw_actions())
			row.add_child(button)
		_actions.add_child(row)
	var bench := GridContainer.new()
	bench.columns = 2
	bench.add_theme_constant_override("h_separation", 8)
	bench.add_theme_constant_override("v_separation", 8)
	for a in _b["legal"]:
		if a["k"] == "move":
			_actions.add_child(_move_button(a, me, foe))
		else:
			bench.add_child(_swap_button(a))
	if bench.get_child_count() > 0:
		_bench.add_child(UI.label("교체" if not need else "내보낼 몬스터", 22, UI.TEXT_DIM))
		_bench.add_child(bench)
		_bench.show()
	else:
		bench.free()

func _move_button(a: Dictionary, me: Dictionary, foe: Dictionary) -> Control:
	var preview := BEngine.preview_combatant(me, _gimmick)
	var field := _b
	if _gimmick == "mega":
		var weather: String = { "Drought": "쾌청", "Drizzle": "비", "Sand Stream": "모래바람", "Snow Warning": "눈" }.get(preview["ability"], "")
		if weather != "":
			field = _b.duplicate()
			field["weather"] = weather
	var mv := BEngine.preview_move(field, preview, str(a["id"]), "")
	var c := Lay.tap_card(UI.PANEL_HI, 12)
	var tap: TapArea = c[0]
	var col: VBoxContainer = c[1]
	col.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UI.chip(str(mv["type"]), Data.type_color(str(mv["type"]))))
	var name := Lay.wrap(str(mv["ko"]), 25, UI.TEXT)
	head.add_child(name)
	if mv.get("power") != null and not foe.get("hidden", false):
		var eff := str(BEngine.effectiveness(str(mv["type"]), foe, preview)[1])
		if eff != "":
			var label: String = { "strong": "▲ 유리", "weak": "▼ 불리", "immune": "효과 없음" }[eff]
			head.add_child(UI.label(label, 21, Color("#14664d") if eff == "strong" else Color("#9d3937")))
		if eff != "immune":
			head.add_child(UI.label("%d–%d" % [BEngine.damage(preview, foe, mv, 85, field), BEngine.damage(preview, foe, mv, 100, field)], 21, UI.TEXT_DIM))
	var move_id := str(a["id"])
	var max_pp := BEngine.max_pp(_set_id, move_id)
	if max_pp > 0:
		var remaining := int(me.get("pp", {}).get(move_id, 0))
		head.add_child(UI.chip("PP %d/%d" % [remaining, max_pp], Color(0.62, 0.82, 1.0)))
	col.add_child(head)
	var description := str(mv.get("desc", "")) if a["ok"] else "사용 불가: %s" % a["why"]
	if a.has("target"):
		var ally: Dictionary = _b["sides"][_me]["mons"][int(a["target"])]
		description = "되살리기 · " + Data.display_name(_set_id, ally["id"], ally["form"])
	col.add_child(Lay.wrap(description, 19, UI.TEXT_DIM))
	if a["ok"]:
		var id := str(a["id"])
		tap.tapped.connect(func():
			var action := { "k": "move", "id": id }
			if a.has("target"):
				action["target"] = a["target"]
			if _gimmick != "":
				action["gimmick"] = _gimmick
			_gimmick = ""
			_act(action))
	else:
		tap.modulate.a = 0.4
	return tap

func _swap_button(a: Dictionary) -> Control:
	var mon: Dictionary = _b["sides"][_me]["mons"][int(a["to"])]
	var c := Lay.tap_card(UI.PANEL_HI, 8)
	var tap: TapArea = c[0]
	tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var spr := SpriteAnim.new(_set_id, str(Data.form(_set_id, str(mon["id"]), mon["form"]).get("file", "")), true)
	spr.custom_minimum_size = Vector2(67, 67)
	spr.playing = false
	row.add_child(spr)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(Lay.wrap(Data.display_name(_set_id, mon["id"], mon["form"]), 21, UI.TEXT))
	info.add_child(UI.label("%d / %d" % [int(mon["hp"]), int(mon["max"])], 19, UI.TEXT_DIM))
	var item := UI.label(_item_text(mon), 18, UI.TEXT_DIM if _item_spent(mon) else UI.ACCENT)
	item.clip_text = true
	info.add_child(item)
	row.add_child(info)
	(c[1] as VBoxContainer).add_child(row)
	var to := int(a["to"])
	tap.tapped.connect(func(): _act({ "k": "swap", "to": to }))
	return tap

func _act(a: Dictionary) -> void:
	if _playing:
		return
	_actions_message("상대를 기다리는 중…")
	Net.send({ "t": "act", "a": a })

# ───────────── 사건 재생 ─────────────

func _animation_time(seconds: float) -> float:
	return seconds * ANIMATION_PACE / float(PLAYBACK_RATES[_playback_index])

func _wait(t: float) -> void:
	await get_tree().create_timer(_animation_time(t)).timeout

func _who(seat: int) -> String:
	return "나의 " if seat == _me else "상대 "

func _rank_effect(slot: int, style: String, tint: Color) -> Control:
	var effect := RankEffect.new()
	var from: Control = _spr[slot]
	var to: Control = _spr[1 - slot]
	var local := get_global_transform().affine_inverse()
	effect.start = local * from.get_global_rect().get_center()
	effect.finish = effect.start if style in ["drop", "rise"] or style.begins_with("self_") else local * to.get_global_rect().get_center()
	effect.style = style
	effect.tint = tint
	add_child(effect)
	if is_instance_valid(_status_layer):
		move_child(_status_layer, -1)
	return effect

func _animate_rank_effect(slot: int, style: String, tint: Color, duration: float) -> void:
	var effect := _rank_effect(slot, style, tint)
	var tween := effect.create_tween()
	tween.tween_property(effect, "progress", 1.0, _animation_time(duration))
	tween.tween_callback(effect.queue_free)

func _float_text(slot: int, text: String, color: Color, font_size := 52) -> void:
	var spr: Control = _spr[slot]
	var l := UI.label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.size = Vector2(spr.size.x, 70)
	l.position = spr.global_position + Vector2(0, spr.size.y * 0.3)
	add_child(l)
	if is_instance_valid(_status_layer):
		move_child(_status_layer, -1)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 80, _animation_time(0.7)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, _animation_time(0.3)).set_delay(_animation_time(0.4))
	tw.tween_callback(l.queue_free)

func _play(e: Dictionary, final: Dictionary) -> void:
	var seat := int(e.get("seat", 0))
	var slot := _slot(seat)
	var spr: SpriteAnim = _spr[slot]
	match str(e["e"]):
		"turn":
			_turn.text = "턴 %d" % int(e["n"])
		"swap":
			var side: Dictionary = _b["sides"][seat]
			var to := int(e["to"])
			if side["mons"][to].get("hidden", false):
				var fresh: Dictionary = (final["sides"][seat]["mons"][to] as Dictionary).duplicate()
				fresh["hp"] = fresh["max"]
				for k in ["dot", "slow"] + Data.RANK_STATS:
					fresh[k] = 0
				side["mons"][to] = fresh
			var tw := spr.create_tween()
			tw.tween_property(spr, "modulate:a", 0.0, _animation_time(0.15))
			await tw.finished
			side["active"] = to
			_draw_side(seat)
			spr.modulate.a = 0.0
			spr.create_tween().tween_property(spr, "modulate:a", 1.0, _animation_time(0.2))
			_log.text = "%s%s 등장!" % [_who(seat), _name(seat)]
			await _wait(0.55)
		"use":
			var move_id := str(e["move"])
			var move := BEngine.move(_set_id, move_id)
			var move_name := str(e.get("name", move.get("ko", "")))
			_log.text = "%s%s의 [%s]!" % [_who(seat), _name(seat), move_name]
			if move_name == move.get("ko", "") and SELF_RANK_STYLES.has(move_id):
				var visual: Array = SELF_RANK_STYLES[move_id]
				_animate_rank_effect(slot, visual[0], visual[1], 0.86)
				await _wait(0.90)
				return
			if move_name == move.get("ko", "") and move.get("effects", []).any(func(effect): return effect["kind"] == "debuff"):
				_animate_rank_effect(slot, RANK_STYLES.get(move_id, "pulse"), Data.type_color(str(move["type"])), 0.62)
				await _wait(0.66)
				return
			var dir := -1.0 if slot == 1 else 1.0
			var tw := spr.create_tween().set_trans(Tween.TRANS_QUAD)
			tw.tween_property(spr, "position", spr.position + Vector2(-50 * dir, 40 * dir), _animation_time(0.12))
			tw.tween_property(spr, "position", spr.position, _animation_time(0.18))
			await _wait(0.55)
		"dmg":
			_active(seat)["hp"] = int(e["hp"])
			_draw_side(seat)
			spr.modulate.a = 1.0
			var big := str(e.get("eff", "")) == "strong"
			_float_text(slot, "-%d" % int(e["amount"]), Color(1.0, 0.35, 0.3) if not big else Color(1.0, 0.8, 0.2))
			var note: String = { "strong": "효과가 좋다!", "weak": "효과가 별로다…", "immune": "효과가 없다!" }.get(str(e.get("eff", "")), "")
			if str(e.get("src", "")) == "dot": note = "그을음 피해"
			if str(e.get("src", "")) == "recoil": note = "반동 피해"
			if e.get("guard", false): note = "수비 태세로 막았다! " + note
			if note != "":
				_log.text = note
			var amp := 16.0 if big else 9.0
			var tw := spr.create_tween()
			for i in 4:
				tw.tween_property(spr, "position:x", spr.position.x + (amp if i % 2 == 0 else -amp), _animation_time(0.04))
			tw.tween_property(spr, "position:x", spr.position.x, _animation_time(0.04))
			Input.vibrate_handheld(30 if big else 15)
			await _wait(0.6)
		"heal":
			_active(seat)["hp"] = int(e["hp"])
			_draw_side(seat)
			_float_text(slot, "+%d" % int(e["amount"]), Color(0.4, 0.9, 0.55))
			await _wait(0.5)
		"transform":
			_b["sides"][seat]["mons"][int(_b["sides"][seat]["active"])] = e["mon"].duplicate(true)
			_draw_side(seat)
			_log.text = "%s%s · %s" % [_who(seat), _name(seat), e["what"]]
			await _wait(0.6)
		"field":
			var key := str(e.get("key", ""))
			if key in ["weather", "terrain", "trickRoom"]:
				var turns := int(e["turns"])
				if key == "trickRoom":
					_b["trickRoom"] = turns
				else:
					_b[key] = e["value"]
					_b[key + "Turns"] = turns
				var sources: Dictionary = _b.get("effectSources", {}).duplicate()
				sources[key] = e.get("source", "")
				_b["effectSources"] = sources
				_draw_conditions()
				if is_instance_valid(_status_content):
					_draw_status()
			var source := str(e.get("source", ""))
			_log.text = str(e["what"]) if source.is_empty() else "%s · %s" % [e["what"], source]
			await _wait(0.55)
		"status":
			_log.text = "%s%s: %s" % [_who(seat), _name(seat), e["what"]]
			await _wait(0.45)
		"stage":
			var source := str(e.get("source", ""))
			var delta := int(e["delta"])
			var changes := PackedStringArray()
			for entry: Dictionary in e.get("changes", [e]):
				changes.append("%s %+d" % [STAT_KO.get(str(entry["stat"]), ""), int(entry["delta"])])
			var change := "%s%s · %s" % [_who(seat), _name(seat), " · ".join(changes)]
			_log.text = change if source.is_empty() else "%s\n%s" % [change, source]
			var tint := Color(0.71, 0.74, 1.0) if delta < 0 else Color(0.49, 0.93, 0.69)
			var float_label := changes[0] if changes.size() == 1 else "%d개 능력 %s" % [changes.size(), "↓" if delta < 0 else "↑"]
			_animate_rank_effect(slot, "drop" if delta < 0 else "rise", tint, 0.60)
			_float_text(slot, float_label, tint, 31)
			await _wait(0.70)
		"faint":
			_log.text = "%s%s 쓰러졌다!" % [_who(seat), _name(seat)]
			var tw := spr.create_tween()
			tw.tween_property(spr, "modulate:a", 0.0, _animation_time(0.35))
			Input.vibrate_handheld(40)
			await _wait(0.7)
		"over":
			await _wait(0.3)
