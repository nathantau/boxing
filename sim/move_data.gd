class_name MoveData
extends Resource
## Frame data for one attack or dodge. Frames are 60 Hz sim ticks; damage is in health points.
## For dodges, `active` is the invulnerable window and `recovery` is the punishable tail.

@export var startup: int = 0
@export var active: int = 0
@export var recovery: int = 0
@export var stamina_cost: int = 0

@export_group("Attack")
@export var damage: int = 0
## Damage dealt through a block.
@export var chip_damage: int = 0
## Stamina the defender loses when blocking this.
@export var block_stamina_damage: int = 0
@export var hitstun: int = 0
@export var blockstun: int = 0
## Which defender dodge directions avoid this punch (defender's own left/right).
@export_flags("Dodge Left:32", "Dodge Right:64") var dodged_by: int = 0
## Bonus damage when the defender is caught in dodge recovery (a whiffed dodge).
@export var dodge_punish_damage: int = 0
## Parry window: the defender parries by starting any punch from this many ticks before
## this move's first active frame up to and including that frame.
@export var parry_window: int = 0
## How long the attacker is staggered after being parried.
@export var parry_stagger: int = 0


func total() -> int:
	return startup + active + recovery
