class_name Sim
## Advances a MatchState by one 60 Hz tick.
## Deterministic: integer math only, no physics, no randomness, no engine time.
## The same state and inputs give the same result on every platform.

enum Phase { NONE, STARTUP, ACTIVE, RECOVERY }
enum Hit { NONE, HIT, BLOCKED, DODGED }

const TICK_RATE := 60


static func step(s: MatchState, input_a: int, input_b: int, moves: MoveSet) -> void:
	s.tick += 1
	var a := s.fighters[0]
	var b := s.fighters[1]
	match s.phase:
		MatchState.Phase.FIGHT:
			_fight(s, input_a, input_b, moves)
		MatchState.Phase.INTRO:
			_hold(a, input_a)
			_hold(b, input_b)
			s.phase_timer -= 1
			if s.phase_timer <= 0:
				s.phase = MatchState.Phase.FIGHT
		MatchState.Phase.ROUND_OVER:
			_hold(a, input_a)
			_hold(b, input_b)
			s.phase_timer -= 1
			if s.phase_timer <= 0:
				_next_round(s, moves)
		MatchState.Phase.MATCH_OVER:
			_hold(a, input_a)
			_hold(b, input_b)


## Current phase of an attack or dodge, including the exhaustion slowdown.
static func phase(f: FighterState, moves: MoveSet) -> Phase:
	if f.action != FighterState.ATTACK and f.action != FighterState.DODGE:
		return Phase.NONE
	var m := moves.get_move(f.move)
	if f.frame < startup_of(f, m):
		return Phase.STARTUP
	if f.frame < startup_of(f, m) + m.active:
		return Phase.ACTIVE
	return Phase.RECOVERY


static func startup_of(f: FighterState, m: MoveData) -> int:
	return m.startup + f.slow


static func recovery_of(f: FighterState, m: MoveData) -> int:
	return m.recovery + f.slow


## Between rounds: no control, but keep press detection and animation time going.
static func _hold(f: FighterState, input: int) -> void:
	f.prev_input = input
	f.frame += 1


static func _fight(s: MatchState, input_a: int, input_b: int, moves: MoveSet) -> void:
	var a := s.fighters[0]
	var b := s.fighters[1]
	s.round_timer -= 1
	_advance(a, input_a, moves)
	_advance(b, input_b, moves)

	# Everything below reads one post-advance snapshot for both sides, so neither fighter
	# gets an advantage from being processed first.
	var a_parries := _parries(a, b, moves)
	var b_parries := _parries(b, a, moves)
	if a_parries:
		_apply_parry(a, b, moves)
	elif b_parries:
		_apply_parry(b, a, moves)

	var a_result := _check_hit(a, b, moves)
	var b_result := _check_hit(b, a, moves)
	# Look these up first: applying one hit clears the defender's own move and counter.
	var a_move := moves.get_move(a.move)
	var b_move := moves.get_move(b.move)
	var a_counter := a.counter > 0
	var b_counter := b.counter > 0
	_apply_hit(a, b, a_result, a_move, a_counter, moves)
	_apply_hit(b, a, b_result, b_move, b_counter, moves)

	_check_down(a, moves)
	_check_down(b, moves)
	var a_out := a.action == FighterState.KO
	var b_out := b.action == FighterState.KO
	if a_out or b_out:
		_end_round(s, MatchState.DRAW if a_out and b_out else (1 if a_out else 0), moves)
	elif s.round_timer <= 0:
		var winner := MatchState.DRAW
		if a.health > b.health:
			winner = 0
		elif b.health > a.health:
			winner = 1
		_end_round(s, winner, moves)


