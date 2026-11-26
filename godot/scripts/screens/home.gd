class_name HomeScreen
extends Control
## 첫 화면: 대회 팀 뷰어와 1:1 대전

func _ready() -> void:
	var col := Lay.page(self)
	col.add_child(UI.label("배틀 테스트", 52, UI.TEXT))
	col.add_child(UI.label("대회 팀 뷰어 · 1:1 대전", 24, UI.TEXT_DIM))
	if Data.load_error != "":
		col.add_child(Lay.wrap("데이터 오류: " + Data.load_error, 26, Color(1, 0.5, 0.5)))
		return

	var p: Dictionary = Data.sets["pokemon"]["info"]
	_section(col, "대회 팀", str(p["subtitle"]), "charizard", "megay", "pokemon")
	_button(col, "📋  팀 뷰어 (팀 %d개)" % Data.sets["pokemon"]["teams"].size(), true, func(): Nav.push(TeamSelectScreen.new("pokemon")))
	_button(col, "⚔  1:1 대전 — 방 만들기", false, func(): _open("host"))
	_button(col, "🔗  1:1 대전 — 참가", false, func(): _open("join"))
	_button(col, "🤖  AI와 연습", false, func(): _open("solo"))

func _section(col: VBoxContainer, title: String, sub: String, species_id: String, form_id: String, set_id: String) -> void:
	var c := Lay.card(UI.PANEL, 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	(c[1] as VBoxContainer).add_child(row)
	var spr := SpriteAnim.new(set_id, str(Data.form(set_id, species_id, form_id).get("file", "")), true)
	spr.custom_minimum_size = Vector2(150, 120)
	row.add_child(spr)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(UI.label(title, 38, UI.ACCENT))
	info.add_child(Lay.wrap(sub, 21, UI.TEXT_DIM))
	row.add_child(info)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 14)
	m.add_child(c[0])
	col.add_child(m)

func _button(col: VBoxContainer, text: String, primary: bool, action: Callable) -> void:
	var b := UI.button(text, 28, primary)
	(b.get_meta("panel") as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	b.tapped.connect(action)
	col.add_child(b)

func _open(role: String) -> void:
	Nav.push(SessionScreen.new(role))
