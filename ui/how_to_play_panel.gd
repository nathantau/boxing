class_name HowToPlayPanel
extends VBoxContainer
## The controls and core rules, inside the main menu. Each gesture gets a little drawn phone
## screen showing the swipe or the zone to hold.

signal closed

const GOLD := Color(0.91, 0.72, 0.29)

## [icon kind, move name, one-line hint]
const TOUCH := [
	["up_left", "JAB", "Swipe up on the left half. Fast."],
	["up_right", "CROSS", "Swipe up on the right half. Harder."],
	["right", "LEFT HOOK", "Swipe right."],
	["left", "RIGHT HOOK", "Swipe left."],
	["down_up", "UPPERCUT", "Swipe down, then up. Slow, huge damage."],
	["edges", "BLOCK", "Hold both edges, or the BLOCK circle."],
	["edge_left", "DODGE LEFT", "Hold the left edge."],
	["edge_right", "DODGE RIGHT", "Hold the right edge."],
]

const RULES := [
	"PARRY  ·  punch just before their punch lands. They stagger; your next hits are counters.",
	"DODGE  ·  hooks must be dodged away from the fist. Uppercuts punish a dodge.",
	"STAMINA  ·  every punch costs some. Run out and you're slow and can't block.",
	"KNOCKDOWNS  ·  a quick burst of damage drops them. Three in a round is a T.K.O.",
]

const KEYS := "KEYBOARD  W jab · F cross · Q / E hooks · S uppercut · A / D dodge · Space block      PAD  X · A · LB / RB · Y · d-pad · B"

var _back: Button
var _then := Callable()


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.theme_type_variation = &"Display"
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", GOLD)
	add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for entry: Array in TOUCH:
		grid.add_child(_gesture_row(entry[0], _move_name(entry[1]), entry[2]))

	for rule: String in RULES:
		var label := Label.new()
		label.text = rule
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.9))
		add_child(label)
	if not OS.has_feature("mobile"):
		var keys := Label.new()
		keys.text = KEYS
		keys.add_theme_font_size_override("font_size", 15)
		keys.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		add_child(keys)

	_back = Button.new()
	_back.theme_type_variation = &"MenuItem"
	_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(_on_back)
	add_child(_back)
	visibility_changed.connect(_on_shown)


## Show the panel; leaving it runs `then` (e.g. start the fight) instead of going back.
func open_then(then: Callable) -> void:
	_then = then
	visible = true
	_on_shown()


func _on_shown() -> void:
	if not visible:
		return
	_back.text = "LET'S FIGHT" if _then.is_valid() else "BACK"
	_back.grab_focus.call_deferred()


func _on_back() -> void:
	var then := _then
	_then = Callable()
	if then.is_valid():
		then.call()
	else:
		closed.emit()


## Swipe right throws the left hook unless the player flipped that in Settings.
static func _move_name(name: String) -> String:
	if Settings.hooks_follow_fist:
		return name
	return {"LEFT HOOK": "RIGHT HOOK", "RIGHT HOOK": "LEFT HOOK"}.get(name, name)


func _gesture_row(kind: String, move: String, hint: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var icon := GestureIcon.new()
	icon.kind = kind
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -4)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := Label.new()
	name_label.theme_type_variation = &"Display"
	name_label.text = move
	name_label.add_theme_font_size_override("font_size", 24)
	text.add_child(name_label)
	var hint_label := Label.new()
	hint_label.text = hint
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	text.add_child(hint_label)
	row.add_child(text)
	return row


## A tiny landscape phone screen with the gesture drawn on it.
class GestureIcon:
	extends Control

	const SIZE := Vector2(76, 44)
	const FRAME := Color(1, 1, 1, 0.35)
	const STROKE := Color(0.91, 0.72, 0.29)
	const ZONE := Color(0.91, 0.72, 0.29, 0.35)

	var kind := ""

	func _init() -> void:
		custom_minimum_size = SIZE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, SIZE)
		draw_rect(r, Color(0, 0, 0, 0.35))
		draw_rect(r, FRAME, false, 1.5)
		var strip := SIZE.x * 0.17
		var mid := SIZE * 0.5
		match kind:
			"up_left":
				_arrow([Vector2(mid.x - 16, mid.y + 12), Vector2(mid.x - 16, mid.y - 12)])
				draw_line(Vector2(mid.x, 6), Vector2(mid.x, SIZE.y - 6), Color(1, 1, 1, 0.15), 1.0)
			"up_right":
				_arrow([Vector2(mid.x + 16, mid.y + 12), Vector2(mid.x + 16, mid.y - 12)])
				draw_line(Vector2(mid.x, 6), Vector2(mid.x, SIZE.y - 6), Color(1, 1, 1, 0.15), 1.0)
			"right":
				_arrow([Vector2(mid.x - 16, mid.y + 4), Vector2(mid.x + 16, mid.y - 4)])
			"left":
				_arrow([Vector2(mid.x + 16, mid.y + 4), Vector2(mid.x - 16, mid.y - 4)])
			"down_up":
				_arrow([Vector2(mid.x - 8, mid.y - 12), Vector2(mid.x - 2, mid.y + 12), Vector2(mid.x + 8, mid.y - 12)])
			"edges":
				draw_rect(Rect2(0, 0, strip, SIZE.y), ZONE)
				draw_rect(Rect2(SIZE.x - strip, 0, strip, SIZE.y), ZONE)
				draw_arc(mid + Vector2(0, 6), 8.0, 0.0, TAU, 20, STROKE, 2.0, true)
			"edge_left":
				draw_rect(Rect2(0, 0, strip, SIZE.y), ZONE)
				_arrow([Vector2(mid.x + 4, mid.y), Vector2(mid.x - 14, mid.y)])
			"edge_right":
				draw_rect(Rect2(SIZE.x - strip, 0, strip, SIZE.y), ZONE)
				_arrow([Vector2(mid.x - 4, mid.y), Vector2(mid.x + 14, mid.y)])

	## A stroke along `points` with an arrowhead at the last one and a dot where it starts.
	func _arrow(points: Array) -> void:
		var line := PackedVector2Array(points)
		draw_polyline(line, STROKE, 3.0, true)
		draw_circle(line[0], 3.5, STROKE)
		var tip := line[line.size() - 1]
		var dir := (tip - line[line.size() - 2]).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip + dir * 5.0, tip - dir * 5.0 + side * 5.0, tip - dir * 5.0 - side * 5.0]), STROKE)
