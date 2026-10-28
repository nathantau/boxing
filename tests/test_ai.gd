extends GutTest
## AI opponent: deterministic for a given seed, finishes matches, and harder levels defend better.

var moves: MoveSet = preload("res://sim/moves.tres")


## Throws a punch every `interval` ticks, cycling through the punches. Never defends.
class PunchBot:
	extends InputSource
	const PUNCHES := [InputBits.JAB, InputBits.HOOK_L, InputBits.HOOK_R, InputBits.UPPERCUT]
	var interval := 70
	var _count := 0

	func observe(s: MatchState) -> void:
		if s.phase == MatchState.Phase.FIGHT and s.tick % interval == 0:
			press(PUNCHES[_count % PUNCHES.size()])
			_count += 1


func play(a: InputSource, b: InputSource, ticks: int, s := MatchState.create(moves)) -> MatchState:
	for t in ticks:
		if s.phase == MatchState.Phase.MATCH_OVER:
			break
		a.observe(s)
		b.observe(s)
		Sim.step(s, a.consume(), b.consume(), moves)
	return s


func test_ai_vs_ai_is_deterministic() -> void:
	var first := play(AISource.new(0, moves, AISource.Level.HARD, 1), AISource.new(1, moves, AISource.Level.NORMAL, 2), 60 * 60 * 3)
	var second := play(AISource.new(0, moves, AISource.Level.HARD, 1), AISource.new(1, moves, AISource.Level.NORMAL, 2), 60 * 60 * 3)
	assert_eq(first.state_hash(), second.state_hash())
	assert_true(first.round_number > 1 or first.phase == MatchState.Phase.MATCH_OVER, "rounds were decided")


func test_ai_match_finishes() -> void:
	var s := play(AISource.new(0, moves, AISource.Level.HARD, 3), AISource.new(1, moves, AISource.Level.EASY, 4), 60 * 60 * 6)
	assert_eq(s.phase, MatchState.Phase.MATCH_OVER)
	assert_eq(s.match_winner, 0, "hard beats easy")


## Damage the defender takes from PunchBot over a fixed time, with the defender's AI only defending.
func damage_taken(defender: InputSource) -> int:
	var s := MatchState.create(moves)
	s.phase = MatchState.Phase.FIGHT
	s.round_timer = 1_000_000
	var bot := PunchBot.new()
	var taken := 0
	var last := moves.max_health
	for t in 60 * 40:
		bot.observe(s)
		defender.observe(s)
		Sim.step(s, bot.consume(), defender.consume(), moves)
		var f := s.fighters[1]
		taken += maxi(0, last - f.health)
		last = f.health
		if s.phase != MatchState.Phase.FIGHT:
			s.start_round(moves)
			s.phase = MatchState.Phase.FIGHT
			last = moves.max_health
	return taken


func _defender(level: AISource.Level) -> AISource:
	var ai := AISource.new(1, moves, level, 7)
	ai._profile = ai._profile.duplicate()
	ai._profile.aggression = 0.0
	ai._profile.punish = 0.0
	return ai


func test_harder_ai_defends_better() -> void:
	var dummy := damage_taken(InputSource.new())
	var easy := damage_taken(_defender(AISource.Level.EASY))
	var hard := damage_taken(_defender(AISource.Level.HARD))
	gut.p("damage taken in 40 s: dummy %d, easy %d, hard %d" % [dummy, easy, hard])
	assert_gt(dummy, 0)
	assert_lt(easy, dummy)
	assert_lt(hard, easy)
	assert_lt(hard * 2, dummy, "hard AI stops at least half the damage")
