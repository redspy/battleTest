class_name SpriteAnim
extends Control
## 프레임 시트(WebP) 를 재생하는 그림. 주어진 칸 안에 비율을 지켜 가운데(아래 정렬 선택)로 그린다.

var set_id := ""
var file := ""
var thumb := false
var flip := false          # 좌우 뒤집기 (대전에서 내 쪽 몬스터)
var bottom := false        # 칸 아래에 붙여 그리기
var playing := true

var _tex: Texture2D
var _meta := {}
var _t := 0.0
var _frame := 0

func _init(p_set := "", p_file := "", p_thumb := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if p_file != "":
		show_sprite(p_set, p_file, p_thumb)

func show_sprite(p_set: String, p_file: String, p_thumb := false) -> void:
	if p_set == set_id and p_file == file and p_thumb == thumb and (_tex != null or file.begins_with("emblem:")):
		return
	set_id = p_set
	file = p_file
	thumb = p_thumb
	_meta = Data.sprite_meta(set_id, file, thumb)
	var path := Data.sprite_path(set_id, file, thumb)
	_tex = load(path) if not _meta.is_empty() and ResourceLoader.exists(path) else null
	_t = randf() * 2.0   # 여러 그림이 똑같이 움직이지 않게
	_frame = 0
	queue_redraw()

func _process(delta: float) -> void:
	if not playing or not is_visible_in_tree():
		return
	if file.begins_with("emblem:") and not thumb:
		_t += delta
		queue_redraw()
		return
	if _tex == null:
		return
	var n := int(_meta.get("frames", 1))
	if n <= 1:
		return
	_t += delta
	var f := int(_t * float(_meta.get("fps", 10.0))) % n
	if f != _frame:
		_frame = f
		queue_redraw()

func _draw() -> void:
	if file.begins_with("emblem:"):
		_draw_emblem()
		return
	if _tex == null:
		return
	var fw := float(_meta["fw"])
	var fh := float(_meta["fh"])
	var cols := int(_meta["cols"])
	var region := Rect2((_frame % cols) * fw, (_frame / cols) * fh, fw, fh)
	var k := minf(size.x / fw, size.y / fh)
	var dst := Vector2(fw, fh) * k
	var pos := Vector2((size.x - dst.x) / 2.0, size.y - dst.y if bottom else (size.y - dst.y) / 2.0)
	if flip:
		draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
	draw_texture_rect_region(_tex, Rect2(pos, dst), region)


func _draw_emblem() -> void:
	var parts := file.split(":")
	var types := Data.types(set_id, parts[1], parts[2])
	var color := Data.type_color(str(types[0]))
	var accent := Data.type_color(str(types[types.size() - 1]))
	var radius := minf(size.x, size.y) * 0.40
	var center := size * 0.5 + Vector2(0.0, sin(_t * 2.4) * radius * 0.11 if not thumb else 0.0)
	var sides := 6 + posmod(parts[1].hash(), 3)
	var points := PackedVector2Array()
	for i in sides:
		points.append(center + Vector2.from_angle(TAU * i / sides - PI / 2) * radius)
	draw_colored_polygon(points, color.darkened(0.68))
	points.append(points[0])
	draw_polyline(points, accent.lightened(0.18), maxf(2.0, radius * 0.045), true)
	draw_arc(center, radius * 0.77, -PI * 0.78, PI * 0.78, 32, color, maxf(1.5, radius * 0.024), true)
	var name := str(Data.species(set_id, parts[1]).get("ko", parts[1])).left(2)
	var font := ThemeDB.fallback_font
	var font_size := maxi(10, int(radius * 0.53))
	var text_width := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, center + Vector2(-text_width * 0.5, font_size * 0.33), name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
