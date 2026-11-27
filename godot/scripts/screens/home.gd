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
		_button(col, "AI 연습", true, func(): _open("solo"))
		_button(col, "팀 둘러보기", false, func(): Nav.open_tab(TeamSelectScreen.new("pokemon", false, "", true)))
	Lay.tabs(self, "대전" if battle_tab else "홈")

func _button(col: VBoxContainer, text: String, primary: bool, action: Callable) -> void:
	var b := UI.button(text, 28, primary, primary)
	(b.get_meta("panel") as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
	b.tapped.connect(action)
	col.add_child(b)

func _open(role: String) -> void:
	Nav.push(SessionScreen.new(role))
