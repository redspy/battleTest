class_name UI
## 공통 색상/스타일/위젯 헬퍼

const BG := Color(0.075, 0.085, 0.14)
const BG_DEEP := Color(0.05, 0.055, 0.10)
const PANEL := Color(0.12, 0.135, 0.21)
const PANEL_HI := Color(0.17, 0.19, 0.29)
const ACCENT := Color(0.98, 0.78, 0.30)
const TEXT := Color(0.95, 0.97, 0.96)
const TEXT_DIM := Color(1, 1, 1, 0.62)
const KIND_COLOR := {
	"pokemon": Color(0.93, 0.42, 0.36),
	"trainer": Color(0.36, 0.62, 0.95),
	"energy": Color(0.98, 0.80, 0.30),
}
const CARD_RATIO := 1212.0 / 868.0  # 세로/가로

## wrap=true 는 폭이 정해진 곳(세로 목록 등)에서만 쓸 것. 가로 배치 안에서 켜면 글자가 세로로 꺾인다.
static func label(text: String, size: int, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func box(color: Color, radius := 18, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	sb.anti_aliasing = true
	return sb

static func panel(color: Color, radius := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius))
	return p

static func margin(all: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, all)
	return m

static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(Color(color, 0.18), 14, 2, Color(color, 0.8))
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, 20, color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## 화면 위쪽 안전 영역(상태바/카메라 구멍) 높이를 뷰포트 좌표로 반환
static func safe_top(node: Node) -> float:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var scale := node.get_viewport().get_visible_rect().size.y / float(win.y)
	return max(0.0, float(safe.position.y) * scale)

static func safe_bottom(node: Node) -> float:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	var scale := node.get_viewport().get_visible_rect().size.y / float(win.y)
	return max(0.0, float(win.y - safe.end.y) * scale)

## 상단 바: 뒤로 가기 + 제목 (+ 부제). 뒤로 가기는 Nav.back
static func top_bar(node: Control, title: String, sub := "") -> PanelContainer:
	var bar := PanelContainer.new()
	var sb := box(BG_DEEP, 0)
	sb.content_margin_top = safe_top(node) + 10
	sb.content_margin_bottom = 14
	sb.content_margin_left = 10
	sb.content_margin_right = 22
	bar.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	var back := TapArea.new()
	back.custom_minimum_size = Vector2(84, 84)
	var arrow := label("‹", 64, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.position.y = -6
	back.add_child(arrow)
	back.tapped.connect(Nav.back)
	row.add_child(back)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(label(title, 36, ACCENT))
	if sub != "":
		titles.add_child(label(sub, 22, TEXT_DIM))
	row.add_child(titles)
	return bar

## 버튼 (탭 영역 + 둥근 패널 + 글자). primary 는 강조색 테두리
static func button(text: String, size := 28, primary := false, fill := false) -> TapArea:
	var tap := TapArea.new()
	var p := PanelContainer.new()
	var sb := box(ACCENT if fill else PANEL_HI, 16, 3 if primary else 0, ACCENT)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, Color(0.13, 0.13, 0.13) if fill else TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	tap.add_child(p)
	tap.press_target = p
	tap.set_meta("label", l)
	tap.set_meta("panel", p)
	return tap

## 버튼 비활성 표시 (탭은 화면 쪽에서 무시)
static func set_enabled(b: TapArea, on: bool) -> void:
	b.modulate.a = 1.0 if on else 0.4
	b.set_meta("enabled", on)

static func is_enabled(b: TapArea) -> bool:
	return bool(b.get_meta("enabled", true))

## 입력칸
static func line_edit(placeholder: String, size := 30) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_stylebox_override("normal", box(PANEL, 12, 2, Color(1, 1, 1, 0.25)))
	e.add_theme_stylebox_override("focus", box(PANEL, 12, 2, ACCENT))
	for s in ["normal", "focus"]:
		var st: StyleBoxFlat = e.get_theme_stylebox(s)
		st.content_margin_left = 16
		st.content_margin_right = 16
		st.content_margin_top = 12
		st.content_margin_bottom = 12
	return e
