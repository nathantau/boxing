extends GutTest
## Rules of the combat sim. Timings are derived from moves.tres, so these keep passing when you retune numbers.

var moves: MoveSet = preload("res://sim/moves.tres")
var s: MatchState
var a: FighterState
var b: FighterState


func before_each() -> void:
	s = MatchState.create(moves)
	a = s.fighters[0]
	b = s.fighters[1]


## Runs `ticks` steps. Each input is held for one tick on the given tick offset (0 = the first step).
func run(ticks: int, a_presses := {}, b_presses := {}, a_hold := 0, b_hold := 0) -> void:
	for t in ticks:
		Sim.step(s, a_hold | a_presses.get(t, 0), b_hold | b_presses.get(t, 0), moves)


func test_jab_lands_on_first_active_frame() -> void:
	var jab := moves.jab
	run(jab.startup, {0: InputBits.JAB})
	assert_eq(b.health, moves.max_health, "no damage during startup")
	run(1)
	assert_eq(b.health, moves.max_health - jab.damage)
	assert_eq(b.action, FighterState.HITSTUN)
	assert_eq(b.stun, jab.hitstun)


func test_attack_connects_only_once() -> void:
	run(moves.jab.total(), {0: InputBits.JAB})
	assert_eq(b.health, moves.max_health - moves.jab.damage)


func test_block_takes_chip_and_blockstun() -> void:
	run(moves.jab.startup + 1, {0: InputBits.JAB}, {}, 0, InputBits.BLOCK)
	assert_eq(b.health, moves.max_health - moves.jab.chip_damage)
	assert_eq(b.action, FighterState.BLOCKSTUN)


func test_block_has_startup() -> void:
	# Block pressed one tick too late: the jab's first active frame lands inside block startup.
	var late := moves.jab.startup - moves.block_startup + 1
	for t in moves.jab.startup + 1:
		var b_in := InputBits.BLOCK if t >= late else 0
		Sim.step(s, InputBits.JAB if t == 0 else 0, b_in, moves)
	assert_eq(b.health, moves.max_health - moves.jab.damage, "block that is still starting up does not protect")


func _dodge_test(hook_move: int, dodge_bit: int) -> void:
	var hook := moves.get_move(hook_move)
	var dodge := moves.get_move(MoveSet.DODGE_L if dodge_bit == InputBits.DODGE_L else MoveSet.DODGE_R)
	assert_true(dodge.active >= hook.active, "test assumes the dodge outlasts the hook's active frames")
	var hook_bit := InputBits.HOOK_L if hook_move == MoveSet.HOOK_L else InputBits.HOOK_R
	# Dodge so its invulnerability starts on the hook's first active frame.
	run(hook.total(), {0: hook_bit}, {hook.startup - dodge.startup: dodge_bit})


func test_correct_dodge_avoids_hook() -> void:
	for hook_move: int in [MoveSet.HOOK_L, MoveSet.HOOK_R]:
		before_each()
		var side := InputBits.DODGE_L if moves.get_move(hook_move).dodged_by & InputBits.DODGE_L else InputBits.DODGE_R
		_dodge_test(hook_move, side)
		assert_eq(b.health, moves.max_health, "hook %d should be dodged" % hook_move)


func test_wrong_dodge_gets_hit() -> void:
	for hook_move: int in [MoveSet.HOOK_L, MoveSet.HOOK_R]:
		before_each()
		var dodged_by := moves.get_move(hook_move).dodged_by
		var wrong := InputBits.DODGE_R if dodged_by & InputBits.DODGE_L else InputBits.DODGE_L
		if dodged_by & wrong:
			continue  # This hook can be dodged both ways; nothing to test.
		_dodge_test(hook_move, wrong)
		assert_eq(b.health, moves.max_health - moves.get_move(hook_move).damage)


func test_uppercut_punishes_dodge_recovery() -> void:
	var up := moves.uppercut
	var dodge := moves.dodge_l
	# B dodges first; A times the uppercut so its first active frame is B's first recovery frame.
	var a_press := dodge.startup + dodge.active - up.startup
	assert_true(a_press >= 0, "uppercut startup is longer than the dodge; rework this test's timing")
	assert_true(dodge.recovery > 0)
	run(a_press + up.startup + 1, {a_press: InputBits.UPPERCUT}, {0: InputBits.DODGE_L})
	assert_eq(b.health, moves.max_health - up.damage - up.dodge_punish_damage)


func test_hit_interrupts_startup() -> void:
	# B starts a hook; A's jab lands during the hook's startup and cancels it.
	assert_true(moves.jab.startup < moves.hook_l.startup)
	run(moves.hook_l.total(), {0: InputBits.JAB}, {0: InputBits.HOOK_L})
	assert_eq(a.health, moves.max_health, "B's hook never lands")
	assert_eq(b.health, moves.max_health - moves.jab.damage)


func test_simultaneous_jabs_trade() -> void:
	run(moves.jab.startup + 1, {0: InputBits.JAB}, {0: InputBits.JAB})
	assert_eq(a.health, moves.max_health - moves.jab.damage)
	assert_eq(b.health, moves.max_health - moves.jab.damage)


func test_press_during_recovery_is_buffered() -> void:
	var jab := moves.jab
	# Second press 2 ticks before the first jab ends.
	run(jab.total() + 1, {0: InputBits.JAB, jab.total() - 2: InputBits.JAB})
	assert_eq(a.action, FighterState.ATTACK)
	assert_eq(a.frame, 0, "buffered jab starts on the first free tick")


func test_holding_a_button_does_not_repeat() -> void:
	run(moves.jab.total() * 3, {}, {}, InputBits.JAB)
	assert_eq(b.health, moves.max_health - moves.jab.damage)


func test_knockout_then_reset() -> void:
	b.health = moves.jab.damage
	run(moves.jab.startup + 1, {0: InputBits.JAB})
	assert_eq(b.action, FighterState.KO)
	assert_eq(s.ko_timer, moves.ko_reset_ticks)
	run(moves.ko_reset_ticks)
	assert_eq(b.health, moves.max_health)
	assert_eq(b.action, FighterState.IDLE)


func test_pack_round_trip() -> void:
	run(7, {0: InputBits.HOOK_R}, {2: InputBits.DODGE_L})
	var copy := s.copy()
	assert_eq(copy.pack(), s.pack())
	assert_eq(copy.state_hash(), s.state_hash())
