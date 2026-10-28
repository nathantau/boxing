extends GutTest
## Frame data -> animation time mapping for the Mixamo rig.

var moves: MoveSet = preload("res://sim/moves.tres")
var timings := ClipTimings.new()
var lengths := {
	"idle": 2.0, "jab": 0.8, "hook_l": 1.0, "hook_r": 1.0, "uppercut": 1.2, "block": 0.6,
	"dodge_l": 0.9, "dodge_r": 0.9, "hit": 0.7, "knockdown": 2.5, "get_up": 2.0,
}


func attacking(move: int, frame: int) -> FighterState:
	var f := FighterState.new()
	f.action = FighterState.ATTACK
	f.move = move
	f.frame = frame
	return f


func test_jab_impact_lands_on_first_active_frame() -> void:
	var jab := moves.jab
	var at_startup_end := AnimationPicker.pick(attacking(MoveSet.JAB, jab.startup - 1), 0, moves, lengths, timings)
	assert_eq(at_startup_end[0], "jab")
	assert_almost_eq(at_startup_end[1], timings.jab_impact, 0.0001, "windup finishes on the last startup frame")
	var active := AnimationPicker.pick(attacking(MoveSet.JAB, jab.startup + 1), 0, moves, lengths, timings)
	assert_almost_eq(active[1], timings.jab_impact, 0.0001, "held at impact while active")


func test_recovery_plays_to_the_end() -> void:
	var hook := moves.hook_l
	var last := AnimationPicker.pick(attacking(MoveSet.HOOK_L, hook.total() - 1), 0, moves, lengths, timings)
	assert_eq(last[0], "hook_l")
	assert_almost_eq(last[1], lengths.hook_l, 0.0001)


func test_exhausted_slowdown_stretches_windup() -> void:
	var f := attacking(MoveSet.JAB, moves.jab.startup - 1)
	f.slow = moves.exhausted_slow
	var t: float = AnimationPicker.pick(f, 0, moves, lengths, timings)[1]
	assert_lt(t, timings.jab_impact, "slowed jab hasn't reached impact yet")


func test_idle_loops_on_the_match_clock() -> void:
	var f := FighterState.new()
	var t: float = AnimationPicker.pick(f, 150, moves, lengths, timings)[1]
	assert_almost_eq(t, fmod(150 / 60.0, 2.0), 0.0001)


func test_hit_reaction_spans_the_hitstun() -> void:
	var f := FighterState.new()
	f.action = FighterState.HITSTUN
	f.frame = 5
	f.stun = 5
	var pick := AnimationPicker.pick(f, 0, moves, lengths, timings)
	assert_eq(pick[0], "hit")
	assert_almost_eq(pick[1], lengths.hit * 0.5, 0.0001)


func test_missing_clips_fall_back() -> void:
	var f := FighterState.new()
	f.action = FighterState.STAGGER
	f.stun = 10
	assert_eq(AnimationPicker.pick(f, 0, moves, lengths, timings)[0], "hit", "no stagger clip -> hit")
	f.action = FighterState.KO
	assert_eq(AnimationPicker.pick(f, 0, moves, lengths, timings)[0], "knockdown", "no ko clip -> knockdown")
	f.action = FighterState.IDLE
	f.exhausted = 1
	assert_eq(AnimationPicker.pick(f, 0, moves, lengths, timings)[0], "idle", "no tired clip -> idle")


func test_knockdown_gets_up_at_the_end() -> void:
	var f := FighterState.new()
	f.action = FighterState.KNOCKDOWN
	f.frame = 10
	f.stun = moves.knockdown_ticks - 10
	assert_eq(AnimationPicker.pick(f, 0, moves, lengths, timings)[0], "knockdown")
	f.stun = timings.get_up_ticks / 2
	var pick := AnimationPicker.pick(f, 0, moves, lengths, timings)
	assert_eq(pick[0], "get_up")
	assert_almost_eq(pick[1], lengths.get_up * 0.5, 0.02)
