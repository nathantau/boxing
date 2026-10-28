class_name MatchState
## Everything the simulation needs to continue from a given tick.
## pack()/unpack() turn it into a flat int array for rollback snapshots and the network.

enum Phase { INTRO, FIGHT, ROUND_OVER, MATCH_OVER }

## round_winner / match_winner values besides the fighter index 0 or 1.
const NO_WINNER := -1
const DRAW := 2

const HEADER := 9

var tick: int = 0
var phase: int = Phase.INTRO
## Ticks left in INTRO or ROUND_OVER.
var phase_timer: int = 0
## 1-based round number.
var round_number: int = 1
## Ticks left on the round clock.
var round_timer: int = 0
var wins_a: int = 0
var wins_b: int = 0
var round_winner: int = NO_WINNER
var match_winner: int = NO_WINNER
var fighters: Array[FighterState] = [FighterState.new(), FighterState.new()]


static func create(moves: MoveSet) -> MatchState:
	var s := MatchState.new()
	s.start_round(moves)
	return s


func start_round(moves: MoveSet) -> void:
	phase = Phase.INTRO
	phase_timer = moves.intro_ticks
	round_timer = moves.round_ticks
	round_winner = NO_WINNER
	for f in fighters:
		f.reset(moves)


func wins(fighter: int) -> int:
	return wins_a if fighter == 0 else wins_b


func pack() -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(HEADER + FighterState.SIZE * 2)
	out[0] = tick
	out[1] = phase
	out[2] = phase_timer
	out[3] = round_number
	out[4] = round_timer
	out[5] = wins_a
	out[6] = wins_b
	out[7] = round_winner
	out[8] = match_winner
	fighters[0].pack_into(out, HEADER)
	fighters[1].pack_into(out, HEADER + FighterState.SIZE)
	return out


func unpack(data: PackedInt64Array) -> void:
	tick = data[0]
	phase = data[1]
	phase_timer = data[2]
	round_number = data[3]
	round_timer = data[4]
	wins_a = data[5]
	wins_b = data[6]
	round_winner = data[7]
	match_winner = data[8]
	fighters[0].unpack_from(data, HEADER)
	fighters[1].unpack_from(data, HEADER + FighterState.SIZE)


func copy() -> MatchState:
	var s := MatchState.new()
	s.unpack(pack())
	return s


## 32-bit FNV-1a over every byte of the packed state. Identical on every platform.
func state_hash() -> int:
	var h := 2166136261
	for value in pack():
		for shift in range(0, 64, 8):
			h = ((h ^ ((value >> shift) & 0xFF)) * 16777619) & 0xFFFFFFFF
	return h
