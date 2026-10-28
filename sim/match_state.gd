class_name MatchState
## Everything the simulation needs to continue from a given tick.
## pack()/unpack() turn it into a flat int array for rollback snapshots and the network.

const HEADER := 2

var tick: int = 0
## Counts down after a knockout; the fighters reset when it reaches 0.
var ko_timer: int = 0
var fighters: Array[FighterState] = [FighterState.new(), FighterState.new()]


static func create(moves: MoveSet) -> MatchState:
	var s := MatchState.new()
	for f in s.fighters:
		f.reset(moves.max_health)
	return s


func pack() -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(HEADER + FighterState.SIZE * 2)
	out[0] = tick
	out[1] = ko_timer
	fighters[0].pack_into(out, HEADER)
	fighters[1].pack_into(out, HEADER + FighterState.SIZE)
	return out


func unpack(data: PackedInt64Array) -> void:
	tick = data[0]
	ko_timer = data[1]
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
