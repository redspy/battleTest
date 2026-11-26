class_name TeamSelectScreen
extends Control
## 팀 선택 화면: 대회별로 팀을 나열한다. 팀마다 순위·선수·이름·6마리 작은 그림.
## pick_mode 이면 팀을 탭했을 때 화면을 닫고 picked(team_id) 를 알린다 (대전 로비에서 팀 고르기).

signal picked(team_id: String)

var set_id: String
var pick_mode := false

func _init(p_set: String, p_pick := false) -> void:
	set_id = p_set
	pick_mode = p_pick

func _ready() -> void:
	var s: Dictionary = Data.sets[set_id]
	var info: Dictionary = s["info"]
	var col := Lay.page(self, "팀 고르기" if pick_mode else str(info["title"]), str(info["subtitle"]))
	if not pick_mode:
		var dex := UI.button("📖  도감 (%d종)" % s["order"].size(), 26, true)
		dex.tapped.connect(func(): Nav.push(DexScreen.new(set_id)))
		col.add_child(dex)
		if not (s["rules"] as Dictionary).is_empty():
			col.add_child(_rules(s["rules"]))
	var order := 0
	for ev in info["events"]:
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 0)
		head.add_child(UI.label(str(ev["name"]), 30, UI.ACCENT))
		var sub := " · ".join([str(ev.get("date", "")), str(ev.get("note", ""))].filter(func(x): return x != ""))
		if sub != "":
			head.add_child(UI.label(sub, 20, UI.TEXT_DIM))
		col.add_child(head)
		for t in s["teams"]:
			if t["event"] != ev["id"]:
				continue
			var item := _team_item(t)
			col.add_child(item)
			if order < 8:
				item.modulate.a = 0.0
				var tw := item.create_tween()
				tw.tween_interval(0.05 + order * 0.05)
				tw.tween_property(item, "modulate:a", 1.0, 0.25)
			order += 1

func _rules(rules: Dictionary) -> Control:
	var c := Lay.card(UI.PANEL, 20)
	var col: VBoxContainer = c[1]
	col.add_child(UI.label("규칙", 28, UI.ACCENT))
	for line in rules.get("text", []):
		col.add_child(Lay.wrap("• " + str(line), 21, UI.TEXT))
	return c[0]

func _team_item(t: Dictionary) -> Control:
	var c := Lay.tap_card(UI.PANEL, 16)
	var tap: TapArea = c[0]
	var col: VBoxContainer = c[1]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UI.chip(str(t.get("placement", "%d위" % int(t["rank"]))), UI.ACCENT))
	var name := UI.label(str(t["name"]), 28, UI.TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	head.add_child(name)
	col.add_child(head)
	if t["event"] != "PTC26" and str(t.get("player", "")) != "":
		col.add_child(UI.label(str(t["player"]), 21, UI.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m in t["members"]:
		var f := Data.form(set_id, m["species"], m.get("form", "base"))
		var spr := SpriteAnim.new(set_id, str(f.get("file", "")), true)
		spr.custom_minimum_size = Vector2(0, 92)
		spr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spr.playing = false
		row.add_child(spr)
	col.add_child(row)
	col.add_child(Lay.chips(t.get("tags", []), func(_x): return Color(0.62, 0.82, 1.0)))
	var id: String = t["id"]
	tap.tapped.connect(func():
		if pick_mode:
			picked.emit(id)
			Nav.back()
		else:
			Nav.push(TeamDetailScreen.new(set_id, t)))
	if pick_mode:
		tap.long_pressed.connect(func(): Nav.push(TeamDetailScreen.new(set_id, t)))
	return tap
