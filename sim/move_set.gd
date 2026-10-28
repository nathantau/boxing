class_name MoveSet
extends Resource
## All balance numbers in one place. Edit res://sim/moves.tres (in the inspector or as text) to tune.

enum { NONE, JAB, HOOK_L, HOOK_R, UPPERCUT, DODGE_L, DODGE_R }

@export var max_health: int = 1000
## Ticks after pressing block before it protects.
@export var block_startup: int = 2
## A press made this many ticks before the fighter can act still comes out.
@export var input_buffer: int = 8
## Ticks between a knockout and the fighters resetting.
@export var ko_reset_ticks: int = 180

@export_group("Moves")
@export var jab: MoveData
@export var hook_l: MoveData
@export var hook_r: MoveData
@export var uppercut: MoveData
@export var dodge_l: MoveData
@export var dodge_r: MoveData


func get_move(move: int) -> MoveData:
	match move:
		JAB: return jab
		HOOK_L: return hook_l
		HOOK_R: return hook_r
		UPPERCUT: return uppercut
		DODGE_L: return dodge_l
		DODGE_R: return dodge_r
	return null


static func is_dodge(move: int) -> bool:
	return move == DODGE_L or move == DODGE_R
