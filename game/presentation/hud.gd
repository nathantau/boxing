class_name Hud
extends Control
## Health/stamina bars, round clock and pips, and center banners. Drawn entirely from the
## sim state, so it is always right after a rollback. The viewer's bars are on the left.

const HEALTH_COLOR := Color(0.9, 0.2, 0.15)
const HEALTH_BACK := Color(0.25, 0.05, 0.05, 0.8)
const STAMINA_COLOR := Color(0.95, 0.8, 0.2)
const EXHAUSTED_COLOR := Color(0.9, 0.3, 0.1)
const BAR_BACK := Color(0, 0, 0, 0.5)
const TEXT_COLOR := Color(1, 1, 1)
const SHADOW_COLOR := Color(0, 0, 0, 0.6)
const PIP_ON := Color(1.0, 0.85, 0.3)
const PIP_OFF := Color(1, 1, 1, 0.25)
## Popup text like PARRY! or COUNTER! shows for this many ticks of the triggering action.
const POPUP_TICKS := 30

var state: MatchState
var moves: MoveSet
## Which fighter this screen belongs to (shown on the left, "YOU" in banners).
var viewer := 0
var names: PackedStringArray = ["P1", "P2"]

var _safe := Rect2()


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	_safe = SafeArea.rect(get_viewport())


## Height of the bar area, so other UI (the debug text) can sit below it.
func top_height() -> float:
	return _unit() * 9.0


func _process(_delta: float) -> void:
	queue_redraw()


## One "unit" of HUD size, scaled to the screen.
func _unit() -> float:
	return _safe.size.y / 72.0


func _draw() -> void:
	if state == null:
		return
	var u := _unit()
	var margin := 2.0 * u
	var bar_w := _safe.size.x * 0.36
	var top := _safe.position.y + margin
	var left_x := _safe.position.x + margin
	var right_x := _safe.end.x - margin - bar_w
	_draw_fighter(viewer, Vector2(left_x, top), bar_w, false)
	_draw_fighter(1 - viewer, Vector2(right_x, top), bar_w, true)

	# Round clock and win pips.
	var center_x := _safe.get_center().x
	var seconds := Fixed.ticks_to_seconds(maxi(state.round_timer, 0), Sim.TICK_RATE)
	_text(Vector2(center_x, top + 3.0 * u), str(seconds), int(4.5 * u))
	_draw_pips(state.wins(viewer), Vector2(center_x - 3.0 * u, top + 6.5 * u), -1)
	_draw_pips(state.wins(1 - viewer), Vector2(center_x + 3.0 * u, top + 6.5 * u), 1)

	_draw_banner()


## Bars for one fighter. Mirrored bars fill from the right edge.
func _draw_fighter(index: int, pos: Vector2, width: float, mirrored: bool) -> void:
	var f := state.fighters[index]
	var u := _unit()
	var health_h := 2.6 * u
	var stamina_h := 1.1 * u
	var health := clampf(f.health / float(moves.max_health), 0.0, 1.0)
	var stamina := clampf(f.stamina / float(moves.max_stamina), 0.0, 1.0)

	var name_pos := pos + Vector2(width if mirrored else 0.0, 0.0)
	_text(name_pos, names[index], int(2.0 * u), HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT)

	var health_rect := Rect2(pos + Vector2(0, 1.2 * u), Vector2(width, health_h))
	draw_rect(health_rect, HEALTH_BACK)
	draw_rect(_fill(health_rect, health, mirrored), HEALTH_COLOR)
	draw_rect(health_rect, Color(1, 1, 1, 0.5), false, 1.0)

	var stamina_rect := Rect2(health_rect.position + Vector2(0, health_h + 0.6 * u), Vector2(width * 0.8, stamina_h))
	if mirrored:
		stamina_rect.position.x += width * 0.2
	var blink := f.exhausted and (state.tick >> 3) & 1 == 0
	draw_rect(stamina_rect, BAR_BACK)
	draw_rect(_fill(stamina_rect, stamina, mirrored), EXHAUSTED_COLOR if blink else STAMINA_COLOR)
	if f.exhausted:
		var label_pos := stamina_rect.position + Vector2(0, stamina_h + 1.8 * u)
		if mirrored:
			label_pos.x = stamina_rect.end.x
		_text(label_pos, "EXHAUSTED", int(1.6 * u), HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT, EXHAUSTED_COLOR)

	var popup := _popup(f)
	if popup != "":
		var popup_pos := Vector2(pos.x + (width * 0.75 if mirrored else width * 0.25), _safe.position.y + _safe.size.y * 0.32)
		_text(popup_pos, popup, int(3.5 * u), HORIZONTAL_ALIGNMENT_CENTER, PIP_ON)


static func _fill(rect: Rect2, amount: float, mirrored: bool) -> Rect2:
	var w := rect.size.x * amount
	var x := rect.end.x - w if mirrored else rect.position.x
	return Rect2(Vector2(x, rect.position.y), Vector2(w, rect.size.y))


func _popup(f: FighterState) -> String:
	if state.phase != MatchState.Phase.FIGHT or f.frame >= POPUP_TICKS:
		return ""
	match f.action:
		FighterState.PARRY:
			return "PARRY!"
		FighterState.KNOCKDOWN:
			return "DOWN!"
		FighterState.STAGGER:
			return "STAGGERED"
		FighterState.HITSTUN:
			return "COUNTER!" if f.took_counter else ""
	return ""


func _draw_pips(count: int, origin: Vector2, direction: int) -> void:
	var u := _unit()
	for i in moves.rounds_to_win:
		var c := origin + Vector2(direction * i * 2.4 * u, 0)
		draw_circle(c, 0.8 * u, PIP_ON if i < count else PIP_OFF)


func _draw_banner() -> void:
	var u := _unit()
	var title := ""
	var subtitle := ""
	match state.phase:
		MatchState.Phase.INTRO:
			title = "ROUND %d" % state.round_number if state.phase_timer * 2 > moves.intro_ticks else "FIGHT!"
		MatchState.Phase.ROUND_OVER:
			title = _round_end_reason()
			subtitle = _result_text(state.round_winner, "ROUND")
		MatchState.Phase.MATCH_OVER:
			title = _result_text(state.match_winner, "MATCH")
			subtitle = "Tap or press R for a rematch"
	if title == "":
		return
	var center := _safe.get_center() + Vector2(0, -6.0 * u)
	_text(center, title, int(8.0 * u))
	if subtitle != "":
		_text(center + Vector2(0, 5.0 * u), subtitle, int(2.6 * u))


func _round_end_reason() -> String:
	for f in state.fighters:
		if f.action == FighterState.KO:
			return "T.K.O." if f.knockdowns >= moves.max_knockdowns else "K.O."
	return "DRAW" if state.round_winner == MatchState.DRAW else "TIME"


func _result_text(winner: int, what: String) -> String:
	if winner == MatchState.DRAW:
		return "DRAW"
	if winner == viewer:
		return "YOU WIN" if what == "MATCH" else "YOU WIN THE ROUND"
	return "YOU LOSE" if what == "MATCH" else "%s WINS THE ROUND" % names[winner]


## Text with a drop shadow. `pos` is the baseline anchor: left, center or right per `align`.
func _text(pos: Vector2, text: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER, color := TEXT_COLOR) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	var baseline := Vector2(x, pos.y + size * 0.35)
	draw_string(font, baseline + Vector2(2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SHADOW_COLOR)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
