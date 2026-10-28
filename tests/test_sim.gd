extends GutTest
## Rules of the combat sim. Timings are derived from moves.tres, so these keep passing when you retune numbers.

var moves: MoveSet = preload("res://sim/moves.tres")
var s: MatchState
var a: FighterState
var b: FighterState


func before_each() -> void:
	s = MatchState.create(moves)
	s.phase = MatchState.Phase.FIGHT  # Skip the round intro.
	a = s.fighters[0]
	b = s.fighters[1]


## Runs `ticks` steps. Each press is held for one tick at the given tick offset (0 = the first step).
func run(ticks: int, a_presses := {}, b_presses := {}, a_hold := 0, b_hold := 0) -> void:
	for t in ticks:
		Sim.step(s, a_hold | a_presses.get(t, 0), b_hold | b_presses.get(t, 0), moves)


# --- Basic hits ---------------------------------------------------------------

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
		Sim.step(s, InputBits.JAB if t == 0 else 0, InputBits.BLOCK if t >= late else 0, moves)
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
	# Both press on tick 0, so A's jab is not a parry (the hook isn't in its window yet).
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


# --- Stamina ------------------------------------------------------------------

func test_moves_cost_stamina_and_it_regenerates() -> void:
	run(1, {0: InputBits.JAB})
	var after_jab := moves.max_stamina - moves.jab.stamina_cost
	assert_eq(a.stamina, after_jab)
	run(moves.jab.total() + moves.stamina_regen_delay - 2)
	assert_eq(a.stamina, after_jab, "no regen while attacking or during the regen delay")
	run(20)
	assert_gt(a.stamina, after_jab)


func test_blocking_drains_stamina() -> void:
	run(moves.jab.startup + 1, {0: InputBits.JAB}, {}, 0, InputBits.BLOCK)
	assert_eq(b.stamina, moves.max_stamina - moves.jab.block_stamina_damage)


func test_running_out_exhausts() -> void:
	a.stamina = moves.jab.stamina_cost - 1
	a.regen_wait = 100  # no regen on the tick the jab starts
	run(1, {0: InputBits.JAB})
	assert_eq(a.stamina, 0)
	assert_eq(a.exhausted, 1)


func test_exhausted_moves_are_slower() -> void:
	a.stamina = 0
	a.exhausted = 1
	run(moves.jab.startup + 1, {0: InputBits.JAB})
	assert_eq(b.health, moves.max_health, "slowed jab has not landed yet")
	run(moves.exhausted_slow)
	assert_eq(b.health, moves.max_health - moves.jab.damage)


func test_exhausted_fighter_cannot_block() -> void:
	b.stamina = 0
	b.exhausted = 1
	run(moves.jab.startup + 1, {0: InputBits.JAB}, {}, 0, InputBits.BLOCK)
	assert_eq(b.health, moves.max_health - moves.jab.damage)


func test_exhaustion_wears_off() -> void:
	a.stamina = 0
	a.exhausted = 1
	run(moves.stamina_regen_delay + moves.exhaust_recover / moves.stamina_regen + 2)
	assert_eq(a.exhausted, 0)


# --- Parry and counter --------------------------------------------------------

func test_punch_in_parry_window_parries() -> void:
	var hook := moves.hook_l
	var press := hook.startup - hook.parry_window  # earliest tick in the window
	run(press + 1, {0: InputBits.HOOK_L}, {press: InputBits.JAB})
	assert_eq(b.action, FighterState.PARRY)
	assert_eq(a.action, FighterState.STAGGER)
	assert_eq(b.stamina, moves.max_stamina, "the parrying punch is free")
	run(hook.total())
	assert_eq(b.health, moves.max_health, "parried hook never lands")


func test_parry_on_first_active_frame() -> void:
	var hook := moves.hook_l
	run(hook.startup + 1, {0: InputBits.HOOK_L}, {hook.startup: InputBits.JAB})
	assert_eq(b.action, FighterState.PARRY)
	assert_eq(b.health, moves.max_health)


func test_too_early_is_not_a_parry() -> void:
	var hook := moves.hook_l
	var press := hook.startup - hook.parry_window - 1
	run(press + 1, {0: InputBits.HOOK_L}, {press: InputBits.JAB})
	assert_eq(b.action, FighterState.ATTACK)
	assert_eq(a.action, FighterState.ATTACK)


