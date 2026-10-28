extends LocalMatch
## Training mode: you (P1) against a configurable dummy, with frame data on screen.
## No round clock or intro; health refills after each exchange; optional infinite stamina,
## ¼-speed slow motion, pause and frame step; moves.tres reloads by itself when you save it, so
## you can tune numbers in any text editor (or the Godot inspector) while you play.

const MOVES_PATH := "res://sim/moves.tres"
## Refill health once both fighters have been idle this long.
const REFILL_AFTER_TICKS := 60
const SLOW_SCALE := 0.25

var dummy: DummySource
var refill_health := true
var infinite_stamina := false

var analyzers: Array[FrameAnalyzer] = [FrameAnalyzer.new(0), FrameAnalyzer.new(1)]
var _quiet_ticks := 0
var _moves_mtime := 0
var _mtime_check := 0.0

@onready var _panel: TrainingPanel = $TrainingPanel


func _ready() -> void:
	super()
	_moves_mtime = FileAccess.get_modified_time(MOVES_PATH)
	_panel.training = self
	_view.hud.names[1] = "DUMMY"


func _new_state() -> MatchState:
	var s := MatchState.create(moves)
	s.phase = MatchState.Phase.FIGHT
	return s


func _setup_players() -> void:
	_set_control(0, -1)
	dummy = DummySource.new(1, moves)
	_players[1] = [dummy]
	_ai_levels[1] = -1


func _control_name(player: int) -> String:
	return "you" if player == 0 else "dummy: " + DummySource.MODE_NAMES[dummy.mode]


func set_dummy_mode(mode: DummySource.Mode) -> void:
	dummy.mode = mode


func set_slow_motion(on: bool) -> void:
	time_scale = SLOW_SCALE if on else 1.0


func reload_moves() -> void:
	var fresh := ResourceLoader.load(MOVES_PATH, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as MoveSet
	if fresh == null:
		push_warning("Couldn't reload %s (syntax error?)" % MOVES_PATH)
		return
	moves = fresh
	_view.moves = fresh
	var mode := dummy.mode
	_setup_players()
	dummy.mode = mode
	_panel.refresh_table()
	print("Reloaded ", MOVES_PATH)


func _process(delta: float) -> void:
	_mtime_check += delta
	if _mtime_check >= 1.0:
		_mtime_check = 0.0
		var mtime := FileAccess.get_modified_time(MOVES_PATH)
		if mtime != 0 and mtime != _moves_mtime:
			_moves_mtime = mtime
			reload_moves()
	super(delta)


func _after_step() -> void:
	state.round_timer = moves.round_ticks
	if state.phase != MatchState.Phase.FIGHT:
		var keep := state.tick
		state.start_round(moves)
		state.phase = MatchState.Phase.FIGHT
		state.tick = keep
	for f in state.fighters:
		if infinite_stamina:
			f.stamina = moves.max_stamina
			f.exhausted = 0
	var quiet := true
	for f in state.fighters:
		if f.action != FighterState.IDLE and f.action != FighterState.BLOCK:
			quiet = false
	_quiet_ticks = _quiet_ticks + 1 if quiet else 0
	if refill_health and _quiet_ticks == REFILL_AFTER_TICKS:
		for f in state.fighters:
			f.health = moves.max_health
			f.knock_meter = 0
			f.knockdowns = 0
	for analyzer in analyzers:
		analyzer.observe(state, moves)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_F5:
				_panel.toggle_slow()
				return
			KEY_F6:
				_panel.toggle_pause()
				return
			KEY_F7:
				step_once()
				return
			KEY_F9:
				reload_moves()
				return
			KEY_1, KEY_2:
				return  # no AI switching in training
	super(event)
