extends Control
## 전장 스프라이트 위에서 대타의 등장·피격·파괴를 보여준다.

# 나무위키 대타출동 문서의 포챔스 대타출동 스크린샷.
# https://namu.wiki/w/대타출동
const DECOY_IMAGE := preload("res://scripts/widgets/substitute_reference.webp")

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
	var image_size := DECOY_IMAGE.get_size()
	var fit := minf(size.x * 0.92 / image_size.x, size.y * 0.68 / image_size.y)
	var center := size * Vector2(0.5, 0.62)
	var tint := Color("#36bba6")
	var opacity := 1.0
	if phase == "발동":
		fit *= 1.0 - motion * 0.40
		center.y += size.y * 0.14 * motion
		opacity = 1.0 - motion * 0.7
	elif phase == "피격":
		center.x += sin(motion * 24.0) * size.x * 0.065 * motion
	elif phase == "파괴":
		fit *= 0.6 + motion * 0.4
		center.y -= size.y * 0.17 * (1.0 - motion)
		opacity = motion
		for i in 8:
			var direction := Vector2.from_angle(TAU * i / 8.0)
			var distance := size.y * (0.16 + 0.35 * (1.0 - motion))
			draw_circle(center + direction * distance, 5.0 * motion, Color(tint, motion), true, -1.0, true)
	var drawn_size := image_size * fit
	var frame := Rect2(center - drawn_size * 0.5, drawn_size)
	draw_texture_rect(DECOY_IMAGE, frame, false, Color(1.0, 1.0, 1.0, opacity))
	draw_rect(frame.grow(2.0), Color(tint, opacity), false, 3.0, true)
