class_name MemberViewer
extends Control
## 크게 보기: 큰 움직이는 그림 + 폼 전환 + 타입·역할 + 도구·특성·기술(또는 능력치·기술).
## 그림을 좌우로 밀면 목록의 이전/다음으로 넘어간다.

var set_id: String
const NATURE_NAMES := {
	"hardy": "노력", "lonely": "외로움", "adamant": "고집", "naughty": "개구쟁이", "brave": "용감",
	"bold": "대담", "docile": "온순", "impish": "장난꾸러기", "lax": "촐랑", "relaxed": "무사태평",
	"modest": "조심", "mild": "의젓", "bashful": "수줍음", "rash": "덜렁", "quiet": "냉정",
	"calm": "차분", "gentle": "얌전", "careful": "신중", "quirky": "변덕", "sassy": "건방",
	"timid": "겁쟁이", "hasty": "성급", "jolly": "명랑", "naive": "천진난만", "serious": "성실",
}

var list: Array        # [{species, form, item?, ability?, moves?}]
var index := 0
var _form := ""
var _col: VBoxContainer
var _title: Label

func _init(p_set: String, p_list: Array, p_index: int) -> void:
	set_id = p_set
	list = p_list
	index = p_index

func _ready() -> void:
	_col = Lay.page(self, " ", " ")
	_form = str(list[index].get("form", "base"))
	_build()

func go(dir: int) -> void:
	if list.size() <= 1:
		return
	index = posmod(index + dir, list.size())
	_form = str(list[index].get("form", "base"))
	_build()
	_col.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_col, "modulate:a", 1.0, 0.2)

func _build() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var m: Dictionary = list[index]
	var sp := Data.species(set_id, m["species"])
	var f := Data.form(set_id, m["species"], _form)
	# 상단 바 제목
	var bar: Node = (get_meta("layout") as Control).get_child(0)
	var labels := bar.find_children("", "Label", true, false)
	(labels[1] as Label).text = Data.display_name(set_id, m["species"], _form)
	(labels[2] as Label).text = "No.%04d  %s   %d / %d" % [int(sp.get("no", 0)), sp.get("en", ""), index + 1, list.size()]

	# 큰 그림 (좌우로 밀어 넘기기)
	var tap := TapArea.new()
	tap.custom_minimum_size = Vector2(0, 520)
	var stage := UI.panel(UI.BG_DEEP, 26)
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tap.add_child(stage)
	var spr := SpriteAnim.new(set_id, str(f.get("file", "")), false)
	spr.set_anchors_preset(Control.PRESET_FULL_RECT)
	spr.offset_left = 24
	spr.offset_right = -24
	spr.offset_top = 24
	spr.offset_bottom = -24
	tap.add_child(spr)
	tap.swiped.connect(func(d: Vector2): if absf(d.x) > absf(d.y): go(-1 if d.x > 0 else 1))
	_col.add_child(tap)
	if f.get("noArt", false):
		_col.add_child(Lay.wrap("이 폼의 그림이 없어 다른 폼의 그림을 보여 줍니다.", 20, Color("#795524")))

	# 폼 전환
	var forms: Array = sp.get("forms", [])
	if forms.size() > 1:
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 10)
		for fo in forms:
			var fid := str(fo["id"])
			var b := UI.button(str(fo["label"]), 22, fid == _form)
			b.tapped.connect(func():
				_form = fid
				_build())
			row.add_child(b)
		_col.add_child(row)

	var types := Lay.type_chips(Data.types(set_id, m["species"], _form))
	_col.add_child(types)
	if f.get("unverified", false):
		_col.add_child(Lay.wrap("※ 이 폼의 타입·구분은 확인하지 못했습니다 (기본 폼 기준으로 표시).", 19, Color("#795524")))

	if sp.get("role", "") != "":
		var role := Lay.card(UI.PANEL, 18)
		var role_chip := UI.chip(str(sp.get("role", "")), UI.ACCENT)
		role_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		(role[1] as VBoxContainer).add_child(role_chip)
		(role[1] as VBoxContainer).add_child(Lay.wrap(str(sp.get("roleText", "")), 22, UI.TEXT))
		_col.add_child(role[0])

	if f.has("baseStats"):
		_col.add_child(_stats(f["baseStats"], m.get("training", {})))
	if m.has("item") or m.has("ability") or f.has("battleAbility"):
		_col.add_child(_held(m, f))
	_col.add_child(_moves(m.get("moves", sp.get("moves", [])), m.has("moves") or sp.has("moves")))
	if set_id == "pokemon":
		_col.add_child(UI.label("이 포켓몬을 쓰는 팀: %d" % Data.usage(set_id, m["species"]), 21, UI.TEXT_DIM))

