class_name Lay
## 화면 짜임 헬퍼: 배경 + (상단 바) + 세로 스크롤 목록, 타입 칩, 멤버 칸

const MAX_CONTENT_WIDTH := 1024.0

## 화면에 배경·상단 바·스크롤을 넣고, 내용을 담을 세로 칸을 돌려준다. title 이 비면 상단 바 없음.
static func page(screen: Control, title := "", sub := "") -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(bg)
	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	screen.add_child(layout)
	if title != "":
		layout.add_child(UI.top_bar(screen, title, sub))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 12
	layout.add_child(scroll)
	var m := UI.margin(24)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if title == "":
		m.add_theme_constant_override("margin_top", int(UI.safe_top(screen)) + 36)
	m.add_theme_constant_override("margin_bottom", int(UI.safe_bottom(screen)) + 36)
	scroll.add_child(m)
	var fit_content := func():
		var side := maxi(24, int((scroll.size.x - MAX_CONTENT_WIDTH) * 0.5))
		m.add_theme_constant_override("margin_left", side)
		m.add_theme_constant_override("margin_right", side)
	scroll.resized.connect(fit_content)
	fit_content.call()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	m.add_child(col)
	screen.set_meta("layout", layout)
	return col

static func wrap(text: String, size: int, color := UI.TEXT) -> Label:
	var l := UI.label(text, size, color, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func chips(texts: Array, color_of: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in texts:
		f.add_child(UI.chip(str(t), color_of.call(str(t))))
	return f

static func type_chips(types: Array) -> HFlowContainer:
	return chips(types, Data.type_color)

## 둥근 패널 안에 여백을 둔 세로 칸. [패널, 칸] 을 돌려준다.
static func card(color := UI.PANEL, pad := 20) -> Array:
	var p := UI.panel(color, 22)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var m := UI.margin(pad)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(m)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	return [p, col]

## 탭할 수 있는 카드. [탭 영역, 칸]
static func tap_card(color := UI.PANEL, pad := 20) -> Array:
	var tap := TapArea.new()
	var c := card(color, pad)
	var p: PanelContainer = c[0]
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tap.add_child(p)
	tap.press_target = p
	return [tap, c[1]]

static func member_cell_width(screen: Control) -> float:
	var viewport_width := screen.get_viewport_rect().size.x
	var available := minf(viewport_width - 48.0, MAX_CONTENT_WIDTH)
	return floorf((available - 24.0) / 3.0)

## 멤버 칸: 움직이는 그림 + 이름 + 타입. member = {species, form}
static func member_cell(set_id: String, member: Dictionary, width: float, extra := "") -> TapArea:
	var c := tap_card(UI.PANEL, 10)
	var tap: TapArea = c[0]
	var col: VBoxContainer = c[1]
	col.add_theme_constant_override("separation", 4)
	var f := Data.form(set_id, member["species"], member.get("form", "base"))
	var spr := SpriteAnim.new(set_id, str(f.get("file", "")), true)
	spr.custom_minimum_size = Vector2(0.0, clampf((width - 20.0) * 0.82, 105.0, 185.0))
	col.add_child(spr)
	var name := UI.label(Data.display_name(set_id, member["species"], member.get("form", "base")), 22, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	name.clip_text = true
	col.add_child(name)
	var tc := type_chips(Data.types(set_id, member["species"], member.get("form", "base")))
	tc.alignment = FlowContainer.ALIGNMENT_CENTER
	col.add_child(tc)
	if extra != "":
		var e := UI.label(extra, 18, UI.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		e.clip_text = true
		col.add_child(e)
	tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return tap
