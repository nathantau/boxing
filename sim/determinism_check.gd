class_name DeterminismCheck
## Replays a fixed five-minute pseudo-random input log through the sim and returns the final
## state hash. Every device running the same build (same moves.tres) must print the same hash;
## if an iPhone and a Mac disagree, online play between them would desync.
##
## In game: main menu > Check determinism. On a desktop: godot --headless -- --determinism-check

const TICKS := 60 * 60 * 5
const SEED := 20261028


## Deterministic input log from a 32-bit LCG: presses and holds for both players.
## inputs[t * 2] is player A's input for tick t, inputs[t * 2 + 1] player B's.
static func make_log(ticks: int, rng_seed: int) -> PackedInt64Array:
	var inputs := PackedInt64Array()
	inputs.resize(ticks * 2)
	var x := rng_seed
	var held := [0, 0]
	for i in ticks * 2:
		x = (x * 1664525 + 1013904223) & 0xFFFFFFFF
		var p := i % 2
		var roll := (x >> 8) % 100
		if roll < 6:
			held[p] = 1 << ((x >> 16) % 8)  # press or start holding one button
		elif roll < 30:
			held[p] = 0
		inputs[i] = held[p]
	return inputs


## Runs the log (starting a fresh match whenever one ends) and hashes the state every tick.
static func replay(inputs: PackedInt64Array, moves: MoveSet) -> PackedInt64Array:
	var s := MatchState.create(moves)
	var hashes := PackedInt64Array()
	hashes.resize(inputs.size() / 2)
	for t in hashes.size():
		if s.phase == MatchState.Phase.MATCH_OVER:
			s = MatchState.create(moves)
		Sim.step(s, inputs[t * 2], inputs[t * 2 + 1], moves)
		hashes[t] = s.state_hash()
	return hashes


## {"hash": final state hash, "rules": moves.tres fingerprint, "ticks": TICKS, "msec": time taken}
static func run(moves: MoveSet) -> Dictionary:
	var started := Time.get_ticks_msec()
	var hashes := replay(make_log(TICKS, SEED), moves)
	return { "hash": hashes[-1], "rules": fingerprint(moves), "ticks": TICKS, "msec": Time.get_ticks_msec() - started }


static func describe(result: Dictionary) -> String:
	return "%d ticks → %08x   (rules %08x, %.1f s)" % [result.ticks, result.hash, result.rules, result.msec / 1000.0]


## Hash of every number in moves.tres, so two devices can tell they're running the same rules.
static func fingerprint(moves: MoveSet) -> int:
	var values := PackedInt64Array()
	_append_ints(moves, values)
	for move in [MoveSet.JAB, MoveSet.CROSS, MoveSet.HOOK_L, MoveSet.HOOK_R, MoveSet.UPPERCUT, MoveSet.DODGE_L, MoveSet.DODGE_R]:
		_append_ints(moves.get_move(move), values)
	return MatchState.hash_packed(values)


static func _append_ints(res: Resource, out: PackedInt64Array) -> void:
	for prop in res.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.type == TYPE_INT:
			out.append(res.get(prop.name))
