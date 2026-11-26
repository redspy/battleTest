class_name TeamDetailScreen
extends Control
## 팀 상세: 팀 컨셉 패널 + 6마리 격자. 멤버를 탭하면 크게 보기.

var set_id: String
var team: Dictionary

func _init(p_set: String, p_team: Dictionary) -> void:
	set_id = p_set
	team = p_team

func _ready() -> void:
	var col := Lay.page(self, str(team["name"]), str(team.get("placement", team.get("player", ""))))
	col.add_child(_concept())
	col.add_child(UI.label("멤버 (탭하면 크게 보기)", 26, UI.TEXT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	var w := Lay.member_cell_width(self)
	var members: Array = team["members"]
	for i in members.size():
		var m: Dictionary = members[i]
		var item := str(m.get("item", ""))
		var ko = Data.sets[set_id]["items"].get(item, {}).get("ko")
		var cell := Lay.member_cell(set_id, m, w, str(ko) if ko != null else item)
		cell.tapped.connect(func(): Nav.push(MemberViewer.new(set_id, members, i)))
		grid.add_child(cell)

func _concept() -> Control:
	var c := Lay.card(UI.PANEL, 22)
	var col: VBoxContainer = c[1]
	col.add_theme_constant_override("separation", 12)
	col.add_child(UI.label("팀 컨셉", 30, UI.ACCENT))
	col.add_child(Lay.chips(team.get("tags", []), func(_x): return Color(0.62, 0.82, 1.0)))
	col.add_child(Lay.wrap(str(team.get("summary", "")), 24, UI.TEXT))
	if team["event"] != "PTC26":
		col.add_child(UI.label("멤버별 역할", 26, UI.ACCENT))
	for m in team["members"]:
		var sp := Data.species(set_id, m["species"])
		if team["event"] == "PTC26":
			continue
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(UI.label(Data.display_name(set_id, m["species"], m.get("form", "base")), 23, UI.TEXT))
		head.add_child(UI.chip(str(sp.get("role", "")), UI.ACCENT))
		box.add_child(head)
		box.add_child(Lay.wrap(str(sp.get("roleText", "")), 20, UI.TEXT_DIM))
		col.add_child(box)
	if team.has("replicaCode"):
		col.add_child(UI.label("레플리카 코드  %s" % team["replicaCode"], 22, UI.ACCENT))
	if set_id == "pokemon":
		if team["event"] != "PTC26":
			col.add_child(Lay.wrap("※ 컨셉과 역할은 팀 구성을 보고 쓴 추론입니다. 지닌 도구는 대회 공개 자료, 기술·특성은 확인된 팀만 표시합니다.", 19, Color(0.98, 0.78, 0.48)))
		if team.has("sourceUrl"):
			var url := str(team["sourceUrl"])
			var link := UI.button("🔗 공개 팀 시트 열기", 22)
			link.tapped.connect(func(): OS.shell_open(url))
			col.add_child(link)
	return c[0]
