extends Control
## 전장 스프라이트 위에 개구리 대타를 그리고 등장·피격·파괴를 연출한다.

const OUTLINE := Color("#234638")
const GREEN := Color("#72bd68")
const BELLY := Color("#d7eaa2")

var active := false
var motion := 0.0:
	set(value):
		motion = value
		queue_redraw()
var phase := ""
var tween: Tween
var elapsed := 0.0

func _ready() -> void:
	set_process(false)
	resized.connect(queue_redraw)

func present(value: bool) -> void:
	if active == value:
		return
	active = value
	if tween:
		tween.kill()
	phase = ""
	elapsed = 0.0
	motion = 0.0
	set_process(active)

func animate(event: String, duration: float) -> void:
	if tween:
		tween.kill()
	active = event != "파괴"
	phase = event
	elapsed = 0.0
	motion = 1.0
	set_process(active)
	tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "motion", 0.0, duration)

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	if not active and motion <= 0.0:
		return
	var scale_factor := minf(size.x, size.y) / 133.0
	var ground := size * Vector2(0.5, 0.91)
	var lift := 0.0
	var squash := 1.0
	var opacity := 1.0
	var tint := Color.WHITE
	match phase:
		"발동":
			lift = sin(motion * PI) * 22.0
			squash = 1.0 - motion * 0.34
			opacity = 1.0 - motion * 0.6
		"피격":
			ground.x += sin(motion * 24.0) * 11.0 * motion * scale_factor
			squash = 1.0 - motion * 0.2
			tint = GREEN.lerp(Color.WHITE, motion)
		"파괴":
			lift = (1.0 - motion) * 24.0
			squash = 0.5 + motion * 0.5
			opacity = motion
			for i in 8:
				var heading := Vector2.from_angle(TAU * i / 8.0)
				var distance := (18.0 + 58.0 * (1.0 - motion)) * scale_factor
				draw_circle(ground - Vector2(0, 26) * scale_factor + heading * distance, 4.0 * motion * scale_factor, Color(GREEN, motion), true, -1.0, true)
	if active and motion <= 0.0:
		squash = 1.0 + sin(elapsed * 4.0) * 0.035
	_oval(ground, Vector2(36, 5) * scale_factor, Color(OUTLINE, 0.2 * opacity))
	draw_set_transform(ground - Vector2(0, lift) * scale_factor, 0.0, Vector2(2.0 - squash, squash) * scale_factor)
	_frog(opacity, tint)
	draw_set_transform(Vector2.ZERO)

func _frog(opacity: float, tint: Color) -> void:
	var edge := Color(OUTLINE, opacity)
	var skin := Color(GREEN.lerp(tint, 0.28 if motion > 0.0 and phase == "피격" else 0.0), opacity)
	var foot := Color("#4d9458", opacity)
	for side in [-1, 1]:
		_oval(Vector2(23 * side, -9), Vector2(14, 10), edge)
		_oval(Vector2(23 * side, -9), Vector2(12, 8), foot)
	_oval(Vector2(0, -21), Vector2(28, 21), edge)
	_oval(Vector2(0, -21), Vector2(26, 19), skin)
	_oval(Vector2(0, -15), Vector2(16, 12), Color(BELLY, opacity))
	for side in [-1, 1]:
		var eye := Vector2(16 * side, -39)
		draw_circle(eye, 11.0, edge, true, -1.0, true)
		draw_circle(eye, 9.1, skin, true, -1.0, true)
		if fposmod(elapsed, 2.9) > 2.76:
			draw_line(eye + Vector2(-4, 0), eye + Vector2(4, 0), edge, 2.0, true)
		else:
			draw_circle(eye, 5.8, Color("#f9f5d4", opacity), true, -1.0, true)
			draw_circle(eye + Vector2(1, 0), 3.0, edge, true, -1.0, true)
		_oval(Vector2(17 * side, -23), Vector2(3.6, 2.2), Color("#eda690", opacity))
	draw_arc(Vector2(0, -29), 8.0, 0.32, PI - 0.32, 12, edge, 2.0, true)

func _oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 28:
		points.append(center + Vector2.from_angle(TAU * index / 28.0) * radius)
	draw_colored_polygon(points, color)
