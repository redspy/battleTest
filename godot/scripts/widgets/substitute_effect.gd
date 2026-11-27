extends Control
## 전장 스프라이트 위에서 대타의 등장·피격·파괴를 보여준다.

var active := false
var motion := 0.0:
	set(value):
		motion = value
		queue_redraw()
var phase := ""
var tween: Tween

func present(value: bool) -> void:
	if active == value:
		return
	active = value
	if tween:
		tween.kill()
	phase = ""
	motion = 0.0

func animate(event: String, duration: float) -> void:
	if tween:
		tween.kill()
	active = event != "파괴"
	phase = event
	motion = 1.0
	tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "motion", 0.0, duration)

func _draw() -> void:
	if not active and motion <= 0.0:
		return
	var radius := minf(size.x, size.y) * 0.26
	var center := size * Vector2(0.5, 0.68)
	var color := Color("#36bba6").lerp(Color.WHITE, motion * 0.68 if phase == "피격" else 0.0)
	if phase == "파괴":
		for i in 8:
			var dir := Vector2.from_angle(TAU * i / 8.0)
			var distance := radius * (0.6 + 1.3 * (1.0 - motion))
			draw_circle(center + dir * distance, radius * 0.10 * motion, Color(color, motion), true, -1.0, true)
		return
	if phase == "발동":
		radius *= 1.0 - motion * 0.52
		draw_arc(center, radius * (1.2 + motion), 0, TAU, 40, Color(color, motion), 3.0, true)
	if phase == "피격":
		center.x += sin(motion * 21.0) * radius * motion * 0.23
	var corners := PackedVector2Array()
	for i in 6:
		corners.append(center + Vector2.from_angle(TAU * i / 6.0 - PI * 0.5) * radius)
	draw_colored_polygon(corners, Color("#123b43"))
	corners.append(corners[0])
	draw_polyline(corners, color, 4.0, true)
	draw_circle(center, radius * 0.23, color, true, -1.0, true)
