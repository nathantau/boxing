class_name MoveSet
extends Resource
## All balance numbers in one place. Edit res://sim/moves.tres (in the inspector or as text) to tune.
## Times are 60 Hz ticks.

## CROSS is last so the older ids (stored in match state) keep their values.
enum { NONE, JAB, HOOK_L, HOOK_R, UPPERCUT, DODGE_L, DODGE_R, CROSS }

@export var max_health: int = 1000
## Ticks after pressing block before it protects.
@export var block_startup: int = 2
## A press made this many ticks before the fighter can act still comes out.
@export var input_buffer: int = 8

@export_group("Stamina")
@export var max_stamina: int = 1000
@export var stamina_regen: int = 5
## Ticks after spending stamina before it starts to regenerate.
@export var stamina_regen_delay: int = 30
## Once exhausted (stamina hit 0), a fighter stays exhausted until stamina is back to this.
@export var exhaust_recover: int = 350
## Extra startup and recovery ticks on every move while exhausted. Blocking also fails.
@export var exhausted_slow: int = 6

@export_group("Parry")
## How long the parry animation lasts (the parrying fighter can't be hit during it).
@export var parry_ticks: int = 10
## After a parry, hits landed within this many ticks are counter hits.
@export var counter_window: int = 45
@export var counter_bonus_pct: int = 50

@export_group("Knockdown")
## Damage builds a knockdown meter; reaching this knocks the fighter down.
@export var knockdown_threshold: int = 260
## The meter drains this much per tick, so only quick bursts of damage knock down.
@export var knock_decay: int = 2
@export var knockdown_ticks: int = 150
## The third knockdown in a round is a technical knockout.
@export var max_knockdowns: int = 3

@export_group("Rounds")
@export var round_ticks: int = 5400
@export var rounds_to_win: int = 2
@export var intro_ticks: int = 120
@export var round_over_ticks: int = 180

@export_group("Moves")
@export var jab: MoveData
@export var cross: MoveData
@export var hook_l: MoveData
@export var hook_r: MoveData
@export var uppercut: MoveData
@export var dodge_l: MoveData
@export var dodge_r: MoveData


func get_move(move: int) -> MoveData:
	match move:
		JAB: return jab
		CROSS: return cross
		HOOK_L: return hook_l
		HOOK_R: return hook_r
		UPPERCUT: return uppercut
		DODGE_L: return dodge_l
		DODGE_R: return dodge_r
	return null


static func is_dodge(move: int) -> bool:
	return move == DODGE_L or move == DODGE_R
