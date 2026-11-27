extends Control
## 기술 궤적과 능력 변화 표시를 전투 화면 위에 그린다.

var start := Vector2.ZERO
var finish := Vector2.ZERO
var tint := Color.WHITE
var style := "pulse"
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var fade := smoothstep(0.0, 0.10, progress) * (1.0 - smoothstep(0.72, 1.0, progress))
	if style in ["drop", "rise"]:
		var direction_y := 1.0 if style == "drop" else -1.0
		for i in 3:
			var point := finish + Vector2((i - 1) * 36.0, direction_y * (-42.0 + 66.0 * progress + 8.0 * abs(i - 1)))
			var chevron := PackedVector2Array([point + Vector2(-9, -5 * direction_y), point + Vector2(0, 5 * direction_y), point + Vector2(9, -5 * direction_y)])
			draw_polyline(chevron, Color(tint, fade), 3.0, true)
		return

	if style.begins_with("self_"):
		_draw_self(fade)
		return

	var direction := start.direction_to(finish)
	var side := direction.orthogonal()
	var travel := smoothstep(0.06, 0.82, progress)
	var head := start.lerp(finish, travel)
	match style:
		"voice":
			for i in 4:
				var p := start.lerp(finish, maxf(0.0, travel - i * 0.13))
				draw_arc(p, 16.0 + i * 5.0, direction.angle() - 1.1, direction.angle() + 1.1, 26, Color(tint, fade * (1.0 - i * 0.15)), 3.0, true)
		"wind", "water", "flame", "stones":
			for i in 11:
				var trail := maxf(0.0, travel - float(i) * 0.036)
				var offset := sin(float(i) * 2.4 + progress * 6.0) * float(10 + i * 2)
				var p := start.lerp(finish, trail) + side * offset
				var ink := Color(tint, fade * (1.0 - float(i) * 0.065))
				match style:
					"wind":
						draw_line(p, p - direction * (22.0 - i), ink, 2.0, true)
					"water":
						draw_circle(p, 3.5 + (i % 3) * 1.7, ink, true, -1.0, true)
					"flame":
						draw_line(p, p - direction * 16.0 + side * 5.0, ink, 5.0, true)
					"stones":
						_shard(p, 5.0 + (i % 3) * 2.0, float(i) + progress * 4.0, ink)
		"net":
			for i in 4:
				var p := start.lerp(finish, maxf(0.0, travel - float(i) * 0.11))
				draw_line(p - side * 21.0, p + side * 21.0, Color(tint, fade * 0.7), 2.0, true)
			for i in 3:
				var offset := side * float((i - 1) * 20)
				draw_line(start.lerp(finish, maxf(0.0, travel - 0.33)) + offset, head + offset, Color(tint, fade), 2.0, true)
		"prism":
			for i in 5:
				var tail := start.lerp(finish, maxf(0.0, travel - float(i) * 0.08))
				var point := tail + side * sin(float(i) * 2.3 + progress * 8.0) * 24.0
				_shard(point, 11.0 - i, progress * 4.0 + i, Color(tint.lerp(Color.WHITE, float(i % 2) * 0.55), fade))
			draw_arc(head, 20.0 + 8.0 * progress, 0.0, TAU, 24, Color(tint, fade * 0.65), 2.0, true)
		_:
			draw_line(start.lerp(finish, maxf(0.0, travel - 0.25)), head, Color(tint, fade * 0.6), 4.0, true)
			draw_circle(head, 8.0, Color(tint, fade), true, -1.0, true)
			draw_arc(head, 15.0, 0.0, TAU, 22, Color(tint, fade * 0.7), 2.0, true)

