extends Node
## Online 1v1: a RollbackSession advanced on netfox's synchronized 60 Hz tick loop, with inputs
## exchanged every tick through the Net autoload. Always shows the newest (possibly predicted)
## state; since every visual is a function of state, rollbacks correct themselves next frame.
##
## Command line (for testing without the menus), after `--`:
##   --host | --join=ADDRESS   start a session directly
##   --ai[=easy|normal|hard]   let the AI play for this peer
##   --lag=LATENCY,JITTER,LOSS simulated network (ms, ms, %)
##   --input-delay=N           ticks of input delay (default 2)
##   --test-seconds=N          print stats and checkpoint hashes after N seconds, then quit
##   --short-rounds            10 s rounds, first to 1 (both peers must pass it)
##   --auto-rematch            vote for a rematch as soon as a match ends

const MAX_CATCH_UP_TICKS := 4
const DEFAULT_INPUT_DELAY := 2

@export var moves: MoveSet = preload("res://sim/moves.tres")

@onready var _view: MatchView = $MatchView
@onready var _overlay: NetDebugOverlay = $NetDebugOverlay
@onready var _status: Label = $StatusLayer/Status

var session: RollbackSession
var input_delay := DEFAULT_INPUT_DELAY
## Round-trip time measured through our own packets (includes simulated lag), in ms.
var rtt_ms := -1.0

var _source: InputSource
## NetworkTime tick at which sim tick `_base_tick` happens.
var _start_tick := 0
var _base_tick := 0
var _last_desyncs := 0
var _remote_sent_usec := 0
var _remote_sent_at := 0
var _test_until := 0
var _args := {}


func _ready() -> void:
	_parse_args()
	if _args.has("short-rounds"):
		moves = moves.duplicate(true)
		moves.round_ticks = 600
		moves.rounds_to_win = 1
		moves.intro_ticks = 30
		moves.round_over_ticks = 60
	_view.moves = moves
	_source = _make_source()
	_overlay.match = self
	Net.confirmed_state_provider = func() -> PackedInt64Array:
		return session.confirmed_state() if session != null else PackedInt64Array()
	Net.match_ready.connect(_on_match_ready)
	Net.inputs_received.connect(_on_inputs)
	Net.status_changed.connect(_on_status)
	Net.session_ended.connect(_on_session_ended)
	Net.rematch_votes_changed.connect(_on_rematch_votes)
	NetworkTime.on_tick.connect(_on_tick)
	_view.menu_pressed.connect(_leave)
	_view.results.menu_pressed.connect(_leave)
	_view.results.rematch_pressed.connect(_on_rematch_pressed)
	_on_status(Net.status)
	var pending := Net.take_pending_start()
	if not pending.is_empty():
		_on_match_ready(pending[0], pending[1])

	if Net.role == Net.Role.NONE:
		if _args.has("host"):
			Net.host()
		elif _args.has("join"):
			Net.join(_args.join)
	if _args.has("lag"):
		var lag: PackedStringArray = _args.lag.split(",")
		Net.transport.set_lag(lag[0].to_int(), lag[1].to_int() if lag.size() > 1 else 0, lag[2].to_float() if lag.size() > 2 else 0.0)
	if _args.has("test-seconds"):
		_test_until = Time.get_ticks_msec() + int(_args["test-seconds"].to_float() * 1000.0)


func _exit_tree() -> void:
	Net.confirmed_state_provider = Callable()


func _process(_delta: float) -> void:
	_source.sample()
	if session != null:
		_view.show_state(session.state)
		if _args.has("auto-rematch") and session.state.phase == MatchState.Phase.MATCH_OVER and not Net.i_want_rematch():
			_on_rematch_pressed()
	_view.debug_label.text = _debug_text()
	if _test_until > 0 and session != null and Engine.get_process_frames() % 120 == 0:
		print("STAT t=%d sim=%d net=%d depth=%d stalls=%d rollbacks=%d" % [Time.get_ticks_msec(), session.state.tick,
			NetworkTime.tick - _start_tick + _base_tick, session.prediction_depth(), session.stalls, session.rollbacks])
	if _test_until > 0 and Time.get_ticks_msec() >= _test_until:
		_print_test_report()
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		match key.physical_keycode:
			KEY_F3:
				_view.debug_label.visible = not _view.debug_label.visible
			KEY_ESCAPE:
				_leave()


func _on_match_ready(start_tick: int, packed: PackedInt64Array) -> void:
	Net.take_pending_start()
	var state := MatchState.create(moves)
	if not packed.is_empty():
		state.unpack(packed)
	session = RollbackSession.new(state, moves, Net.local_player, input_delay)
	_start_tick = start_tick
	_base_tick = state.tick
	_last_desyncs = 0
	if packed.is_empty():
		_view.fx.reset()  # a fresh match: ticks and rounds start over
	_source = _make_source()
	_view.set_viewer(Net.local_player)
	_view.hud.names[Net.local_player] = "YOU"
	_view.hud.names[1 - Net.local_player] = "OPPONENT"


