class_name TouchControls
extends Control
## Landscape touch layout: hold the left/right edge to dodge, hold the shield to block,
## swipe anywhere else to punch. A swipe is classified as soon as the finger passes a short
## distance, not on release, so punches come out fast. Output goes into `source`.
## On desktop, mouse drags act as touches (input_devices/pointing/emulate_touch_from_mouse).

enum Zone { SWIPE, DODGE_L, DODGE_R, SHIELD }

## Touches that start on a visible Control in this group (menu buttons etc.) are left alone.
const BLOCKER_GROUP := &"touch_blockers"

## Width of each dodge strip, as a fraction of the safe-area width.
const DODGE_STRIP := 0.17
## Shield diameter as a fraction of the safe-area height (about 88 pt on a modern iPhone).
const SHIELD_SIZE := 0.22
## Shield touches count this far outside the drawn circle.
const SHIELD_SLOP := 1.2
const SHIELD_MARGIN := 0.04
## Distance before a swipe counts, as a fraction of the safe-area height.
const SWIPE_DISTANCE := 0.05
## Swipes within this angle of straight up are jabs; other upward/sideways swipes are hooks.
const JAB_CONE_DEG := 30.0
## Hooks follow the fist: a left hook travels left to right, so swiping right throws it.
## Set false to make "swipe left" throw the left hook instead.
const HOOKS_FOLLOW_FIST := true

const ZONE_BITS := {
	Zone.SWIPE: 0,
	Zone.DODGE_L: InputBits.DODGE_L,
	Zone.DODGE_R: InputBits.DODGE_R,
	Zone.SHIELD: InputBits.BLOCK,
}

const IDLE_COLOR := Color(1, 1, 1, 0.08)
const HELD_COLOR := Color(1, 1, 1, 0.28)
const LINE_COLOR := Color(1, 1, 1, 0.35)

var source := InputSource.new()
## Finger index -> Touch.
var _touches := {}
var _safe := Rect2()


class Touch:
	var zone: Zone
	var start: Vector2
	## Lowest point reached; an uppercut fires when the finger comes back up from it.
	var lowest: Vector2
	## The swipe went down first: an uppercut is pending.
	var dipping := false
	## This touch already produced its punch.
	var done := false


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	_safe = SafeArea.rect(get_viewport())
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_touches.clear()
		_update_held()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _over_blocker(touch.position):
				return
			var t := Touch.new()
			t.zone = _zone_at(touch.position)
			t.start = touch.position
			t.lowest = touch.position
			_touches[touch.index] = t
		elif _touches.has(touch.index):
			var t: Touch = _touches[touch.index]
			if t.dipping and not t.done:
				source.press(InputBits.UPPERCUT)  # Forgiving: a plain downward swipe also uppercuts.
			_touches.erase(touch.index)
		_update_held()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var t: Touch = _touches.get(drag.index)
		if t != null and t.zone == Zone.SWIPE and not t.done:
			_track_swipe(t, drag.position)


func _track_swipe(t: Touch, pos: Vector2) -> void:
	var min_distance := SWIPE_DISTANCE * _safe.size.y
	if t.dipping:
		if pos.y > t.lowest.y:
			t.lowest = pos
		elif t.lowest.y - pos.y >= min_distance:
			_fire(t, InputBits.UPPERCUT)
		return

	var d := pos - t.start
	if d.length() < min_distance:
		return
	if d.y > 0.0 and d.y >= absf(d.x):
		t.dipping = true
		t.lowest = pos
	elif rad_to_deg(absf(Vector2.UP.angle_to(d))) <= JAB_CONE_DEG:
		_fire(t, InputBits.JAB)
	elif (d.x > 0.0) == HOOKS_FOLLOW_FIST:
		_fire(t, InputBits.HOOK_L)
	else:
		_fire(t, InputBits.HOOK_R)


func _over_blocker(pos: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group(BLOCKER_GROUP):
		var control := node as Control
		if control and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return true
	return false


func _fire(t: Touch, bits: int) -> void:
	t.done = true
	source.press(bits)


func _update_held() -> void:
	var bits := 0
	for t: Touch in _touches.values():
		bits |= ZONE_BITS[t.zone]
	source.held = bits
	queue_redraw()


func _zone_at(pos: Vector2) -> Zone:
	if pos.distance_to(_shield_center()) <= _shield_radius() * SHIELD_SLOP:
		return Zone.SHIELD
	var strip := DODGE_STRIP * _safe.size.x
	if pos.x < _safe.position.x + strip:
		return Zone.DODGE_L
	if pos.x > _safe.end.x - strip:
		return Zone.DODGE_R
	return Zone.SWIPE


func _shield_radius() -> float:
	return SHIELD_SIZE * _safe.size.y * 0.5


func _shield_center() -> Vector2:
	return Vector2(_safe.get_center().x, _safe.end.y - _shield_radius() - SHIELD_MARGIN * _safe.size.y)


func _draw() -> void:
	var strip := DODGE_STRIP * _safe.size.x
	var left := Rect2(_safe.position, Vector2(strip, _safe.size.y))
	var right := Rect2(Vector2(_safe.end.x - strip, _safe.position.y), Vector2(strip, _safe.size.y))
	_draw_zone(left, source.held & InputBits.DODGE_L, "<")
	_draw_zone(right, source.held & InputBits.DODGE_R, ">")

	var center := _shield_center()
	var radius := _shield_radius()
	draw_circle(center, radius, HELD_COLOR if source.held & InputBits.BLOCK else IDLE_COLOR)
	draw_arc(center, radius, 0.0, TAU, 48, LINE_COLOR, 2.0, true)
	_draw_label(center, "BLOCK")


func _draw_zone(rect: Rect2, is_held: int, label: String) -> void:
	draw_rect(rect, HELD_COLOR if is_held else IDLE_COLOR)
	_draw_label(rect.get_center(), label)


func _draw_label(center: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	var size := int(_safe.size.y * 0.04)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, center + Vector2(-width * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, LINE_COLOR)
