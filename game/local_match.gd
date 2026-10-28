extends Node3D
## Offline 1v1 on one machine: two local input sets drive the same Sim the online game uses.
## The sim runs at a fixed 60 Hz from an integer microsecond accumulator, independent of frame rate.

const TICK_RATE := 60
const USEC := 1_000_000
const MAX_TICKS_PER_FRAME := 4

const ACTION_NAMES := ["idle", "attack", "block", "dodge", "hitstun", "blockstun", "KO", "parry", "stagger", "down"]
const MOVE_NAMES := ["-", "jab", "hook L", "hook R", "uppercut", "dodge L", "dodge R"]

@export var moves: MoveSet = preload("res://sim/moves.tres")

@onready var _boxers: Array[BoxerView] = [$BoxerA, $BoxerB]
@onready var _camera: CameraRig = $Camera
@onready var _debug: Label = $DebugHUD/Label
@onready var _touch: TouchControls = $TouchLayer/TouchControls
@onready var _hud: Hud = $HUDLayer/HUD

var state: MatchState
## Every source for a player is ORed together, so P1 can mix keyboard, gamepad and touch.
var _players: Array[Array] = [
	[LocalInputSource.new(LocalInputSource.P1_KEYS, 0)],
	[LocalInputSource.new(LocalInputSource.P2_KEYS, 1)],
]
## Elapsed time scaled by TICK_RATE, in microseconds; one tick per USEC.
var _acc := 0
var _last_usec := 0
var _camera_player := 0


func _ready() -> void:
	state = MatchState.create(moves)
	_hud.moves = moves
	_players[0].append(_touch.source)
	_set_camera(0)
	get_viewport().size_changed.connect(_place_debug)
	_place_debug()
	_last_usec = Time.get_ticks_usec()


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch and touch.pressed and state.phase == MatchState.Phase.MATCH_OVER:
		state = MatchState.create(moves)
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_C:
				_set_camera(1 - _camera_player)
			KEY_R:
				state = MatchState.create(moves)
			KEY_T:
				_touch.visible = not _touch.visible
			KEY_F3:
				_debug.visible = not _debug.visible


func _process(_delta: float) -> void:
	for sources in _players:
		for source: InputSource in sources:
			source.sample()

	var now := Time.get_ticks_usec()
	_acc += (now - _last_usec) * TICK_RATE
	_last_usec = now
	var ticks := 0
	while _acc >= USEC and ticks < MAX_TICKS_PER_FRAME:
		Sim.step(state, _consume(0), _consume(1), moves)
		_acc -= USEC
		ticks += 1
	if ticks == MAX_TICKS_PER_FRAME:
		_acc = 0  # Too far behind (hitch or debugger pause): drop the backlog instead of fast-forwarding.

	for i in 2:
		_boxers[i].show_state(state.fighters[i], moves)
	_hud.state = state
	_debug.text = _debug_text()


func _consume(player: int) -> int:
	var bits := 0
	for source: InputSource in _players[player]:
		bits |= source.consume()
	return bits


func _place_debug() -> void:
	_debug.position = SafeArea.rect(get_viewport()).position + Vector2(16, _hud.top_height() + 24)


func _set_camera(player: int) -> void:
	_camera_player = player
	_hud.viewer = player
	_camera.focus = _boxers[player]
	_camera.target = _boxers[1 - player]
	_camera.snap()


func _debug_text() -> String:
	var lines := PackedStringArray([
		"tick %d   fps %d   hash %08x" % [state.tick, Engine.get_frames_per_second(), state.state_hash()],
	])
	for i in 2:
		var f := state.fighters[i]
		lines.append("P%d  HP %4d  ST %4d%s  %-9s %-8s f%-3d stun %-3d knock %d" % [
			i + 1, f.health, f.stamina, "x" if f.exhausted else " ", ACTION_NAMES[f.action],
			MOVE_NAMES[f.move], f.frame, f.stun, f.knock_meter])
	if OS.has_feature("mobile"):
		return "\n".join(lines)
	lines.append("")
	lines.append("P1  W jab  Q/E hooks  S uppercut  A/D dodge  Space block   (pad 1: X, LB/RB, Y, d-pad/stick, B/RT)")
	lines.append("P2  I jab  U/O hooks  K uppercut  J/L dodge  P block       (pad 2: same)")
	lines.append("C swap camera   R restart   T touch overlay (mouse drags act as touches)   F3 hide this")
	return "\n".join(lines)
