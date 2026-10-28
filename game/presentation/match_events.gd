class_name MatchEvents
## Turns the sim state into one-shot presentation events (hit, block, parry, knockdown, KO,
## punch whoosh, round bell) for sounds, sparks, camera shake and haptics.
##
## Events are derived from the state alone and keyed by the tick their action started
## (state.tick - frame), so showing the same moment twice, or re-simulating it in a rollback,
## never fires an event twice. If a rollback reveals an event that started a few ticks ago, it
## still fires (slightly late) as long as it started within RECENT_TICKS.

enum Kind { PUNCH, HIT, COUNTER_HIT, BLOCK, PARRY, STAGGER, KNOCKDOWN, KO, ROUND_START, ROUND_END }

## Covers the deepest rollback (MAX_PREDICTION) plus a few ticks of catch-up.
const RECENT_TICKS := 16
## Forget keys after this long.
const KEEP_TICKS := 600

## key -> tick it fired
var _fired := {}
var _now := 0


class Event:
	var kind: Kind
	## Fighter it happened to (the defender for hits and blocks), or -1 for match events.
	var fighter: int
	## Move involved, for PUNCH: MoveSet.JAB etc.
	var move: int
	## 0..1, how big it was (hitstun length for hits).
	var strength: float

	func _init(k: Kind, f: int, m := MoveSet.NONE, s := 0.5) -> void:
		kind = k
		fighter = f
		move = m
		strength = s


func collect(state: MatchState, moves: MoveSet) -> Array[Event]:
	var events: Array[Event] = []
	_now = state.tick
	for i in 2:
		var f := state.fighters[i]
		if f.frame >= RECENT_TICKS:
			continue
		var started := state.tick - f.frame
		match f.action:
			FighterState.ATTACK:
				_add(events, "punch", started, i, Event.new(Kind.PUNCH, i, f.move))
			FighterState.HITSTUN:
				var strength := clampf(f.stun / float(maxi(moves.uppercut.hitstun, 1)), 0.0, 1.0)
				var kind := Kind.COUNTER_HIT if f.took_counter else Kind.HIT
				_add(events, "hit", started, i, Event.new(kind, i, MoveSet.NONE, 1.0 if f.took_counter else strength))
			FighterState.BLOCKSTUN:
				_add(events, "block", started, i, Event.new(Kind.BLOCK, i))
			FighterState.PARRY:
				_add(events, "parry", started, i, Event.new(Kind.PARRY, i))
			FighterState.STAGGER:
				_add(events, "stagger", started, i, Event.new(Kind.STAGGER, i))
			FighterState.KNOCKDOWN:
				_add(events, "down", started, i, Event.new(Kind.KNOCKDOWN, i, MoveSet.NONE, 1.0))
			FighterState.KO:
				_add(events, "ko", started, i, Event.new(Kind.KO, i, MoveSet.NONE, 1.0))

	if state.phase == MatchState.Phase.INTRO and state.phase_timer * 2 <= moves.intro_ticks:
		_add(events, "bell", state.round_number, -1, Event.new(Kind.ROUND_START, -1))
	elif state.phase == MatchState.Phase.ROUND_OVER:
		_add(events, "round_end", state.round_number, -1, Event.new(Kind.ROUND_END, -1))

	for key: String in _fired.keys():
		# Time jumping far backwards means a new match started (reset() should have been called).
		# Small steps back happen when a session resumes from a confirmed state; keep those keys.
		if state.tick - _fired[key] > KEEP_TICKS or _fired[key] - state.tick > 2 * RECENT_TICKS:
			_fired.erase(key)
	return events


## Forget everything (a new match started, e.g. a rematch: rounds and ticks repeat).
func reset() -> void:
	_fired.clear()


func _add(events: Array[Event], what: String, when: int, fighter: int, event: Event) -> void:
	var key := "%s:%d:%d" % [what, fighter, when]
	if _fired.has(key):
		return
	_fired[key] = _now
	events.append(event)
