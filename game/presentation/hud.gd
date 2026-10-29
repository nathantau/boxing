class_name Hud
extends Control
## Health/stamina bars, round clock and pips, and center banners. Drawn entirely from the
## sim state, so it is always right after a rollback. The viewer's bars are on the left.

const GOLD := Color(0.91, 0.72, 0.29)
const HEALTH_TOP := Color(1.0, 0.84, 0.35)
const HEALTH_BOTTOM := Color(0.93, 0.5, 0.1)
const LOW_TOP := Color(1.0, 0.38, 0.28)
const LOW_BOTTOM := Color(0.7, 0.06, 0.05)
const TRAIL_COLOR := Color(0.85, 0.1, 0.08)
const STAMINA_TOP := Color(0.5, 0.85, 1.0)
const STAMINA_BOTTOM := Color(0.15, 0.45, 0.9)
const EXHAUSTED_COLOR := Color(1.0, 0.45, 0.1)
const BAR_BACK := Color(0.03, 0.03, 0.05, 0.85)
const FRAME_COLOR := Color(1, 1, 1, 0.22)
const TEXT_COLOR := Color(1, 1, 1)
const OUTLINE_COLOR := Color(0, 0, 0, 0.75)
const PIP_OFF := Color(1, 1, 1, 0.18)
const LOW_HEALTH := 0.3
## The red "damage taken" trail waits this long after a hit, then drains at TRAIL_SPEED per second.
const TRAIL_HOLD := 0.5
const TRAIL_SPEED := 0.8
## Popup text like PARRY! or COUNTER! shows for this many ticks of the triggering action.
const POPUP_TICKS := 30

var state: MatchState
var moves: MoveSet
## Which fighter this screen belongs to (shown on the left, "YOU" in banners).
var viewer := 0
var names: PackedStringArray = ["P1", "P2"]

var _safe := Rect2()
var _font: Font
var _trail := [1.0, 1.0]
var _trail_wait := [0.0, 0.0]


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_font = get_theme_font("font", &"Display")
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	_safe = SafeArea.rect(get_viewport())


## Height of the bar area, so other UI (the debug text) can sit below it.
func top_height() -> float:
	return _unit() * 9.0


func _process(delta: float) -> void:
	if state != null:
		for i in 2:
			_update_trail(i, delta)
	queue_redraw()


## Display-only smoothing (not sim state): snaps up on a heal or a rollback, drains down slowly.
func _update_trail(i: int, delta: float) -> void:
	var health := clampf(state.fighters[i].health / float(moves.max_health), 0.0, 1.0)
	if health >= _trail[i]:
		_trail[i] = health
		_trail_wait[i] = TRAIL_HOLD
	elif _trail_wait[i] > 0.0:
		_trail_wait[i] -= delta
	else:
		_trail[i] = maxf(health, _trail[i] - TRAIL_SPEED * delta)


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
	var badge := Rect2(center_x - 4.5 * u, top - 0.5 * u, 9.0 * u, 6.5 * u)
	draw_rect(badge, BAR_BACK)
	draw_rect(Rect2(badge.position, Vector2(badge.size.x, 0.4 * u)), GOLD)
	draw_rect(badge, FRAME_COLOR, false, 1.0)
	var urgent := seconds <= 10 and state.phase == MatchState.Phase.FIGHT
	_text(badge.get_center() + Vector2(0, 0.3 * u), str(seconds), int(4.6 * u), HORIZONTAL_ALIGNMENT_CENTER, LOW_TOP if urgent else TEXT_COLOR)
	_draw_pips(state.wins(viewer), Vector2(badge.position.x - 1.8 * u, badge.get_center().y), -1)
	_draw_pips(state.wins(1 - viewer), Vector2(badge.end.x + 1.8 * u, badge.get_center().y), 1)

	_draw_banner()


## Bars for one fighter: slanted, outer edge anchored, draining toward the outside.
## Mirrored bars are the left bars reflected.
func _draw_fighter(index: int, pos: Vector2, width: float, mirrored: bool) -> void:
	var f := state.fighters[index]
	var u := _unit()
	var health_h := 2.8 * u
	var stamina_h := 1.0 * u
	var health := clampf(f.health / float(moves.max_health), 0.0, 1.0)
	var stamina := clampf(f.stamina / float(moves.max_stamina), 0.0, 1.0)
	var align := HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT

	var name_pos := pos + Vector2(width if mirrored else 0.0, 0.2 * u)
	_text(name_pos, names[index].to_upper(), int(2.2 * u), align)

	var health_rect := Rect2(pos + Vector2(0, 1.6 * u), Vector2(width, health_h))
	_bar(health_rect, 0.0, 1.0, mirrored, BAR_BACK, BAR_BACK)
	_bar(health_rect, health, _trail[index], mirrored, TRAIL_COLOR, TRAIL_COLOR.darkened(0.3))
	var low := health < LOW_HEALTH
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012) if low else 0.0
	var top_color := LOW_TOP.lerp(Color.WHITE, 0.25 * pulse) if low else HEALTH_TOP
	_bar(health_rect, 0.0, health, mirrored, top_color, LOW_BOTTOM if low else HEALTH_BOTTOM)
	_bar(health_rect, 0.0, health, mirrored, Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.0), 0.4)
	_bar_frame(health_rect, mirrored)

	var stamina_rect := Rect2(health_rect.position + Vector2(0, health_h + 0.7 * u), Vector2(width * 0.7, stamina_h))
	if mirrored:
		stamina_rect.position.x += width * 0.3
	var blink := f.exhausted and (state.tick >> 3) & 1 == 0
	_bar(stamina_rect, 0.0, 1.0, mirrored, BAR_BACK, BAR_BACK)
	if f.exhausted:
		_bar(stamina_rect, 0.0, stamina, mirrored, EXHAUSTED_COLOR if blink else EXHAUSTED_COLOR.darkened(0.4), EXHAUSTED_COLOR.darkened(0.5))
	else:
		_bar(stamina_rect, 0.0, stamina, mirrored, STAMINA_TOP, STAMINA_BOTTOM)
	_bar_frame(stamina_rect, mirrored)
	if f.exhausted:
		var label_pos := stamina_rect.position + Vector2(0, stamina_h + 1.8 * u)
		if mirrored:
			label_pos.x = stamina_rect.end.x
		_text(label_pos, "EXHAUSTED", int(1.7 * u), align, EXHAUSTED_COLOR)

	var popup := _popup(f)
	if popup != "":
		var popup_pos := Vector2(pos.x + (width * 0.75 if mirrored else width * 0.25), _safe.position.y + _safe.size.y * 0.32)
		var pop := 1.0 + 0.4 * maxf(0.0, 1.0 - f.frame / 6.0)
		_text(popup_pos, popup, int(3.8 * u * pop), HORIZONTAL_ALIGNMENT_CENTER, GOLD)


