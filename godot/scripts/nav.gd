extends Node
## Autoload: 화면 스택 + 전환 애니메이션 + Android 뒤로 가기
## 화면은 Control. 선택적으로 on_shown() / on_back() -> bool(true면 직접 처리함) 을 구현할 수 있다.

const DURATION := 0.32

var root: Control
var _stack: Array[Control] = []
var _busy := false

func _ready() -> void:
	# 뒤로 가기 키로 앱이 바로 꺼지지 않게 하고 직접 처리
	get_tree().set_quit_on_go_back(false)

func setup(container: Control) -> void:
	root = container

func current() -> Control:
	return _stack.back() if not _stack.is_empty() else null

func depth() -> int:
	return _stack.size()

func push(screen: Control, animate := true) -> void:
	if _busy:
		screen.free()
		return
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	var prev := current()
	root.add_child(screen)
	_stack.append(screen)
	if not animate or prev == null:
		_shown(screen)
		return
	_busy = true
	var w := root.size.x
	screen.position.x = w
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(screen, "position:x", 0.0, DURATION)
	tw.tween_property(prev, "position:x", -w * 0.28, DURATION)
	tw.tween_property(prev, "modulate", Color(0.55, 0.55, 0.55), DURATION)
	tw.chain().tween_callback(func():
		prev.visible = false
		_busy = false
		_shown(screen))

## 오버레이 화면: 이전 화면을 그대로 둔 채 위에 얹는다. 열고 닫는 애니메이션은 화면이 직접 처리하고,
## 닫힐 때 drop(self) 를 호출한다.
func push_overlay(screen: Control) -> void:
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	_stack.append(screen)
	_shown(screen)

func drop(screen: Control) -> void:
	_stack.erase(screen)
	screen.queue_free()
	var cur := current()
	if cur:
		_shown(cur)

func pop() -> void:
	if _busy or _stack.size() <= 1:
		return
	_busy = true
	var screen: Control = _stack.pop_back()
	var prev := current()
	prev.visible = true
	var w := root.size.x
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(screen, "position:x", w, DURATION)
	tw.tween_property(prev, "position:x", 0.0, DURATION)
	tw.tween_property(prev, "modulate", Color.WHITE, DURATION)
	tw.chain().tween_callback(func():
		screen.queue_free()
		_busy = false
		_shown(prev))

## 첫 화면으로: 사이 화면들은 바로 없애고 맨 위 화면만 밀어내는 전환
func pop_to_root() -> void:
	if _busy:
		await get_tree().create_timer(DURATION + 0.05).timeout
	while _stack.size() > 2:
		var mid: Control = _stack.pop_at(_stack.size() - 2)
		mid.queue_free()
	pop()

func back() -> void:
	var cur := current()
	if cur and cur.has_method("on_back") and cur.on_back():
		return
	if _stack.size() > 1:
		pop()
	else:
		get_tree().quit()

func _shown(screen: Control) -> void:
	if screen.has_method("on_shown"):
		screen.on_shown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()

func _unhandled_input(event: InputEvent) -> void:
	# PC 테스트용: Esc / Backspace = 뒤로
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_BACKSPACE]:
		back()
