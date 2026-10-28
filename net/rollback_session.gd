class_name RollbackSession
## Symmetric rollback for two peers running the same deterministic Sim (GGPO-style).
##
## Local input is scheduled `input_delay` ticks ahead. The remote player's input is predicted
## (their last known input repeats) until the real one arrives; if it differs from the
## prediction, the session restores the snapshot from that tick and resimulates to the present.
## Both peers hash confirmed states every HASH_INTERVAL ticks so a desync is caught early.
##
## No networking in here: OnlineMatch feeds it inputs and sends what it hands back, which keeps
## the whole thing testable offline with two sessions wired together.

## Never predict further ahead than this; stall and wait for input instead.
const MAX_PREDICTION := 12
## Never send more than this many inputs in one packet.
const MAX_INPUTS_PER_PACKET := 32
const HASH_INTERVAL := 60
const KEEP_HASHES := 16

var state: MatchState
var moves: MoveSet
var local_player: int
var input_delay: int

## Counters for the debug overlay.
var rollbacks := 0
var rollback_ticks := 0
var last_rollback_depth := 0
var stalls := 0
var desyncs := 0

## player -> {tick: input bits}
var _inputs: Array[Dictionary] = [{}, {}]
## tick -> the remote input actually used when that tick was simulated
var _used_remote := {}
## tick -> packed state *before* that tick was simulated (i.e. the state whose .tick == tick)
var _snapshots := {}
## Highest tick for which we have every input from that player.
var _last_input: PackedInt64Array = [-1, -1]
## Earliest tick that must be resimulated, or -1.
var _rollback_from := -1
## Highest tick of OUR inputs the remote has confirmed receiving.
var _remote_ack := -1
## Confirmed-state hashes: tick -> hash, ours and theirs.
var _hashes := {}
var _remote_hashes := {}
var _last_hashed := -1


func _init(start: MatchState, move_set: MoveSet, local: int, delay: int) -> void:
	state = start
	moves = move_set
	local_player = local
	input_delay = delay
	# Nobody has input for the first `delay` ticks; they are empty for both players.
	for p in 2:
		for t in range(start.tick, start.tick + delay):
			_inputs[p][t] = 0
		_last_input[p] = start.tick + delay - 1
	_remote_ack = start.tick + delay - 1
	_last_hashed = start.tick


var remote_player: int:
	get:
		return 1 - local_player


## Ticks we are currently simulating ahead of the remote player's known input.
func prediction_depth() -> int:
	return state.tick - 1 - _last_input[remote_player]


## Rolls back if needed, then simulates one tick with `local_bits` as our newest input.
## Returns false (and does nothing else) if we'd have to predict too far ahead.
func advance(local_bits: int) -> bool:
	_apply_rollback()
	_collect_hashes()
	if prediction_depth() >= MAX_PREDICTION:
		stalls += 1
		return false
	_last_input[local_player] += 1
	_inputs[local_player][_last_input[local_player]] = local_bits
	_step()
	_trim()
	return true


## Inputs from the remote peer: `bits[i]` is their input for tick `first_tick + i`.
## `ack` is the highest tick of our inputs they have.
func receive(first_tick: int, bits: PackedByteArray, ack: int) -> void:
	_remote_ack = maxi(_remote_ack, ack)
	var remote := remote_player
	for i in bits.size():
		var t := first_tick + i
		if t <= _last_input[remote] or _inputs[remote].has(t):
			continue
		_inputs[remote][t] = bits[i]
		if t < state.tick and _used_remote.get(t, -1) != bits[i]:
			_rollback_from = t if _rollback_from < 0 else mini(_rollback_from, t)
	while _inputs[remote].has(_last_input[remote] + 1):
		_last_input[remote] += 1


## What to send the remote peer now: our inputs they haven't acknowledged.
## Returns [first_tick, bits, ack].
func outgoing() -> Array:
	var first := _remote_ack + 1
	var last := mini(_last_input[local_player], first + MAX_INPUTS_PER_PACKET - 1)
	var bits := PackedByteArray()
	for t in range(first, last + 1):
		bits.append(_inputs[local_player][t])
	return [first, bits, _last_input[remote_player]]


## Our newest confirmed hash as [tick, hash], or [-1, 0] if none yet.
func latest_hash() -> Array:
	if _hashes.is_empty():
		return [-1, 0]
	var t: int = _hashes.keys().max()
	return [t, _hashes[t]]


## A confirmed hash from the remote peer. Returns false if it disagrees with ours.
func check_remote_hash(tick: int, value: int) -> bool:
	if tick < 0:
		return true
	_remote_hashes[tick] = value
	if _hashes.has(tick) and _hashes[tick] != value:
		desyncs += 1
		return false
	return true


## The newest state both peers agree on (every input before it is known), packed.
## Used to resume after a reconnect.
func confirmed_state() -> PackedInt64Array:
	var t := mini(_last_input[remote_player] + 1, state.tick)
	if _rollback_from >= 0:
		t = mini(t, _rollback_from)
	return state.pack() if t == state.tick else _snapshots[t]


func _remote_input(t: int) -> int:
	var remote := remote_player
	if _inputs[remote].has(t):
		return _inputs[remote][t]
	return _inputs[remote].get(_last_input[remote], 0)


func _step() -> void:
	var t := state.tick
	_snapshots[t] = state.pack()
	var remote_bits := _remote_input(t)
	_used_remote[t] = remote_bits
	var local_bits: int = _inputs[local_player][t]
	if local_player == 0:
		Sim.step(state, local_bits, remote_bits, moves)
	else:
		Sim.step(state, remote_bits, local_bits, moves)


func _apply_rollback() -> void:
	if _rollback_from < 0:
		return
	var target := state.tick
	state.unpack(_snapshots[_rollback_from])
	last_rollback_depth = target - _rollback_from
	rollback_ticks += last_rollback_depth
	rollbacks += 1
	_rollback_from = -1
	while state.tick < target:
		_step()


## Hash states that can no longer change, every HASH_INTERVAL ticks.
func _collect_hashes() -> void:
	var confirmed := mini(_last_input[remote_player] + 1, state.tick)
	var next := _last_hashed - posmod(_last_hashed, HASH_INTERVAL) + HASH_INTERVAL
	while next <= confirmed:
		var data: PackedInt64Array = state.pack() if next == state.tick else _snapshots.get(next, PackedInt64Array())
		if not data.is_empty():
			_hashes[next] = MatchState.hash_packed(data)
			if _remote_hashes.has(next) and _remote_hashes[next] != _hashes[next]:
				desyncs += 1
		_last_hashed = next
		next += HASH_INTERVAL


## Forget history that can never be rolled back to again.
func _trim() -> void:
	var keep_from := mini(_last_input[remote_player], _last_hashed) - 1
	for dict: Dictionary in [_snapshots, _used_remote, _inputs[remote_player]]:
		for t: int in dict.keys():
			if t < keep_from:
				dict.erase(t)
	var keep_local_from := mini(_remote_ack, keep_from)
	for t: int in _inputs[local_player].keys():
		if t < keep_local_from:
			_inputs[local_player].erase(t)
	for dict: Dictionary in [_hashes, _remote_hashes]:
		while dict.size() > KEEP_HASHES:
			dict.erase(dict.keys().min())
