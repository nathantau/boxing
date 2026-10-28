class_name ClipTimings
extends Resource
## Where the key moment is in each downloaded animation, in seconds from the clip's start.
## Attack clips are time-stretched so this moment lands exactly on the move's first active
## frame; tune these after importing new clips (scrub the clip in the editor to find the moment
## the fist is fully extended / the dodge is fully out / the guard is up).

@export var jab_impact := 0.25
@export var hook_impact := 0.35
@export var uppercut_impact := 0.4
@export var dodge_peak := 0.3
@export var block_up := 0.2
@export var parry_impact := 0.15
## How long the get-up clip should take, in sim ticks, at the end of a knockdown.
@export var get_up_ticks := 60
