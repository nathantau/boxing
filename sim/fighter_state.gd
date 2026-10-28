class_name FighterState
## Simulated state of one boxer. Ints only: this is exactly what rollback saves and restores.

enum { IDLE, ATTACK, BLOCK, DODGE, HITSTUN, BLOCKSTUN, KO, PARRY, STAGGER, KNOCKDOWN }

## Number of ints written by pack_into(); bump when adding a field.
const SIZE := 17

var action: int = IDLE
## Current attack or dodge (MoveSet.JAB, ...), NONE otherwise.
var move: int = MoveSet.NONE
## Ticks spent in the current action, starting at 0.
var frame: int = 0
## Remaining ticks of a timed action: hitstun, blockstun, parry, stagger, knockdown.
var stun: int = 0
## 1 once the current attack has hit or been blocked, so it connects only once.
var hit_done: int = 0
var health: int = 0
## Input bits from the previous tick, for press detection.
var prev_input: int = 0
## A pressed move waiting for the fighter to become free, and how long it has waited.
var buffered: int = MoveSet.NONE
var buffer_age: int = 0
var stamina: int = 0
## Ticks until stamina starts regenerating again.
var regen_wait: int = 0
## 1 after stamina ran out, until it recovers to MoveSet.exhaust_recover.
var exhausted: int = 0
## Extra startup/recovery ticks on the current move (set when it started while exhausted).
var slow: int = 0
## Ticks left in which a landed hit counts as a counter hit (after a parry).
var counter: int = 0
## Recent damage; knocks the fighter down when it reaches MoveSet.knockdown_threshold.
var knock_meter: int = 0
## Knockdowns this round.
var knockdowns: int = 0
## 1 if the last hit this fighter took was a counter hit (for the HUD); cleared by the next hit.
var took_counter: int = 0


## Fresh fighter for the start of a round.
func reset(moves: MoveSet) -> void:
	action = IDLE
	move = MoveSet.NONE
	frame = 0
	stun = 0
	hit_done = 0
	health = moves.max_health
	buffered = MoveSet.NONE
	buffer_age = 0
	stamina = moves.max_stamina
	regen_wait = 0
	exhausted = 0
	slow = 0
	counter = 0
	knock_meter = 0
	knockdowns = 0
	took_counter = 0


func pack_into(out: PackedInt64Array, at: int) -> void:
	out[at] = action
	out[at + 1] = move
	out[at + 2] = frame
	out[at + 3] = stun
	out[at + 4] = hit_done
	out[at + 5] = health
	out[at + 6] = prev_input
	out[at + 7] = buffered
	out[at + 8] = buffer_age
	out[at + 9] = stamina
	out[at + 10] = regen_wait
	out[at + 11] = exhausted
	out[at + 12] = slow
	out[at + 13] = counter
	out[at + 14] = knock_meter
	out[at + 15] = knockdowns
	out[at + 16] = took_counter


func unpack_from(src: PackedInt64Array, at: int) -> void:
	action = src[at]
	move = src[at + 1]
	frame = src[at + 2]
	stun = src[at + 3]
	hit_done = src[at + 4]
	health = src[at + 5]
	prev_input = src[at + 6]
	buffered = src[at + 7]
	buffer_age = src[at + 8]
	stamina = src[at + 9]
	regen_wait = src[at + 10]
	exhausted = src[at + 11]
	slow = src[at + 12]
	counter = src[at + 13]
	knock_meter = src[at + 14]
	knockdowns = src[at + 15]
	took_counter = src[at + 16]