static func _advance(f: FighterState, input: int, moves: MoveSet) -> void:
	var pressed := input & ~f.prev_input
	f.prev_input = input

	var wanted := _move_from_presses(pressed)
	if wanted != MoveSet.NONE:
		f.buffered = wanted
		f.buffer_age = 0
	elif f.buffered != MoveSet.NONE:
		f.buffer_age += 1
		if f.buffer_age > moves.input_buffer:
			f.buffered = MoveSet.NONE

	f.frame += 1
	if f.counter > 0:
		f.counter -= 1
	f.knock_meter = maxi(0, f.knock_meter - moves.knock_decay)
	_regen(f, moves)

	match f.action:
		FighterState.ATTACK, FighterState.DODGE:
			var m := moves.get_move(f.move)
			if f.frame >= startup_of(f, m) + m.active + recovery_of(f, m):
				_to_idle(f)
		FighterState.HITSTUN, FighterState.BLOCKSTUN, FighterState.PARRY, FighterState.STAGGER, FighterState.KNOCKDOWN:
			f.stun -= 1
			if f.stun <= 0:
				_to_idle(f)

	if f.action != FighterState.IDLE and f.action != FighterState.BLOCK:
		return
	if f.buffered != MoveSet.NONE:
		_start_move(f, f.buffered, moves)
	elif input & InputBits.BLOCK and f.exhausted == 0:
		if f.action != FighterState.BLOCK:
			f.action = FighterState.BLOCK
			f.frame = 0
	elif f.action == FighterState.BLOCK:
		_to_idle(f)


## Dodges win over punches if pressed on the same tick; heavier punches win over lighter ones.
static func _move_from_presses(pressed: int) -> int:
	if pressed & InputBits.DODGE_L:
		return MoveSet.DODGE_L
	if pressed & InputBits.DODGE_R:
		return MoveSet.DODGE_R
	if pressed & InputBits.UPPERCUT:
		return MoveSet.UPPERCUT
	if pressed & InputBits.HOOK_L:
		return MoveSet.HOOK_L
	if pressed & InputBits.HOOK_R:
		return MoveSet.HOOK_R
	if pressed & InputBits.CROSS:
		return MoveSet.CROSS
	if pressed & InputBits.JAB:
		return MoveSet.JAB
	return MoveSet.NONE


static func _start_move(f: FighterState, move: int, moves: MoveSet) -> void:
	f.action = FighterState.DODGE if MoveSet.is_dodge(move) else FighterState.ATTACK
	f.move = move
	f.frame = 0
	f.hit_done = 0
	f.buffered = MoveSet.NONE
	f.slow = moves.exhausted_slow if f.exhausted else 0
	_spend(f, moves.get_move(move).stamina_cost, moves)


static func _spend(f: FighterState, amount: int, moves: MoveSet) -> void:
	f.stamina -= amount
	f.regen_wait = moves.stamina_regen_delay
	if f.stamina <= 0:
		f.stamina = 0
		f.exhausted = 1


static func _regen(f: FighterState, moves: MoveSet) -> void:
	if f.action == FighterState.ATTACK or f.action == FighterState.DODGE:
		return
	if f.regen_wait > 0:
		f.regen_wait -= 1
		return
	f.stamina = mini(moves.max_stamina, f.stamina + moves.stamina_regen)
	if f.exhausted and f.stamina >= moves.exhaust_recover:
		f.exhausted = 0


static func _to_idle(f: FighterState) -> void:
	f.action = FighterState.IDLE
	f.move = MoveSet.NONE
	f.frame = 0
	f.stun = 0
	f.slow = 0


## True if `def` started a punch this tick while `att`'s punch is in its parry window.
static func _parries(def: FighterState, att: FighterState, moves: MoveSet) -> bool:
	if def.action != FighterState.ATTACK or def.frame != 0:
		return false
	if att.action != FighterState.ATTACK or att.hit_done == 1:
		return false
	var m := moves.get_move(att.move)
	var first_active := startup_of(att, m)
	return att.frame >= first_active - m.parry_window and att.frame <= first_active


static func _apply_parry(def: FighterState, att: FighterState, moves: MoveSet) -> void:
	# The punch used to parry is free.
	def.stamina = mini(moves.max_stamina, def.stamina + moves.get_move(def.move).stamina_cost)
	if def.exhausted and def.stamina >= moves.exhaust_recover:
		def.exhausted = 0
	var m := moves.get_move(att.move)
	def.action = FighterState.PARRY
	def.move = MoveSet.NONE
	def.frame = 0
	def.slow = 0
	def.stun = moves.parry_ticks
	def.counter = moves.counter_window
	att.action = FighterState.STAGGER
	att.move = MoveSet.NONE
	att.frame = 0
	att.slow = 0
	att.stun = m.parry_stagger
	att.buffered = MoveSet.NONE