func _draw_self(fade: float) -> void:
	var ink := Color(tint, fade)
	var p := progress
	var center := start
	match style:
		"self_ideas":
			var radius := lerpf(65.0, 15.0, smoothstep(0.0, 0.67, p))
			for i in 6:
				var angle := TAU * i / 6.0 + p * 3.0
				var dot := center + Vector2(cos(angle) * radius, -42.0 + sin(angle) * radius * 0.35)
				_shard(dot, 7.0, PI / 4, ink)
			draw_arc(center + Vector2(0, -42), 10.0, 0, TAU, 24, ink, 3.0, true)
		"self_ripple":
			var ground := center + Vector2(0, 33)
			if p < 0.34:
				draw_circle(ground + Vector2(0, lerpf(-89.0, 0.0, smoothstep(0.0, 0.34, p))), 5.0, ink, true, -1.0, true)
			_waves(ground, 0.29, 0.10, 88.0, 0.27, fade)
		"self_swords":
			for i in 5:
				var angle := TAU * i / 5.0 + p * 5.0
				var hilt := center + Vector2(cos(angle) * 74.0, sin(angle) * 26.0 + 15.0 - p * 40.0)
				draw_colored_polygon(PackedVector2Array([hilt + Vector2(0, -35), hilt + Vector2(7, -6), hilt, hilt + Vector2(-7, -6)]), ink)
				draw_line(hilt + Vector2(-11, 0), hilt + Vector2(11, 0), ink, 3.0, true)
				draw_line(hilt, hilt + Vector2(0, 10), ink, 3.0, true)
		"self_spiral":
			for strand in 3:
				var points := PackedVector2Array()
				for i in 35:
					var t := float(i) / 34.0
					var angle := t * TAU + p * 9.0 + TAU * strand / 3.0
					points.append(center + Vector2(cos(angle) * (80.0 - 28.0 * t), 48.0 - 120.0 * t + sin(angle) * 13.0))
				draw_polyline(points, Color(tint, fade * (0.9 - strand * 0.18)), 3.0, true)
		"self_wings":
			for i in 6:
				var angle := TAU * i / 6.0 + p * 5.0
				var point := center + Vector2(cos(angle) * (34.0 + sin(PI * p) * 50.0), sin(angle) * 35.0 - 28.0 * p)
				var spread := 3.0 + absf(sin(p * 20.0 + i)) * 10.0
				for side in [-1.0, 1.0]:
					_shard(point + Vector2(side * spread, -3), 9.0, side * 0.5, ink)
		"self_shell":
			if p < 0.50:
				_ellipse(center, Vector2(50, 58), Color(tint, fade * 0.9), 3.0)
				if p > 0.19:
					var crack := PackedVector2Array([Vector2(-13, -49), Vector2(4, -22), Vector2(-7, -4), Vector2(14, 16), Vector2(6, 43)])
					for i in crack.size():
						crack[i] += center
					draw_polyline(crack, ink, 3.0, true)
			else:
				var burst := (p - 0.5) * 2.0
				for i in 12:
					var angle := TAU * i / 12.0 + 0.12 * sin(float(i) * 2.0)
					var point := center + Vector2.from_angle(angle) * (39.0 + 71.0 * burst)
					_shard(point, 5.0 + (i % 3) * 3.0, angle + p * 5.0, ink)
		"self_plates":
			for i in 3:
				var travel := smoothstep(float(i) * 0.08, 0.7, p)
				for side in [-1.0, 1.0]:
					var point := center + Vector2(side * lerpf(110.0, 53.0 + i * 6.0, travel), -32.0 + i * 25.0)
					var plate := PackedVector2Array([point + Vector2(-13, -8), point + Vector2(10, -8), point + Vector2(16, 0), point + Vector2(10, 8), point + Vector2(-13, 8), point + Vector2(-18, 0), point + Vector2(-13, -8)])
					draw_colored_polygon(plate.slice(0, 6), Color(tint, fade * 0.25))
					draw_polyline(plate, ink, 3.0, true)
		"self_power":
			_waves(center + Vector2(0, 38), 0.0, 0.16, 100.0, 0.23, fade)
			for i in 9:
				var dot := center + Vector2((i - 4) * 17.0, 27.0 - p * (52.0 + i % 3 * 10.0))
				draw_line(dot, dot - Vector2(0, 13), ink, 3.0, true)
		"self_acid":
			var spread := sin(PI * p)
			_ellipse(center + Vector2(0, 37), Vector2(24.0 + 62.0 * spread, 9.0 + 9.0 * spread), ink, 3.0)
			for i in 11:
				var angle := TAU * i / 11.0
				var dot := center + Vector2(cos(angle) * (25.0 + 52.0 * spread), 33.0 - absf(sin(angle + p * 6.0)) * 53.0 * spread)
				draw_circle(dot, float(3 + i % 4), ink, true, -1.0, true)
		"self_beat":
			_waves(center, 0.0, 0.14, 103.0, 0.68, fade)
			for i in 5:
				var height := (4.0 + absf(sin(p * 20.0 + i)) * 16.0) * fade
				var dot := center + Vector2((i - 2) * 21.0, 37)
				draw_line(dot - Vector2(0, height), dot + Vector2(0, height), ink, 4.0, true)

func _waves(center: Vector2, delay: float, interval: float, radius: float, aspect: float, fade: float) -> void:
	for i in 3:
		var time := (progress - delay - float(i) * interval) / 0.56
		if time > 0.0 and time < 1.0:
			var size := lerpf(12.0, radius, time)
			_ellipse(center, Vector2(size, size * aspect), Color(tint, fade * (1.0 - time)), 3.0)

func _ellipse(center: Vector2, radius: Vector2, ink: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in 41:
		points.append(center + Vector2.from_angle(TAU * i / 40.0) * radius)
	draw_polyline(points, ink, width, true)

func _shard(center: Vector2, radius: float, angle: float, ink: Color) -> void:
	var axis := Vector2.from_angle(angle) * radius
	var edge := axis.orthogonal() * 0.55
	draw_colored_polygon(PackedVector2Array([center + axis, center + edge, center - axis, center - edge]), ink)
