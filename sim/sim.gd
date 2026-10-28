class_name Sim
## Advances a MatchState by one 60 Hz tick.
## Deterministic: integer math only, no physics, no randomness, no engine time.
## The same state and inputs give the same result on every platform.

enum Phase { NONE, STARTUP, ACTIVE, RECOVERY }
enum Hit { NONE, HIT, BLOCKED, DODGED }


static func step(s: MatchState, input_a: int, input_b: int, moves: MoveSet) -> void:
	s.tick += 1
	var a := s.fighters[0]
	var b := s.fighters[1]

	if s.ko_timer > 0:
		s.ko_timer -= 1
		for f in s.fighters:
			f.frame += 1
		a.prev_input = input_a
		b.prev_input = input_b
		if s.ko_timer == 0:
			a.reset(moves.max_health)
			b.reset(moves.max_health)
		return

	_advance(a, input_a, moves)
	_advance(b, input_b, moves)

	# Both checks read the same post-advance snapshot, so simultaneous punches trade.
	# Look up both moves first: applying one hit clears the defender's own move.
	var a_result := _check_hit(a, b, moves)
	var b_result := _check_hit(b, a, moves)
	var a_move := moves.get_move(a.move)
	var b_move := moves.get_move(b.move)
	_apply_hit(a, b, a_result, a_move, moves)
	_apply_hit(b, a, b_result, b_move, moves)

	for f in s.fighters:
		if f.health <= 0 and f.action != FighterState.KO:
			f.health = 0
			f.action = FighterState.KO
			f.move = MoveSet.NONE
			f.frame = 0
			s.ko_timer = moves.ko_reset_ticks
	if s.ko_timer > 0:
		for f in s.fighters:
			if f.action != FighterState.KO:
				_to_idle(f)


static func phase(f: FighterState, moves: MoveSet) -> Phase:
	if f.action != FighterState.ATTACK and f.action != FighterState.DODGE:
		return Phase.NONE
	var m := moves.get_move(f.move)
	if f.frame < m.startup:
		return Phase.STARTUP
	if f.frame < m.startup + m.active:
		return Phase.ACTIVE
	return Phase.RECOVERY


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
	match f.action:
		FighterState.ATTACK, FighterState.DODGE:
			if f.frame >= moves.get_move(f.move).total():
				_to_idle(f)
		FighterState.HITSTUN, FighterState.BLOCKSTUN:
			f.stun -= 1
			if f.stun <= 0:
				_to_idle(f)

	if f.action != FighterState.IDLE and f.action != FighterState.BLOCK:
		return
	if f.buffered != MoveSet.NONE:
		f.action = FighterState.DODGE if MoveSet.is_dodge(f.buffered) else FighterState.ATTACK
		f.move = f.buffered
		f.frame = 0
		f.hit_done = 0
		f.buffered = MoveSet.NONE
	elif input & InputBits.BLOCK:
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
	if pressed & InputBits.JAB:
		return MoveSet.JAB
	return MoveSet.NONE


static func _to_idle(f: FighterState) -> void:
	f.action = FighterState.IDLE
	f.move = MoveSet.NONE
	f.frame = 0
	f.stun = 0


static func _check_hit(att: FighterState, def: FighterState, moves: MoveSet) -> Hit:
	if att.action != FighterState.ATTACK or att.hit_done == 1:
		return Hit.NONE
	if phase(att, moves) != Phase.ACTIVE or def.action == FighterState.KO:
		return Hit.NONE
	if def.action == FighterState.DODGE and phase(def, moves) == Phase.ACTIVE:
		var side := InputBits.DODGE_L if def.move == MoveSet.DODGE_L else InputBits.DODGE_R
		if moves.get_move(att.move).dodged_by & side:
			return Hit.DODGED
	if def.action == FighterState.BLOCKSTUN:
		return Hit.BLOCKED
	if def.action == FighterState.BLOCK and def.frame >= moves.block_startup:
		return Hit.BLOCKED
	return Hit.HIT


static func _apply_hit(att: FighterState, def: FighterState, result: Hit, m: MoveData, moves: MoveSet) -> void:
	if result == Hit.NONE or result == Hit.DODGED:
		return
	att.hit_done = 1
	if result == Hit.BLOCKED:
		def.health -= m.chip_damage
		def.action = FighterState.BLOCKSTUN
		def.stun = m.blockstun
	else:
		var damage := m.damage
		if def.action == FighterState.DODGE and phase(def, moves) == Phase.RECOVERY:
			damage += m.dodge_punish_damage
		def.health -= damage
		def.action = FighterState.HITSTUN
		def.stun = m.hitstun
	def.move = MoveSet.NONE
	def.frame = 0
