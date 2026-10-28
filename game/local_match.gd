extends Node
## Offline 1v1 on one machine: two local input sets (or the AI) drive the same Sim the online
## game uses. The sim runs at a fixed 60 Hz from an integer microsecond accumulator,
## independent of frame rate.

const USEC := 1_000_000
const MAX_TICKS_PER_FRAME := 4

@export var moves: MoveSet = preload("res://sim/moves.tres")

@onready var _view: MatchView = $MatchView

var state: MatchState
## Every source for a player is ORed together, so P1 can mix keyboard, gamepad and touch.
var _players: Array[Array] = [[], []]
## AI level per player, or -1 for human control.
var _ai_levels := [-1, -1]
## Elapsed time scaled by the tick rate, in microseconds; one tick per USEC.
var _acc := 0
var _last_usec := 0


func _ready() -> void:
	state = MatchState.create(moves)
	_view.moves = moves
	var ai_vs_ai := "--ai-vs-ai" in OS.get_cmdline_user_args()
	_set_control(0, AISource.Level.HARD if ai_vs_ai else -1)
	_set_control(1, Game.p2_control)
	_view.set_viewer(0)
	_view.menu_pressed.connect(Game.goto.bind(Game.MENU))
	_view.results.menu_pressed.connect(Game.goto.bind(Game.MENU))
	_view.results.rematch_pressed.connect(_restart)
	_last_usec = Time.get_ticks_usec()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_C:
				_view.set_viewer(1 - _view.viewer)
			KEY_R:
				_restart()
			KEY_ESCAPE:
				Game.goto(Game.MENU)
			KEY_T:
				_view.touch.visible = not _view.touch.visible
			KEY_F3:
				_view.debug_label.visible = not _view.debug_label.visible
			KEY_1:
				_set_control(0, -1 if _ai_levels[0] >= 0 else AISource.Level.HARD)
			KEY_2:
				_set_control(1, _ai_levels[1] + 1 if _ai_levels[1] < AISource.Level.HARD else -1)


func _process(_delta: float) -> void:
	for sources in _players:
		for source: InputSource in sources:
			source.sample()

	var now := Time.get_ticks_usec()
	_acc += (now - _last_usec) * Sim.TICK_RATE
	_last_usec = now
	var ticks := 0
	while _acc >= USEC and ticks < MAX_TICKS_PER_FRAME:
		for sources in _players:
			for source: InputSource in sources:
				source.observe(state)
		Sim.step(state, _consume(0), _consume(1), moves)
		_acc -= USEC
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_acc = 0  # Too far behind (hitch or debugger pause): drop the backlog instead of fast-forwarding.

	_view.show_state(state)
	_view.debug_label.text = _debug_text()


func _restart() -> void:
	state = MatchState.create(moves)
	_view.fx.reset()


## level: an AISource.Level, or -1 for human (keyboard + gamepad, plus touch for P1).
func _set_control(player: int, level: int) -> void:
	_ai_levels[player] = level
	if level >= 0:
		_players[player] = [AISource.new(player, moves, level as AISource.Level, Time.get_ticks_usec())]
		_view.hud.names[player] = "CPU"
		return
	var keys := LocalInputSource.P1_KEYS if player == 0 else LocalInputSource.P2_KEYS
	_players[player] = [LocalInputSource.new(keys, player)]
	if player == 0:
		_players[player].append(_view.touch.source)
	_view.hud.names[player] = "P%d" % (player + 1)


func _control_name(player: int) -> String:
	return "human" if _ai_levels[player] < 0 else "AI " + AISource.LEVEL_NAMES[_ai_levels[player]]


func _consume(player: int) -> int:
	var bits := 0
	for source: InputSource in _players[player]:
		bits |= source.consume()
	return bits


func _debug_text() -> String:
	var lines := PackedStringArray([
		"tick %d   fps %d   hash %08x" % [state.tick, Engine.get_frames_per_second(), state.state_hash()],
	])
	lines.append(_view.perf_line())
	lines.append_array(_view.fighter_debug_lines(state, [_control_name(0), _control_name(1)]))
	if OS.has_feature("mobile"):
		return "\n".join(lines)
	lines.append("")
	lines.append("P1  W jab  Q/E hooks  S uppercut  A/D dodge  Space block   (pad 1: X, LB/RB, Y, d-pad/stick, B/RT)")
	lines.append("P2  I jab  U/O hooks  K uppercut  J/L dodge  P block       (pad 2: same)")
	lines.append("1/2 toggle P1 AI / cycle P2 human-easy-normal-hard")
	lines.append("C swap camera   R restart   Esc menu   T touch overlay (mouse drags act as touches)   F3 hide this")
	return "\n".join(lines)
