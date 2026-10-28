class_name DummySource
extends InputSource
## Training dummy: stands, blocks, repeats one punch, reacts with a perfect dodge or parry, or
## hands control to the hard CPU.

enum Mode { STAND, BLOCK, JAB, HOOK_L, HOOK_R, UPPERCUT, DODGE, PARRY, CPU }

const MODE_NAMES := ["Stand", "Block", "Jab", "Left hook", "Right hook", "Uppercut", "Perfect dodge", "Perfect parry", "CPU (hard)"]
const PUNCH_BITS := {
	Mode.JAB: InputBits.JAB, Mode.HOOK_L: InputBits.HOOK_L,
	Mode.HOOK_R: InputBits.HOOK_R, Mode.UPPERCUT: InputBits.UPPERCUT,
}
## Repeating punches come out after the dummy has been idle this long.
const REPEAT_IDLE_TICKS := 40

var mode := Mode.STAND
var _me: int
var _moves: MoveSet
var _cpu: AISource
var _answered := -1
var _press_tick := -1
var _press_bits := 0


func _init(me: int, moves: MoveSet) -> void:
	_me = me
	_moves = moves
	_cpu = AISource.new(me, moves, AISource.Level.HARD, 99)


func observe(s: MatchState) -> void:
	held = 0
	if mode == Mode.CPU:
		_cpu.observe(s)
		return
	if s.phase != MatchState.Phase.FIGHT:
		return
	var me := s.fighters[_me]
	var opp := s.fighters[1 - _me]
	if _press_tick >= 0 and s.tick >= _press_tick:
		press(_press_bits)
		_press_tick = -1
	match mode:
		Mode.BLOCK:
			held = InputBits.BLOCK
		Mode.JAB, Mode.HOOK_L, Mode.HOOK_R, Mode.UPPERCUT:
			if me.action == FighterState.IDLE and me.frame == REPEAT_IDLE_TICKS:
				press(PUNCH_BITS[mode])
		Mode.DODGE, Mode.PARRY:
			if opp.action == FighterState.ATTACK and opp.frame == 0 and s.tick != _answered:
				_answered = s.tick
				_react(s, opp)


func consume() -> int:
	if mode == Mode.CPU:
		return _cpu.consume()
	return super()


func sample() -> void:
	if mode == Mode.CPU:
		_cpu.sample()
	super()


## Schedule the ideal answer to a punch that just started.
func _react(s: MatchState, opp: FighterState) -> void:
	var m := _moves.get_move(opp.move)
	var first_active := Sim.startup_of(opp, m)
	if mode == Mode.PARRY:
		_schedule(s, InputBits.JAB, first_active - 1)
		return
	var side := InputBits.DODGE_L if m.dodged_by & InputBits.DODGE_L else InputBits.DODGE_R
	var dodge := _moves.get_move(MoveSet.DODGE_L if side == InputBits.DODGE_L else MoveSet.DODGE_R)
	_schedule(s, side, first_active - dodge.startup)


## Press so our move starts when the opponent's frame is `target_frame` (opponent is on frame 0 now).
func _schedule(s: MatchState, bits: int, target_frame: int) -> void:
	var wait := target_frame - 1
	if wait <= 0:
		press(bits)
	else:
		_press_tick = s.tick + wait
		_press_bits = bits
