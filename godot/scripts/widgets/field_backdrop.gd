extends Control
## 포켓몬 뒤의 배경 효과. 콘텐츠나 입력 영역 위에는 그리지 않는다.

const TINTS := {
	"쾌청": Color("#f4b65a"), "비": Color("#3988bd"),
	"모래바람": Color("#daa16b"), "눈": Color("#578baa"),
	"그래스필드": Color("#6bb88a"), "사이코필드": Color("#d684c8"),
	"일렉트릭필드": Color("#f2cd55"), "미스트필드": Color("#ddbce8"),
	"트릭룸": Color("#7445b8"),
}

var _weather := ""
var _previous_weather := ""
var _terrain := ""
var _room := false
var _room_from := 0.0
var _room_mix := 0.0
var _elapsed := 0.0
var _duration := 0.0
var _mix := 1.0
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(false)

func show_field(weather: String, terrain: String, room: bool, duration: float) -> void:
	if _weather == weather and _terrain == terrain and _room == room:
		return
	_previous_weather = _weather
	_weather = weather
	_terrain = terrain
	_room_from = _room_mix
	_room = room
	_elapsed = 0.0
	_duration = duration
	_mix = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	_elapsed += delta
	_mix = smoothstep(0.0, 1.0, clampf(_elapsed / maxf(_duration, 0.01), 0.0, 1.0))
	_room_mix = lerpf(_room_from, 1.0 if _room else 0.0, _mix)
	queue_redraw()
	if _mix >= 1.0 and _weather == "" and _terrain == "" and not _room:
		set_process(false)

func _draw() -> void:
	if not is_visible_in_tree() or size.x <= 0 or size.y <= 0:
		return
	var side := 126.0 / maxf(size.x, 252.0)
	for point in [Vector2(1.0 - side, 0.47), Vector2(side, 0.97)]:
		draw_set_transform(size * point, 0.0, Vector2(1.0, 0.23))
		draw_circle(Vector2.ZERO, 112.0, Color("#8fb5a480"), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	if _previous_weather == _weather:
		_draw_weather(_weather, 1.0)
	else:
		_draw_weather(_previous_weather, 1.0 - _mix)
		_draw_weather(_weather, _mix)
	if _terrain != "":
		var tint: Color = TINTS.get(_terrain, Color.WHITE)
		for i in 5:
			var y := size.y * (0.79 + i * 0.04)
			draw_rect(Rect2(0.0, y, size.x, size.y * 0.04), Color(tint, 0.025 + i * 0.012))
	if _room_mix > 0.0:
		_draw_room()

func _draw_weather(weather: String, strength: float) -> void:
	if weather == "" or strength <= 0.0:
		return
	var tint: Color = TINTS.get(weather, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.095 * strength))
	if weather == "쾌청":
		for i in 7:
			var width := size.x * 0.55
			var x := size.x * (0.03 + i * 0.14) + sin(_time * 0.54 + i * 0.6) * 14.0
			draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 27, 0), Vector2(x + width, size.y), Vector2(x + width - 42, size.y)]), Color(tint, 0.026 * strength))
		return
	for i in 31:
		var seed := float(i)
		var origin := Vector2(fposmod(seed * 0.618, 1.0) * (size.x + 48.0), fposmod(seed * 0.381, 1.0) * (size.y + 48.0))
		var point := origin
		match weather:
			"비": point += Vector2(-126.0, 390.0) * _time
			"모래바람": point += Vector2(230.0 + 6.0 * (i % 5), 24.0) * _time
			"눈": point += Vector2(sin(_time * 0.85 + seed) * 18.0, (35.0 + i % 5 * 9.0) * _time)
		point = Vector2(fposmod(point.x, size.x + 48), fposmod(point.y, size.y + 48)) - Vector2(24, 24)
		var ink := Color(tint, (0.32 + 0.07 * (i % 4)) * strength)
		match weather:
			"비": draw_line(point, point + Vector2(-7, 24 + i % 7), ink, 1.8, true)
			"모래바람": draw_line(point, point + Vector2(8 + i % 7, 1), ink, 2.0, true)
			"눈": draw_circle(point, 2.0 + (i % 4) * 0.65, ink, true, -1.0, true)
	if weather == "비":
		for i in 3:
			var ripple := fposmod(_time * 0.8 + i * 0.37, 1.0)
			var center := size * Vector2(0.17 + i * 0.31, 0.86 - 0.06 * (i % 2))
			_oval(center, Vector2(7, 2) + Vector2(25, 6) * ripple, Color(tint, (1.0 - ripple) * strength * 0.28))
	elif weather == "모래바람":
		for i in 5:
			var y := size.y * (0.70 + i * 0.05) + 5.0 * sin(_time * 1.1 + i)
			draw_rect(Rect2(0, y, size.x, size.y * 0.05), Color(tint, (0.026 + i * 0.011) * strength))

func _draw_room() -> void:
	var tint: Color = TINTS["트릭룸"]
	var center := size * 0.5
	var angle := (1.0 - _room_mix) * PI * 0.55
	var pulse := 1.0 + 0.025 * sin(_time * 2.0)
	var accent := _room_mix * (0.19 + 0.22 * (1.0 - _room_mix))
	draw_rect(Rect2(Vector2.ZERO, size), Color(tint, _room_mix * 0.045))
	for i in range(1, 5):
		var radius := Vector2(size.x * (0.08 + i * 0.1), size.y * (0.07 + i * 0.08)) * pulse
		var points := PackedVector2Array()
		for corner in 5:
			points.append(center + (Vector2.from_angle(TAU * corner / 4.0) * radius).rotated(angle))
		draw_polyline(points, Color(tint, accent), 2.4, true)

func _oval(center: Vector2, radius: Vector2, ink: Color) -> void:
	var points := PackedVector2Array()
	for i in 25:
		points.append(center + Vector2.from_angle(TAU * i / 24.0) * radius)
	draw_polyline(points, ink, 1.6, true)
