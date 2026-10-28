extends GutTest
## Records a long pseudo-random input log, replays it, and compares state hashes tick by tick.
## Also checks that restoring a snapshot and resimulating (what rollback does) gives the same result.

const TICKS := 60 * 60 * 5  # five minutes of play
const SEED := 20261028

var moves: MoveSet = preload("res://sim/moves.tres")


## Deterministic input log from a 32-bit LCG: presses and holds for both players.
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
			held[p] = 1 << ((x >> 16) % 7)  # press or start holding one button
		elif roll < 30:
			held[p] = 0
		inputs[i] = held[p]
	return inputs


static func replay(inputs: PackedInt64Array, moves: MoveSet) -> PackedInt64Array:
	var s := MatchState.create(moves)
	var hashes := PackedInt64Array()
	hashes.resize(inputs.size() / 2)
	for t in hashes.size():
		s = _rematch_if_over(s, moves)
		Sim.step(s, inputs[t * 2], inputs[t * 2 + 1], moves)
		hashes[t] = s.state_hash()
	return hashes


## Keeps long logs exercising combat: a finished match is replaced by a fresh one.
static func _rematch_if_over(s: MatchState, moves: MoveSet) -> MatchState:
	return MatchState.create(moves) if s.phase == MatchState.Phase.MATCH_OVER else s


func test_replay_is_identical() -> void:
	var inputs := make_log(TICKS, SEED)
	var first := replay(inputs, moves)
	var second := replay(inputs, moves)
	assert_eq(first.size(), TICKS)
	for t in TICKS:
		if first[t] != second[t]:
			fail_test("hash diverged at tick %d" % t)
			return
	pass_test("%d ticks, final hash %08x" % [TICKS, first[-1]])


func test_log_actually_fights() -> void:
	# Guard against a log that never does anything, which would make the replay test meaningless.
	var inputs := make_log(TICKS, SEED)
	var s := MatchState.create(moves)
	var hits := 0
	var last_health := [moves.max_health, moves.max_health]
	for t in TICKS:
		if s.phase == MatchState.Phase.MATCH_OVER:
			s = MatchState.create(moves)
			last_health = [moves.max_health, moves.max_health]
		Sim.step(s, inputs[t * 2], inputs[t * 2 + 1], moves)
		for i in 2:
			if s.fighters[i].health < last_health[i]:
				hits += 1
			last_health[i] = s.fighters[i].health
	assert_gt(hits, 50, "input log should produce plenty of hits")


func test_rollback_resimulation_matches() -> void:
	var inputs := make_log(3000, SEED + 1)
	var s := MatchState.create(moves)
	var snapshot := PackedInt64Array()
	for t in 3000:
		if t == 2900:
			snapshot = s.pack()
		Sim.step(s, inputs[t * 2], inputs[t * 2 + 1], moves)
	var expected := s.state_hash()

	var resim := MatchState.new()
	resim.unpack(snapshot)
	for t in range(2900, 3000):
		Sim.step(resim, inputs[t * 2], inputs[t * 2 + 1], moves)
	assert_eq(resim.state_hash(), expected)
	assert_eq(resim.pack(), s.pack())


func test_sim_state_is_integers_only() -> void:
	for script: Script in [FighterState, MatchState]:
		for prop in script.get_script_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			assert_true(prop.type == TYPE_INT or prop.name == "fighters",
				"%s.%s must be an int" % [script.resource_path.get_file(), prop.name])
