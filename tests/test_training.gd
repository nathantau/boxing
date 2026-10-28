extends GutTest
## Training mode tools: measured frame advantage must agree with the table formula, results are
## labelled correctly, and the dummy's "perfect" defenses really are perfect.

var moves: MoveSet = preload("res://sim/moves.tres")
const PUNCHES := [MoveSet.JAB, MoveSet.HOOK_L, MoveSet.HOOK_R, MoveSet.UPPERCUT]
const BITS := { MoveSet.JAB: InputBits.JAB, MoveSet.HOOK_L: InputBits.HOOK_L, MoveSet.HOOK_R: InputBits.HOOK_R, MoveSet.UPPERCUT: InputBits.UPPERCUT }


func fight() -> MatchState:
	var s := MatchState.create(moves)
	s.phase = MatchState.Phase.FIGHT
	return s


## P1 throws `move` once; P2 holds `b_hold`. Returns the analyzer's finished record.
func exchange(move: int, b_hold := 0, b_source: InputSource = null) -> Dictionary:
	var s := fight()
	var analyzer := FrameAnalyzer.new(0)
	for t in 120:
		var b := b_hold
		if b_source != null:
			b_source.observe(s)
			b = b_source.consume()
		Sim.step(s, BITS[move] if t == 0 else 0, b, moves)
		analyzer.observe(s, moves)
	return analyzer.last


func test_measured_advantage_on_hit_matches_table() -> void:
	for move: int in PUNCHES:
		var r := exchange(move)
		assert_eq(r.result, "hit")
		assert_eq(r.advantage, moves.get_move(move).advantage_on_hit(), "%s on hit" % move)
		assert_eq(r.damage, moves.get_move(move).damage)


func test_measured_advantage_on_block_matches_table() -> void:
	for move: int in PUNCHES:
		var r := exchange(move, InputBits.BLOCK)
		assert_eq(r.result, "blocked")
		assert_eq(r.advantage, moves.get_move(move).advantage_on_block(), "%s on block" % move)


func test_perfect_dodge_dummy_dodges_everything() -> void:
	for move: int in PUNCHES:
		var dummy := DummySource.new(1, moves)
		dummy.mode = DummySource.Mode.DODGE
		var r := exchange(move, 0, dummy)
		assert_eq(r.result, "dodged", "move %d" % move)
		assert_eq(r.advantage, null)


func test_perfect_parry_dummy_parries_everything() -> void:
	for move: int in PUNCHES:
		var dummy := DummySource.new(1, moves)
		dummy.mode = DummySource.Mode.PARRY
		assert_eq(exchange(move, 0, dummy).result, "parried", "move %d" % move)


func test_whiff_into_nothing() -> void:
	var s := fight()
	s.fighters[1].action = FighterState.KNOCKDOWN  # invulnerable target
	s.fighters[1].stun = 200
	var analyzer := FrameAnalyzer.new(0)
	for t in 60:
		Sim.step(s, InputBits.JAB if t == 0 else 0, 0, moves)
		analyzer.observe(s, moves)
	assert_eq(analyzer.last.result, "whiff")
