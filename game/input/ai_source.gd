class_name AISource
extends InputSource
## Computer opponent. Reads the sim state each tick and produces the same InputBits a player would.
## It reacts to an incoming punch only after `reaction` ticks, then blocks, dodges, parries or eats
## it depending on its level; it attacks when the opponent is open and it has stamina to spare.
## Random choices come from a seeded RNG, so an AI match replays identically.

enum Level { EASY, NORMAL, HARD }

const LEVEL_NAMES := ["easy", "normal", "hard"]

## reaction: ticks before it notices a punch (a jab lands on tick 5, so only fast reactions
## can stop jabs; slower punches give every level a chance). defend / parry: chance to defend at all, and to
## parry when defending. aggression: chance per free tick to start an attack. punish: chance to
## attack an opponent who is staggered or recovering.
const PROFILES := {
	Level.EASY: { "reaction": 6, "defend": 0.35, "parry": 0.0, "aggression": 0.015, "punish": 0.3 },
	Level.NORMAL: { "reaction": 4, "defend": 0.65, "parry": 0.15, "aggression": 0.03, "punish": 0.6 },
	Level.HARD: { "reaction": 2, "defend": 0.9, "parry": 0.4, "aggression": 0.045, "punish": 0.9 },
}

## Below this stamina it only attacks to punish.
const STAMINA_RESERVE := 400

var level: Level
var _me: int
var _moves: MoveSet
var _profile: Dictionary
var _rng := RandomNumberGenerator.new()
## Tick at which the opponent's current attack started, once we've decided how to answer it.
var _answered_attack := -1
var _block_until := -1
var _press_tick := -1
var _press_bits := 0


func _init(me: int, moves: MoveSet, ai_level: Level, rng_seed: int) -> void:
	_me = me
	_moves = moves
	level = ai_level
	_profile = PROFILES[ai_level]
	_rng.seed = rng_seed


func observe(s: MatchState) -> void:
	held = 0
	if s.phase != MatchState.Phase.FIGHT:
		_press_tick = -1
		_block_until = -1
		return
	var me := s.fighters[_me]
	var opp := s.fighters[1 - _me]

	if s.tick < _block_until and me.exhausted == 0:
		held |= InputBits.BLOCK
	if _press_tick >= 0 and s.tick >= _press_tick:
		press(_press_bits)
		_press_tick = -1

	if opp.action == FighterState.ATTACK and opp.hit_done == 0 and Sim.phase(opp, _moves) != Sim.Phase.RECOVERY:
		var started := s.tick - opp.frame
		if started != _answered_attack and opp.frame >= _profile.reaction:
			_answered_attack = started
			_defend(s, me, opp)
		return

	if _press_tick >= 0 or (me.action != FighterState.IDLE and me.action != FighterState.BLOCK):
		return
	if _is_open(opp):
		if _rng.randf() < _profile.punish:
			press(_punish_move(me, opp))
	elif me.stamina > STAMINA_RESERVE and _rng.randf() < _profile.aggression:
		press(_random_attack())


func _defend(s: MatchState, me: FighterState, opp: FighterState) -> void:
	var m := _moves.get_move(opp.move)
	var first_active := Sim.startup_of(opp, m)
	if _rng.randf() >= _profile.defend:
		return  # Didn't see it coming.

	if _rng.randf() < _profile.parry and me.exhausted == 0:
		# Aim the parry one tick before the punch lands, the middle of the window.
		if _schedule(s, opp, InputBits.JAB, first_active - 1):
			return

	var dodge_sides := m.dodged_by
	var prefer_dodge := me.exhausted == 1 or (opp.move != MoveSet.UPPERCUT and _rng.randf() < 0.5)
	if prefer_dodge and dodge_sides != 0:
		var side := InputBits.DODGE_L
		if dodge_sides == InputBits.DODGE_R or (dodge_sides & InputBits.DODGE_R and _rng.randf() < 0.5):
			side = InputBits.DODGE_R
		var dodge := _moves.get_move(MoveSet.DODGE_L if side == InputBits.DODGE_L else MoveSet.DODGE_R)
		if _schedule(s, opp, side, first_active - dodge.startup):
			return

	_block_until = s.tick + (first_active + m.active - opp.frame) + 2


## Press `bits` so our move starts when the opponent's frame is `target_frame`.
## Returns false if that moment has already passed.
func _schedule(s: MatchState, opp: FighterState, bits: int, target_frame: int) -> bool:
	# Input given now is used by the next step, during which the opponent's frame advances by one.
	var wait := target_frame - 1 - opp.frame
	if wait < 0:
		return false
	_press_tick = s.tick + wait
	_press_bits = bits
	if wait == 0:
		press(bits)
		_press_tick = -1
	return true


func _is_open(opp: FighterState) -> bool:
	if opp.action == FighterState.STAGGER:
		return true
	return (opp.action == FighterState.ATTACK or opp.action == FighterState.DODGE) \
		and Sim.phase(opp, _moves) == Sim.Phase.RECOVERY


func _punish_move(me: FighterState, opp: FighterState) -> int:
	if opp.action == FighterState.STAGGER and opp.stun > _moves.uppercut.startup + 2 and me.stamina >= _moves.uppercut.stamina_cost:
		return InputBits.UPPERCUT
	if opp.action == FighterState.DODGE and me.stamina >= _moves.uppercut.stamina_cost:
		return InputBits.UPPERCUT
	return InputBits.HOOK_L if _rng.randf() < 0.5 else InputBits.HOOK_R


func _random_attack() -> int:
	var roll := _rng.randf()
	if roll < 0.35:
		return InputBits.JAB
	if roll < 0.5:
		return InputBits.CROSS
	if roll < 0.7:
		return InputBits.HOOK_L
	if roll < 0.9:
		return InputBits.HOOK_R
	return InputBits.UPPERCUT
