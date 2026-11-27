class_name DexScreen
extends Control
## 도감: 세트의 모든 종을 격자로. 탭하면 크게 보기(좌우로 넘기기).

var set_id: String

var tab: bool

func _init(p_set: String, p_tab := false) -> void:
	set_id = p_set
	tab = p_tab

func _ready() -> void:
	var order: Array = Data.sets[set_id]["order"]
	var col := Lay.page(self, "도감", "%d종" % order.size())
	if tab:
		Lay.tabs(self, "도감")
	var list := []
	for sp in order:
		list.append({ "species": sp["id"], "form": "base" })
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	var w := Lay.member_cell_width(self)
	for i in list.size():
		var n := Data.usage(set_id, list[i]["species"])
		var cell := Lay.member_cell(set_id, list[i], w, "팀 %d" % n)
		cell.tapped.connect(func(): Nav.push(MemberViewer.new(set_id, list, i)))
		grid.add_child(cell)
