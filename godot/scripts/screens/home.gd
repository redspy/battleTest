class_name HomeScreen
extends Control
## 첫 화면: 대회 팀 뷰어와 1:1 대전

var battle_tab: bool

func _init(p_battle_tab := false) -> void:
	battle_tab = p_battle_tab

func _ready() -> void:
	var col := Lay.page(self)
	col.add_child(UI.label("대전" if battle_tab else "배틀 테스트", 52))
	if Data.load_error != "":
		col.add_child(Lay.wrap("데이터 오류: " + Data.load_error, 26))
		return

	if battle_tab:
		_button(col, "AI 연습", true, func(): _open("solo"))
		_button(col, "1:1 대전 방 만들기", false, func(): _open("host"))
		_button(col, "1:1 대전 참가", false, func(): _open("join"))
	else:
		var featured := Data.team("pokemon", "ptc26-1")
		_section(col, featured)
		_button(col, "AI 연습", true, func(): _open("solo"))
		_button(col, "팀 둘러보기", false, func(): Nav.open_tab(TeamSelectScreen.new("pokemon", false, "", true)))
	Lay.tabs(self, "대전" if battle_tab else "홈")

func _section(col: VBoxContainer, team: Dictionary) -> void:
	var c := Lay.tap_card(Color("#dcebe2"), 24)
	var lead: Dictionary = team["members"][0]
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	(c[1] as VBoxContainer).add_child(row)
	var spr := SpriteAnim.new("pokemon", str(Data.form("pokemon", lead["species"], lead.get("form", "base")).get("file", "")), true)
	spr.custom_minimum_size = Vector2(240, 230)
	row.add_child(spr)
	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(Lay.wrap(str(team["name"]), 38, UI.ACCENT))
	info.add_child(Lay.wrap("PTC2026 · " + str(team["placement"]), 23, UI.TEXT_DIM))
	row.add_child(info)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 14)
	(c[0] as TapArea).tapped.connect(func(): Nav.push(TeamDetailScreen.new("pokemon", team)))
	m.add_child(c[0])
	col.add_child(m)

func _button(col: VBoxContainer, text: String, primary: bool, action: Callable) -> void:
	var b := UI.button(text, 28, primary, primary)
	(b.get_meta("panel") as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	b.tapped.connect(action)
	col.add_child(b)

func _open(role: String) -> void:
	Nav.push(SessionScreen.new(role))