func _on_tick(_delta: float, tick: int) -> void:
	if session == null or not Net.in_match:
		return
	var target := _base_tick + (tick - _start_tick) + 1
	var steps := 0
	while session.state.tick < target and steps < MAX_CATCH_UP_TICKS:
		if session.prediction_depth() >= RollbackSession.MAX_PREDICTION:
			session.stalls += 1
			break
		_source.observe(session.state)
		session.advance(_source.consume())
		steps += 1
	_send()
	if session.desyncs > _last_desyncs:
		_last_desyncs = session.desyncs
		push_warning("Desync detected at checkpoint %s; resyncing from the host's state." % [session.latest_hash()[0]])
		Net.request_resync()


func _send() -> void:
	var out := session.outgoing()
	var h := session.latest_hash()
	var now := Time.get_ticks_usec()
	Net.send_inputs(out[0], out[1], out[2], h[0], h[1], now, _remote_sent_usec, now - _remote_sent_at if _remote_sent_at > 0 else 0)


func _on_inputs(first_tick: int, bits: PackedByteArray, ack: int, hash_tick: int, hash: int, sent_usec: int, echo_usec: int, hold_usec: int) -> void:
	if session == null:
		return
	session.receive(first_tick, bits, ack)
	session.check_remote_hash(hash_tick, hash)
	var now := Time.get_ticks_usec()
	_remote_sent_usec = sent_usec
	_remote_sent_at = now
	if echo_usec > 0:
		var sample := (now - echo_usec - hold_usec) / 1000.0
		rtt_ms = sample if rtt_ms < 0.0 else lerpf(rtt_ms, sample, 0.1)


func _on_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _on_session_ended(reason: String) -> void:
	session = null
	if _test_until > 0:
		print("SESSION ENDED: ", reason)
		get_tree().quit(1)
		return
	Game.goto(Game.MENU)


func _leave() -> void:
	if Net.role == Net.Role.NONE:
		Game.goto(Game.MENU)
	else:
		Net.leave()  # session_ended takes us to the menu


func _on_rematch_pressed() -> void:
	Net.vote_rematch()
	_view.results.set_status("Waiting for your opponent…", true)


func _on_rematch_votes() -> void:
	if Net.opponent_wants_rematch() and not Net.i_want_rematch():
		_view.results.set_status("Your opponent wants a rematch!")


func _make_source() -> InputSource:
	if _args.has("ai"):
		var level := AISource.Level.HARD
		var names: Array = AISource.LEVEL_NAMES
		if names.has(_args.ai):
			level = names.find(_args.ai) as AISource.Level
		return AISource.new(Net.local_player, moves, level, Time.get_ticks_usec())
	var sources: Array[InputSource] = [LocalInputSource.new(LocalInputSource.P1_KEYS, 0), _view.touch.source]
	return MergedSource.new(sources)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if _args.has("input-delay"):
		input_delay = _args["input-delay"].to_int()


func _debug_text() -> String:
	if session == null:
		return "fps %d" % Engine.get_frames_per_second()
	var s := session.state
	var lines := PackedStringArray([
		"tick %d   fps %d   ping %s   rollbacks %d (last %d)   stalls %d   desyncs %d" % [
			s.tick, Engine.get_frames_per_second(), "%d ms" % rtt_ms if rtt_ms >= 0.0 else "-",
			session.rollbacks, session.last_rollback_depth, session.stalls, session.desyncs],
	])
	lines.append_array(_view.fighter_debug_lines(s, ["you" if Net.local_player == 0 else "opponent", "you" if Net.local_player == 1 else "opponent"]))
	if not OS.has_feature("mobile"):
		lines.append("F2 network overlay   F3 hide this   Esc leave")
	return "\n".join(lines)


func _print_test_report() -> void:
	if session == null:
		print("RESULT no-session")
		return
	var hashes := PackedStringArray()
	var ticks: Array = session._hashes.keys()
	ticks.sort()
	for t: int in ticks:
		hashes.append("%d:%08x" % [t, session._hashes[t]])
	print("RESULT role=%s tick=%d rollbacks=%d stalls=%d desyncs=%d rtt=%.1f epoch=%d" % [
		"host" if Net.role == Net.Role.HOST else "client", session.state.tick, session.rollbacks,
		session.stalls, session.desyncs, rtt_ms, Net.epoch])
	print("HASHES ", " ".join(hashes))