func test_counter_hit_after_parry() -> void:
	var hook := moves.hook_l
	var press := hook.startup - hook.parry_window
	var counter_press := press + moves.parry_ticks - 1  # buffered, comes out when the parry ends
	run(counter_press + moves.jab.startup + 3, {0: InputBits.HOOK_L}, {press: InputBits.JAB, counter_press: InputBits.JAB})
	assert_eq(a.health, moves.max_health - Fixed.pct(moves.jab.damage, 100 + moves.counter_bonus_pct))
	assert_eq(a.took_counter, 1)


# --- Knockdowns and rounds ----------------------------------------------------

func test_burst_of_damage_knocks_down() -> void:
	b.knock_meter = moves.knockdown_threshold
	run(moves.jab.startup + 1, {0: InputBits.JAB})
	assert_eq(b.action, FighterState.KNOCKDOWN)
	assert_eq(b.knockdowns, 1)


func test_knocked_down_fighter_cannot_be_hit_and_gets_up() -> void:
	b.knock_meter = moves.knockdown_threshold
	run(moves.jab.startup + 1, {0: InputBits.JAB})
	var health := b.health
	run(moves.jab.total() + moves.jab.startup + 1, {moves.jab.total(): InputBits.JAB})
	assert_eq(b.health, health, "invulnerable while down")
	run(moves.knockdown_ticks)
	assert_eq(b.action, FighterState.IDLE)


func test_third_knockdown_is_tko() -> void:
	b.knockdowns = moves.max_knockdowns - 1
	b.knock_meter = moves.knockdown_threshold
	run(moves.jab.startup + 1, {0: InputBits.JAB})
	assert_eq(b.action, FighterState.KO)
	assert_eq(s.phase, MatchState.Phase.ROUND_OVER)
	assert_eq(s.round_winner, 0)


func test_ko_wins_round_and_next_round_starts_fresh() -> void:
	b.health = moves.jab.damage
	run(moves.jab.startup + 1, {0: InputBits.JAB})
	assert_eq(b.action, FighterState.KO)
	assert_eq(s.phase, MatchState.Phase.ROUND_OVER)
	assert_eq(s.wins_a, 1)
	run(moves.round_over_ticks)
	assert_eq(s.phase, MatchState.Phase.INTRO)
	assert_eq(s.round_number, 2)
	assert_eq(b.health, moves.max_health)
	assert_eq(b.action, FighterState.IDLE)
	assert_eq(s.wins_a, 1, "wins carry over")


func test_two_round_wins_end_the_match() -> void:
	s.wins_a = moves.rounds_to_win - 1
	b.health = moves.jab.damage
	run(moves.jab.startup + 1 + moves.round_over_ticks, {0: InputBits.JAB})
	assert_eq(s.phase, MatchState.Phase.MATCH_OVER)
	assert_eq(s.match_winner, 0)


func test_double_ko_is_a_draw() -> void:
	a.health = moves.jab.damage
	b.health = moves.jab.damage
	run(moves.jab.startup + 1, {0: InputBits.JAB}, {0: InputBits.JAB})
	assert_eq(s.round_winner, MatchState.DRAW)
	assert_eq(s.wins_a, 1)
	assert_eq(s.wins_b, 1)


func test_time_up_goes_to_higher_health() -> void:
	s.round_timer = 1
	a.health = 400
	b.health = 900
	run(1)
	assert_eq(s.phase, MatchState.Phase.ROUND_OVER)
	assert_eq(s.round_winner, 1)


func test_no_control_during_intro() -> void:
	s = MatchState.create(moves)
	a = s.fighters[0]
	b = s.fighters[1]
	run(moves.intro_ticks, {0: InputBits.JAB, moves.intro_ticks - 1: InputBits.JAB})
	assert_eq(s.phase, MatchState.Phase.FIGHT)
	assert_eq(a.action, FighterState.IDLE)
	run(moves.jab.startup + 2)
	assert_eq(b.health, moves.max_health, "presses during the intro are dropped")


func test_pack_round_trip() -> void:
	run(7, {0: InputBits.HOOK_R}, {2: InputBits.DODGE_L})
	var copy := s.copy()
	assert_eq(copy.pack(), s.pack())
	assert_eq(copy.state_hash(), s.state_hash())