func _stats(base: Dictionary, training: Dictionary) -> Control:
	var c := Lay.card(UI.PANEL, 18)
	var col: VBoxContainer = c[1]
	col.add_child(UI.label("레벨 50 능력치", 26, UI.ACCENT))
	var source := "공개 팀 포인트" if training.has("source") else ("연습용 포인트" if training.has("points") else "포인트 0")
	var nature := str(training.get("nature", ""))
	if not nature.is_empty():
		var label := "성격  " + str(NATURE_NAMES.get(nature, nature))
		if training.has("boost") and training.has("reduce"):
			label += " · %s ↑ / %s ↓" % [Data.STAT_LABELS[training["boost"]], Data.STAT_LABELS[training["reduce"]]]
		col.add_child(Lay.wrap(label, 23, UI.TEXT))
	col.add_child(Lay.wrap(source, 20, UI.TEXT_DIM))
	var stats := Data.battle_stats(base, training)
	var points: Dictionary = training.get("points", {})
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 5)
	for heading in ["능력", "종족값", "포인트", "실수치"]:
		table.add_child(UI.label(heading, 20, UI.TEXT_DIM))
	for key in Data.STAT_LABELS:
		for value in [Data.STAT_LABELS[key], int(base[key]), int(points.get(key, 0)), int(stats[key])]:
			var cell := UI.label(str(value), 22, UI.TEXT)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			table.add_child(cell)
	col.add_child(table)
	return c[0]

func _held(m: Dictionary, form: Dictionary) -> Control:
	var c := Lay.card(UI.PANEL, 18)
	var col: VBoxContainer = c[1]
	var s: Dictionary = Data.sets[set_id]
	for pair in [["지닌 도구", "item", "items"], ["특성", "ability", "abilities"]]:
		var v = m.get(pair[1])
		var label: String = pair[0]
		if pair[1] == "ability":
			if _form.begins_with("mega"):
				v = form.get("battleAbility")
				label = "메가진화 후 특성"
			else:
				var listed := str(m.get("form", "base"))
				var starting := str(m.get("preMegaForm", "eternal" if m["species"] == "floette" else "base")) if listed.begins_with("mega") else listed
				if _form != starting or v == null:
					v = form.get("battleAbility")
		col.add_child(UI.label(label, 24, UI.ACCENT))
		if v == null or str(v) == "":
			col.add_child(UI.label("미확인", 22, UI.TEXT_DIM))
			continue
		var info: Dictionary = s[pair[2]].get(str(v), {})
		var ko = info.get("ko")
		col.add_child(UI.label(str(ko) if ko != null and str(ko) != "" else str(v), 24, UI.TEXT))
		if info.has("desc"):
			col.add_child(Lay.wrap(str(info["desc"]), 20, UI.TEXT_DIM))
	return c[0]

func _moves(ids: Array, known: bool) -> Control:
	var c := Lay.card(UI.PANEL, 18)
	var col: VBoxContainer = c[1]
	col.add_child(UI.label("기술", 26, UI.ACCENT))
	if ids.is_empty():
		col.add_child(Lay.wrap("이 팀의 기술 구성은 아직 확인하지 못했습니다." if known or set_id == "pokemon" else "기술 정보 없음", 22, UI.TEXT_DIM))
		return c[0]
	for id in ids:
		var mv := Data.move(set_id, str(id))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(UI.label(str(mv.get("ko", id)) if mv.get("ko") != null else str(id), 24, UI.TEXT))
		if mv.has("type"):
			head.add_child(UI.chip(str(mv["type"]), Data.type_color(str(mv["type"]))))
		if mv.get("power") != null:
			head.add_child(UI.chip("위력 %d" % int(mv["power"]), UI.TEXT))
		if mv.has("cost"):
			head.add_child(UI.chip("PP %d" % int(mv["pp"]), Color(0.62, 0.82, 1.0)))
		box.add_child(head)
		if mv.has("desc"):
			box.add_child(Lay.wrap(str(mv["desc"]), 20, UI.TEXT_DIM))
		col.add_child(box)
	return c[0]
