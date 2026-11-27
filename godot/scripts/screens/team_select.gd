class_name TeamSelectScreen
extends Control
## 팀 선택 화면: 대회별로 팀을 나열한다. 팀마다 순위·선수·이름·6마리 작은 그림.
## pick_mode 이면 팀을 탭했을 때 화면을 닫고 picked(team_id) 를 알린다 (대전 로비에서 팀 고르기).

signal picked(team_id: String)

var set_id: String
var pick_mode := false
var pick_title: String

var tab: bool
var _preview: VBoxContainer

func _init(p_set: String, p_pick := false, p_title := "팀 고르기", p_tab := false) -> void:
	set_id = p_set
	pick_mode = p_pick
	pick_title = p_title
	tab = p_tab

func _ready() -> void:
	var s: Dictionary = Data.sets[set_id]
	var info: Dictionary = s["info"]
	var panel: Control
	if not pick_mode and not s["teams"].is_empty():
		var side := Lay.card(UI.PANEL, 16)
		panel = side[0]
		panel.custom_minimum_size.x = 270
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_preview = side[1]
	var col := Lay.page(self, pick_title if pick_mode else str(info["title"]), str(info["subtitle"]), panel)
	if tab:
		Lay.tabs(self, "팀")
	if panel:
		_show_preview(s["teams"][0])
	var order := 0
	for ev in info["events"]:
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 0)
		head.add_child(UI.label(str(ev["name"]), 30, UI.ACCENT))
		var sub := " · ".join([str(ev.get("date", "")), str(ev.get("note", ""))].filter(func(x): return x != ""))
		if sub != "":
			head.add_child(Lay.wrap(sub, 20, UI.TEXT_DIM))
		col.add_child(head)
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		col.add_child(grid)
		var resize_grid := func(): grid.columns = 2 if pick_mode and col.size.x >= 880 else 1
		col.resized.connect(resize_grid)
		resize_grid.call()
		for t in s["teams"]:
			if t["event"] != ev["id"]:
				continue
			var item := _team_item(t)
			grid.add_child(item)
			if order < 8:
				item.modulate.a = 0.0
				var tw := item.create_tween()
				tw.tween_interval(0.05 + order * 0.05)
				tw.tween_property(item, "modulate:a", 1.0, 0.25)
			order += 1

	if not pick_mode and not (s["rules"] as Dictionary).is_empty():
		var rules := Lay.card(UI.PANEL, 20)
		var body: VBoxContainer = rules[1]
		body.add_child(UI.label("대전 규칙", 28, UI.ACCENT))
		for line in s["rules"].get("text", []):
			body.add_child(Lay.wrap(str(line), 21))
		col.add_child(rules[0])

func _team_item(t: Dictionary) -> Control:
	var lead: Dictionary = t["members"][0]
	var types := Data.types(set_id, lead["species"], lead.get("form", "base"))
	var tint := UI.PANEL if types.is_empty() else UI.PANEL.lerp(Data.type_color(str(types[0])), 0.14)
	var c := Lay.tap_card(tint, 16)
	var tap: TapArea = c[0]
	var col: VBoxContainer = c[1]
	tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UI.chip(str(t.get("placement", "%d위" % int(t["rank"]))), UI.ACCENT))
	var name := Lay.wrap(str(t["name"]), 28)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		spr.custom_minimum_size = Vector2(0, 132 if m == lead else 90)
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
		elif is_instance_valid(_preview) and _preview.is_visible_in_tree():
			_show_preview(t)
		else:
			Nav.push(TeamDetailScreen.new(set_id, t)))
	if pick_mode:
		tap.long_pressed.connect(func(): Nav.push(TeamDetailScreen.new(set_id, t)))
	return tap

func _show_preview(team: Dictionary) -> void:
	for child in _preview.get_children():
		_preview.remove_child(child)
		child.queue_free()
	var lead: Dictionary = team["members"][0]
	var form := Data.form(set_id, lead["species"], lead.get("form", "base"))
	var sprite := SpriteAnim.new(set_id, str(form.get("file", "")), true)
	sprite.custom_minimum_size = Vector2(0, 160)
	_preview.add_child(sprite)
	_preview.add_child(Lay.wrap(str(team["name"]), 28))
	_preview.add_child(Lay.type_chips(Data.types(set_id, lead["species"], lead.get("form", "base"))))
	var open := UI.button("팀 상세", 24, true, true)
	open.tapped.connect(func(): Nav.push(TeamDetailScreen.new(set_id, team)))
	_preview.add_child(open)
