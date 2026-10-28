extends GutTest
## One-shot presentation events fire exactly once, even when the same moment is shown again
## (a rollback re-simulating it).

var moves: MoveSet = preload("res://sim/moves.tres")


func fight() -> MatchState:
	var s := MatchState.create(moves)
	s.phase = MatchState.Phase.FIGHT
	return s


func kinds(events: Array[MatchEvents.Event]) -> Array:
	return events.map(func(e: MatchEvents.Event) -> int: return e.kind)


func test_hit_fires_once() -> void:
	var s := fight()
	var events := MatchEvents.new()
	var seen := []
	for t in moves.jab.startup + 10:
		Sim.step(s, InputBits.JAB if t == 0 else 0, 0, moves)
		seen.append_array(kinds(events.collect(s, moves)))
	assert_eq(seen.count(MatchEvents.Kind.PUNCH), 1)
	assert_eq(seen.count(MatchEvents.Kind.HIT), 1)


func test_rollback_replay_does_not_repeat() -> void:
	var s := fight()
	var events := MatchEvents.new()
	var snapshot := PackedInt64Array()
	var count := 0
	for t in moves.jab.startup + 4:
		if t == 2:
			snapshot = s.pack()
		Sim.step(s, InputBits.JAB if t == 0 else 0, 0, moves)
		count += kinds(events.collect(s, moves)).count(MatchEvents.Kind.HIT)
	# Roll back and resimulate the same inputs: the hit is shown again but must not re-fire.
	s.unpack(snapshot)
	for t in range(2, moves.jab.startup + 4):
		Sim.step(s, 0, 0, moves)
		count += kinds(events.collect(s, moves)).count(MatchEvents.Kind.HIT)
	assert_eq(count, 1)


func test_new_match_fires_again_after_reset() -> void:
	var events := MatchEvents.new()
	for round in 2:
		events.reset()  # what LocalMatch / OnlineMatch do when a new match starts
		var s := fight()
		var hits := 0
		for t in moves.jab.startup + 4:
			Sim.step(s, InputBits.JAB if t == 0 else 0, 0, moves)
			hits += kinds(events.collect(s, moves)).count(MatchEvents.Kind.HIT)
		assert_eq(hits, 1, "match %d" % round)


func test_round_bell_fires_once_per_round() -> void:
	var s := MatchState.create(moves)
	var events := MatchEvents.new()
	var bells := 0
	for t in moves.intro_ticks + 30:
		Sim.step(s, 0, 0, moves)
		bells += kinds(events.collect(s, moves)).count(MatchEvents.Kind.ROUND_START)
	assert_eq(bells, 1)
