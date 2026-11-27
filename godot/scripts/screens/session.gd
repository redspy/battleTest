class_name SessionScreen
extends Control
## 두 폰 세션 화면: 참가(방 찾기) → 로비(팀 고르기·준비) → 선출 → 1:1 대전 화면으로 넘김.
## 상태는 모두 Net.view 에서 읽고, 바뀔 때마다 내용을 다시 그린다.

const EDGE_COLOR := { "good": Color(0.36, 0.82, 0.52), "bad": Color(0.96, 0.45, 0.42), "even": Color(0.8, 0.8, 0.8) }

const SET_ID := Net.SET_ID
var role: String        # host / join / solo
var _col: VBoxContainer
var _footer: VBoxContainer
var _footer_surface: Control
var _sel: Array = []    # 선출에서 고른 번호 (순서대로)
var _phase := ""
var _error := ""
var _address := ""

func _init(p_role: String) -> void:
	role = p_role

func _ready() -> void:
	var title := "AI와 연습" if role == "solo" else "1:1 대전"
	_col = Lay.page(self, title, { "host": "방 만들기", "join": "참가", "solo": "혼자 하기" }[role])
	_footer = UI.footer(self)
	_footer_surface = get_meta("footer")
	Net.changed.connect(_refresh)
	Net.closed.connect(_on_closed)
	Net.hosts_changed.connect(_refresh)
	if role == "join":
		Net.leave()
		Net.scan(true)
	else:
		_error = Net.start(role)
	_refresh()

func _exit_tree() -> void:
	Net.leave()

func on_shown() -> void:
	_refresh()

func _on_closed(reason: String) -> void:
	_error = reason
	if role == "join":
		Net.scan(true)
	if Nav.current() is BattleScreen:
		Nav.back()
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	var v: Dictionary = Net.view
	var phase := str(v.get("phase", ""))
	if phase != _phase:
		_phase = phase
		_sel = []
	if phase == "battle" and Nav.current() == self:
		Nav.push(BattleScreen.new())
	for container in [_col, _footer]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_footer_surface.hide()
	if _error != "":
		_col.add_child(Lay.wrap(_error, 24, Color("#9d3937")))
	match phase:
		"": _build_join()
		"lobby": _build_lobby(v)
		"pick": _build_pick(v)
		"battle": _col.add_child(UI.label("대전 중…", 28, UI.TEXT_DIM))

# ───────────── 참가 ─────────────

func _build_join() -> void:
	if role != "join":
		return
	if Net.role == "join":
		_col.add_child(Lay.wrap(Net.status + "…", 26, UI.TEXT))
		return
	_col.add_child(Lay.wrap("같은 Wi-Fi 에 있는 방을 찾는 중입니다. 방을 만든 폰이 아래에 나타나면 탭하세요.", 23, UI.TEXT_DIM))
	var any := false
	for ip in Net.found_hosts.keys():
		any = true
		var b := UI.button("🔗  %s" % ip, 30, true, true)
		b.tapped.connect(func(): _join(str(ip)))
		_col.add_child(b)
	if not any:
		_col.add_child(UI.label("아직 찾은 방이 없습니다", 24, UI.TEXT_DIM))
	_col.add_child(UI.label("주소 직접 입력", 26, UI.ACCENT))
	var edit := UI.line_edit("예: 192.168.0.12", 30)
	edit.text = _address
	edit.text_changed.connect(func(t: String): _address = t)
	_col.add_child(edit)
	var go := UI.button("연결", 28, true)
	go.tapped.connect(func(): _join(_address.strip_edges()))
	_col.add_child(go)

func _join(address: String) -> void:
	if address == "":
		return
	Net.scan(false)
	_error = Net.join(address)
	_refresh()

# ───────────── 로비 ─────────────

func _build_lobby(v: Dictionary) -> void:
	var me := int(v["seat"])
	var players: Array = v["players"]
	if role == "host":
		var info := Lay.card(UI.PANEL, 18)
		(info[1] as VBoxContainer).add_child(UI.label(Net.status, 24, UI.TEXT))
		(info[1] as VBoxContainer).add_child(Lay.wrap("상대 폰에서 [참가] 를 누르면 이 방이 보입니다. 안 보이면 아래 주소를 직접 입력하세요.", 20, UI.TEXT_DIM))
		for a in Net.local_addresses():
			(info[1] as VBoxContainer).add_child(UI.label(str(a), 34, UI.ACCENT))
		_col.add_child(info[0])
	for i in 2:
		var p: Dictionary = players[i]
		var c := Lay.card(UI.PANEL_HI if i == me else UI.PANEL, 18)
		var col: VBoxContainer = c[1]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		head.add_child(UI.label("내 팀" if i == me else ("상대 팀" if p["here"] else "빈 자리"), 28, UI.ACCENT))
		if p["here"]:
			head.add_child(UI.chip("준비 완료" if p["ready"] else "준비 중", EDGE_COLOR["good"] if p["ready"] else EDGE_COLOR["even"]))
		col.add_child(head)
		var t := Data.team(SET_ID, str(p["team"]))
		if t.is_empty():
			col.add_child(UI.label("팀을 고르지 않았습니다" if p["here"] else "상대를 기다리는 중", 23, UI.TEXT_DIM))
		else:
			var team_name := str(t["name"])
			var player := str(t.get("player", ""))
			if t["event"] != "PTC26" and not player.is_empty():
				team_name += " — " + player
			col.add_child(Lay.wrap(team_name, 24, UI.TEXT))
			col.add_child(_mini_row(t["members"]))
		if i == me or role == "solo":
			var choose := UI.button("팀 고르기" if t.is_empty() else "팀 바꾸기", 25, t.is_empty())
			choose.tapped.connect(_open_team_picker.bind(i != me))
			col.add_child(choose)
		_col.add_child(c[0])
	var my: Dictionary = players[me]
	if my["team"] != "":
		var ready := UI.button("준비 취소" if my["ready"] else "준비 완료", 32, true, not my["ready"])
		ready.tapped.connect(func(): Net.send({ "t": "ready", "v": not my["ready"] }))
		_footer_surface.show()
		_footer.add_child(ready)

