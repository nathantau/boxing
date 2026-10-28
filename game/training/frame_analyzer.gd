class_name FrameAnalyzer
## Watches one fighter's attacks in training mode and measures what actually happened: the
## result (hit / counter hit / blocked / parried / dodged / whiff), damage, and the real frame
## advantage — how many ticks sooner the attacker could act again than the defender.

const STUNNED := [FighterState.HITSTUN, FighterState.BLOCKSTUN, FighterState.STAGGER, FighterState.KNOCKDOWN, FighterState.PARRY, FighterState.KO]

## Most recent finished attack, or empty. Keys: move, result, damage, startup, active,
## recovery, stamina, advantage (int, or null when nothing connected).
var last := {}
## Increments each time `last` changes.
var count := 0

var _attacker: int
var _rec := {}
var _prev_defender_health := 0


func _init(attacker: int) -> void:
	_attacker = attacker


func observe(s: MatchState, moves: MoveSet) -> void:
	var a := s.fighters[_attacker]
	var d := s.fighters[1 - _attacker]
	if not _rec.is_empty():
		_track(s, a, d, moves)
	if a.action == FighterState.ATTACK and a.frame == 0 and (_rec.is_empty() or _rec.start != s.tick):
		if not _rec.is_empty():
			_finish()  # a new punch came out before the previous exchange settled
		var m := moves.get_move(a.move)
		_rec = {
			"move": a.move, "start": s.tick, "result": "whiff", "damage": 0,
			"startup": Sim.startup_of(a, m), "active": m.active, "recovery": Sim.recovery_of(a, m),
			"stamina": m.stamina_cost, "connected": false, "saw_dodge": false,
			"attacker_free": -1, "defender_free": -1,
		}
	_prev_defender_health = d.health


func _track(s: MatchState, a: FighterState, d: FighterState, moves: MoveSet) -> void:
	if not _rec.connected:
		if d.action == FighterState.HITSTUN and d.frame == 0:
			_rec.result = "counter hit" if d.took_counter else "hit"
			_rec.damage = _prev_defender_health - d.health
			_rec.connected = true
		elif d.action == FighterState.BLOCKSTUN and d.frame == 0:
			_rec.result = "blocked"
			_rec.damage = _prev_defender_health - d.health
			_rec.connected = true
		elif a.action == FighterState.STAGGER and a.frame == 0:
			_rec.result = "parried"
		elif a.action == FighterState.ATTACK and Sim.phase(a, moves) == Sim.Phase.ACTIVE \
				and d.action == FighterState.DODGE and Sim.phase(d, moves) == Sim.Phase.ACTIVE:
			_rec.saw_dodge = true
	if _rec.attacker_free < 0 and s.tick > _rec.start and _is_free(a):
		_rec.attacker_free = s.tick
	if _rec.connected and _rec.defender_free < 0 and not (d.action in STUNNED):
		_rec.defender_free = s.tick
	if _rec.attacker_free >= 0 and (not _rec.connected or _rec.defender_free >= 0):
		_finish()


static func _is_free(f: FighterState) -> bool:
	if f.action == FighterState.IDLE or f.action == FighterState.BLOCK:
		return true
	# A buffered move that came out the moment the previous one ended.
	return (f.action == FighterState.ATTACK or f.action == FighterState.DODGE) and f.frame == 0


func _finish() -> void:
	var rec := _rec.duplicate()
	if rec.result == "whiff" and rec.saw_dodge:
		rec.result = "dodged"
	if rec.connected and rec.defender_free >= 0 and rec.attacker_free >= 0:
		rec.advantage = rec.defender_free - rec.attacker_free
	else:
		rec.advantage = null
	last = rec
	count += 1
	_rec = {}
