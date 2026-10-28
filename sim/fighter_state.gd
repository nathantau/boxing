class_name FighterState
## Simulated state of one boxer. Ints only: this is exactly what rollback saves and restores.

enum { IDLE, ATTACK, BLOCK, DODGE, HITSTUN, BLOCKSTUN, KO }

## Number of ints written by pack_into(); bump when adding a field.
const SIZE := 9

var action: int = IDLE
## Current attack or dodge (MoveSet.JAB, ...), NONE otherwise.
var move: int = MoveSet.NONE
## Ticks spent in the current action, starting at 0.
var frame: int = 0
## Remaining hitstun/blockstun ticks.
var stun: int = 0
## 1 once the current attack has hit or been blocked, so it connects only once.
var hit_done: int = 0
var health: int = 0
## Input bits from the previous tick, for press detection.
var prev_input: int = 0
## A pressed move waiting for the fighter to become free, and how long it has waited.
var buffered: int = MoveSet.NONE
var buffer_age: int = 0


func reset(max_health: int) -> void:
	action = IDLE
	move = MoveSet.NONE
	frame = 0
	stun = 0
	hit_done = 0
	health = max_health
	buffered = MoveSet.NONE
	buffer_age = 0


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