func _open_team_picker(opponent: bool) -> void:
	var title := "상대 팀 고르기" if opponent else "내 팀 고르기"
	var picker := TeamSelectScreen.new(SET_ID, true, title)
	var message := "ai_team" if opponent else "team"
	picker.picked.connect(func(id: String): Net.send({ "t": message, "id": id }))
	Nav.push(picker)

func _mini_row(members: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in members.size():
		var f := Data.form(SET_ID, members[i]["species"], members[i].get("form", "base"))
		var spr := SpriteAnim.new(SET_ID, str(f.get("file", "")), true)
		spr.custom_minimum_size = Vector2(0, 86)
		spr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spr.playing = false
		row.add_child(spr)
	return row

# ───────────── 선출 ─────────────

func _build_pick(v: Dictionary) -> void:
	var me := int(v["seat"])
	var n := Net.PICK_COUNT
	var players: Array = v["players"]
	var mine: Array = Data.team(SET_ID, str(players[me]["team"]))["members"]
	var theirs: Array = Data.team(SET_ID, str(players[1 - me]["team"]))["members"]
	var w := Lay.member_cell_width(self)

	_col.add_child(UI.label("상대 팀 (탭하면 자세히)", 26, UI.ACCENT))
	_col.add_child(_grid(theirs, w, [], func(i: int): Nav.push(MemberViewer.new(SET_ID, theirs, i))))
	var their_state := UI.chip("상대: 선출 완료" if players[1 - me]["picked"] else "상대: 고르는 중", EDGE_COLOR["good"] if players[1 - me]["picked"] else EDGE_COLOR["even"])
	their_state.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_col.add_child(their_state)

	if players[me]["picked"]:
		_col.add_child(UI.label("내 선출", 26, UI.ACCENT))
		_col.add_child(_grid(mine, w, players[me]["picks"], func(_i: int): pass))
		_col.add_child(UI.label("상대를 기다리는 중…", 26, UI.TEXT_DIM))
		return
	_col.add_child(UI.label("내 팀에서 %d마리 고르기 (%d/%d) — 첫 번째가 선봉" % [n, _sel.size(), n], 26, UI.ACCENT))
	_col.add_child(Lay.wrap("길게 누르면 자세히 볼 수 있습니다.", 20, UI.TEXT_DIM))
	var toggle := func(i: int):
		if i in _sel:
			_sel.erase(i)
		elif _sel.size() < n:
			_sel.append(i)
		_refresh()
	var detail := func(i: int): Nav.push(MemberViewer.new(SET_ID, mine, i))
	_col.add_child(_grid(mine, w, _sel, toggle, detail))
	var ok := UI.button("선출 확정", 32, true, _sel.size() == n)
	UI.set_enabled(ok, _sel.size() == n)
	ok.tapped.connect(func():
		if _sel.size() == n:
			Net.send({ "t": "picks", "picks": _sel.duplicate() }))
	_footer_surface.show()
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	for i in n:
		var slot := Lay.card(UI.PANEL_HI if i < _sel.size() else UI.BG_DEEP, 8)
		var title := "선봉" if i == 0 else "%d번" % (i + 1)
		var name := "미선택"
		if i < _sel.size():
			var member: Dictionary = mine[_sel[i]]
			name = Data.display_name(SET_ID, member["species"], member.get("form", "base"))
		(slot[1] as VBoxContainer).add_child(Lay.wrap(title + " · " + name, 20))
		(slot[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(slot[0])
	_footer.add_child(slots)
	_footer.add_child(ok)

## 지닌 도구 이름 (한국어 이름이 있으면 그것, 없으면 원래 이름, 없으면 "")
func _item_name(member: Dictionary) -> String:
	var item := str(member.get("item", ""))
	var ko = Data.sets[SET_ID]["items"].get(item, {}).get("ko")
	return str(ko) if ko != null else item

## 멤버 격자. picks 에 든 번호에는 순서 배지를 붙이고 나머지는 흐리게 한다.
func _grid(members: Array, w: float, picks: Array, on_tap: Callable, on_long := Callable()) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for i in members.size():
		var cell := Lay.member_cell(SET_ID, members[i], w, _item_name(members[i]))
		var at := picks.find(i)
		if at >= 0:
			var frame := Panel.new()
			frame.add_theme_stylebox_override("panel", UI.box(Color.TRANSPARENT, 22, 5, UI.ACCENT))
			frame.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(frame)
			var badge := UI.chip("선봉" if at == 0 else "%d번" % (at + 1), UI.ACCENT)
			badge.position = Vector2(8, 8)
			cell.add_child(badge)
		elif not picks.is_empty():
			cell.modulate = Color(1, 1, 1, 0.45)
		cell.tapped.connect(on_tap.bind(i))
		if on_long.is_valid():
			cell.long_pressed.connect(on_long.bind(i))
		grid.add_child(cell)
	return grid