## The slant of a bar's ends, as a fraction of its height.
func _slant(rect: Rect2) -> float:
	return rect.size.y * 0.8


## Fills the slanted bar between fractions `from` and `to` of its length (0 = outer end),
## with a vertical gradient.
## `depth` < 1 draws only the top part of the bar (for the shine), keeping the same slant.
func _bar(rect: Rect2, from: float, to: float, mirrored: bool, top: Color, bottom: Color, depth := 1.0) -> void:
	if to <= from:
		return
	var s := _slant(rect)
	var run := rect.size.x - s
	var bottom_y := rect.position.y + rect.size.y * depth
	var inset := s * (1.0 - depth)
	var pts := PackedVector2Array([
		Vector2(rect.position.x + s + from * run, rect.position.y),
		Vector2(rect.position.x + s + to * run, rect.position.y),
		Vector2(rect.position.x + inset + to * run, bottom_y),
		Vector2(rect.position.x + inset + from * run, bottom_y),
	])
	if mirrored:
		for i in pts.size():
			pts[i].x = rect.position.x + rect.end.x - pts[i].x
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _bar_frame(rect: Rect2, mirrored: bool) -> void:
	var s := _slant(rect)
	var pts := PackedVector2Array([
		Vector2(rect.position.x + s, rect.position.y), Vector2(rect.end.x, rect.position.y),
		Vector2(rect.end.x - s, rect.end.y), Vector2(rect.position.x, rect.end.y),
		Vector2(rect.position.x + s, rect.position.y),
	])
	if mirrored:
		for i in pts.size():
			pts[i].x = rect.position.x + rect.end.x - pts[i].x
	draw_polyline(pts, FRAME_COLOR, 1.5, true)


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
		var r := 0.9 * u
		var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(diamond, GOLD if i < count else PIP_OFF)
		if i < count:
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(1, 0.95, 0.75), 1.0, true)


func _draw_banner() -> void:
	var u := _unit()
	var title := ""
	var subtitle := ""
	var age := 99  # ticks since the title appeared, for the pop-in
	var color := TEXT_COLOR
	match state.phase:
		MatchState.Phase.INTRO:
			var half := moves.intro_ticks / 2
			if state.phase_timer > half:
				title = "ROUND %d" % state.round_number
				age = moves.intro_ticks - state.phase_timer
			else:
				title = "FIGHT!"
				age = half - state.phase_timer
				color = GOLD
		MatchState.Phase.ROUND_OVER:
			title = _round_end_reason()
			subtitle = _result_text(state.round_winner, "ROUND")
			age = moves.round_over_ticks - state.phase_timer
			color = GOLD
		MatchState.Phase.MATCH_OVER:
			title = _result_text(state.match_winner, "MATCH")
			color = GOLD if state.match_winner == viewer else TEXT_COLOR
	if title == "":
		return
	var center := _safe.get_center() + Vector2(0, -6.0 * u)
	# A dark band behind the text that fades out to the sides.
	var band_h := 13.0 * u if subtitle != "" else 10.0 * u
	var band_top := center.y - 6.0 * u
	var clear := Color(0, 0, 0, 0)
	var dark := Color(0, 0, 0, 0.55)
	var mid := _safe.get_center().x
	for side: float in [-1.0, 1.0]:
		var outer := mid + side * _safe.size.x * 0.5
		draw_polygon(PackedVector2Array([Vector2(mid, band_top), Vector2(outer, band_top), Vector2(outer, band_top + band_h), Vector2(mid, band_top + band_h)]),
			PackedColorArray([dark, clear, clear, dark]))
	var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 8.0)
	_text(center, title, int(8.5 * u * pop), HORIZONTAL_ALIGNMENT_CENTER, color)
	if subtitle != "":
		_text(center + Vector2(0, 5.2 * u), subtitle, int(2.6 * u))


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


## Outlined display text. `pos` is the anchor: left, center or right per `align`.
func _text(pos: Vector2, text: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER, color := TEXT_COLOR) -> void:
	var font := _font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	var baseline := Vector2(x, pos.y + size * 0.35)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(2, size / 8), OUTLINE_COLOR)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