static func _check_hit(att: FighterState, def: FighterState, moves: MoveSet) -> Hit:
	if att.action != FighterState.ATTACK or att.hit_done == 1:
		return Hit.NONE
	if phase(att, moves) != Phase.ACTIVE:
		return Hit.NONE
	if def.action == FighterState.KO or def.action == FighterState.KNOCKDOWN or def.action == FighterState.PARRY:
		return Hit.NONE
	if def.action == FighterState.DODGE and phase(def, moves) == Phase.ACTIVE:
		var side := InputBits.DODGE_L if def.move == MoveSet.DODGE_L else InputBits.DODGE_R
		if moves.get_move(att.move).dodged_by & side:
			return Hit.DODGED
	if def.exhausted == 0:
		if def.action == FighterState.BLOCKSTUN:
			return Hit.BLOCKED
		if def.action == FighterState.BLOCK and def.frame >= moves.block_startup:
			return Hit.BLOCKED
	return Hit.HIT


static func _apply_hit(att: FighterState, def: FighterState, result: Hit, m: MoveData, is_counter: bool, moves: MoveSet) -> void:
	if result == Hit.NONE or result == Hit.DODGED:
		return
	att.hit_done = 1
	if result == Hit.BLOCKED:
		def.health -= m.chip_damage
		_spend(def, m.block_stamina_damage, moves)
		def.action = FighterState.BLOCKSTUN
		def.stun = m.blockstun
	else:
		var damage := m.damage
		if def.action == FighterState.DODGE and phase(def, moves) == Phase.RECOVERY:
			damage += m.dodge_punish_damage
		if is_counter:
			damage = Fixed.pct(damage, 100 + moves.counter_bonus_pct)
			att.counter = 0
		def.took_counter = 1 if is_counter else 0
		def.health -= damage
		def.knock_meter += damage
		def.action = FighterState.HITSTUN
		def.stun = m.hitstun
	def.move = MoveSet.NONE
	def.frame = 0
	def.slow = 0
	def.counter = 0


static func _check_down(f: FighterState, moves: MoveSet) -> void:
	if f.action == FighterState.KO or f.action == FighterState.KNOCKDOWN:
		return
	var knocked_down := f.knock_meter >= moves.knockdown_threshold
	if f.health > 0 and not knocked_down:
		return
	f.move = MoveSet.NONE
	f.frame = 0
	f.slow = 0
	f.buffered = MoveSet.NONE
	f.knock_meter = 0
	if knocked_down:
		f.knockdowns += 1
	if f.health <= 0 or f.knockdowns >= moves.max_knockdowns:
		f.health = maxi(f.health, 0)
		f.action = FighterState.KO
	else:
		f.action = FighterState.KNOCKDOWN
		f.stun = moves.knockdown_ticks


static func _end_round(s: MatchState, winner: int, moves: MoveSet) -> void:
	s.round_winner = winner
	if winner == 0 or winner == MatchState.DRAW:
		s.wins_a += 1
	if winner == 1 or winner == MatchState.DRAW:
		s.wins_b += 1
	s.phase = MatchState.Phase.ROUND_OVER
	s.phase_timer = moves.round_over_ticks
	for f in s.fighters:
		if f.action != FighterState.KO:
			_to_idle(f)


static func _next_round(s: MatchState, moves: MoveSet) -> void:
	var a_won := s.wins_a >= moves.rounds_to_win
	var b_won := s.wins_b >= moves.rounds_to_win
	if a_won or b_won:
		s.phase = MatchState.Phase.MATCH_OVER
		s.match_winner = MatchState.DRAW if a_won and b_won else (0 if a_won else 1)
		return
	s.round_number += 1
	s.start_round(moves)
