class_name AnimationPicker
## Maps a fighter's sim state to [clip name, seconds into that clip]. Pure and stateless, so the
## pose is always a function of the state: rollbacks fix it on the next frame.
##
## Attacks and dodges are time-stretched around a key moment (ClipTimings): the clip's windup
## plays over the move's startup frames, the key moment holds through the active frames, and the
## rest of the clip plays over recovery. Reactions are stretched over their stun duration.

const IDLE := "idle"
const TIRED := "tired"
const JAB := "jab"
const CROSS := "cross"
const HOOK_L := "hook_l"
const HOOK_R := "hook_r"
const UPPERCUT := "uppercut"
const BLOCK := "block"
const PARRY := "parry"
const DODGE_L := "dodge_l"
const DODGE_R := "dodge_r"
const HIT := "hit"
const STAGGER := "stagger"
const KNOCKDOWN := "knockdown"
const GET_UP := "get_up"
const KO := "ko"

## Every clip the rig looks for, in res://art/boxer/anims/<name>.fbx (or .glb).
const CLIPS := [IDLE, TIRED, JAB, CROSS, HOOK_L, HOOK_R, UPPERCUT, BLOCK, PARRY, DODGE_L, DODGE_R, HIT, STAGGER, KNOCKDOWN, GET_UP, KO]
## Clips that loop.
const LOOPING := [IDLE, TIRED]
## Optional clips and what to use when they're missing.
const FALLBACKS := { CROSS: JAB, TIRED: IDLE, PARRY: BLOCK, STAGGER: HIT, KO: KNOCKDOWN, GET_UP: "" }

const SECONDS_PER_TICK := 1.0 / Sim.TICK_RATE


## lengths: clip name -> length in seconds, for the clips that were loaded.
static func pick(f: FighterState, tick: int, moves: MoveSet, lengths: Dictionary, timings: ClipTimings) -> Array:
	match f.action:
		FighterState.ATTACK:
			var clip: String = { MoveSet.JAB: JAB, MoveSet.CROSS: CROSS, MoveSet.HOOK_L: HOOK_L, MoveSet.HOOK_R: HOOK_R }.get(f.move, UPPERCUT)
			var impact := timings.jab_impact if clip == JAB or clip == CROSS else (timings.uppercut_impact if clip == UPPERCUT else timings.hook_impact)
			return _stretched(clip, f, moves.get_move(f.move), impact, lengths)
		FighterState.DODGE:
			var clip := DODGE_L if f.move == MoveSet.DODGE_L else DODGE_R
			return _stretched(clip, f, moves.get_move(f.move), timings.dodge_peak, lengths)
		FighterState.BLOCK:
			return _clip(BLOCK, minf(f.frame * SECONDS_PER_TICK, timings.block_up), lengths)
		FighterState.BLOCKSTUN:
			return _clip(BLOCK, timings.block_up, lengths)
		FighterState.PARRY:
			return _over_stun(PARRY, f, lengths)
		FighterState.HITSTUN:
			return _over_stun(HIT, f, lengths)
		FighterState.STAGGER:
			return _over_stun(STAGGER, f, lengths)
		FighterState.KNOCKDOWN:
			if f.stun <= timings.get_up_ticks and _resolve(GET_UP, lengths) != "":
				var progress := 1.0 - f.stun / float(maxi(timings.get_up_ticks, 1))
				return _clip(GET_UP, progress * lengths.get(GET_UP, 0.0), lengths)
			return _clip(KNOCKDOWN, f.frame * SECONDS_PER_TICK, lengths)
		FighterState.KO:
			return _clip(KO, f.frame * SECONDS_PER_TICK, lengths)
	var loop := TIRED if f.exhausted else IDLE
	var name := _resolve(loop, lengths)
	var length: float = lengths.get(name, 0.0)
	return [name, fmod(tick * SECONDS_PER_TICK, length) if length > 0.0 else 0.0]


## Windup over startup, hold the key moment while active, follow-through over recovery.
static func _stretched(clip: String, f: FighterState, m: MoveData, key: float, lengths: Dictionary) -> Array:
	var name := _resolve(clip, lengths)
	var length: float = lengths.get(name, 0.0)
	key = minf(key, length)
	var startup := Sim.startup_of(f, m)
	var t: float
	if f.frame < startup:
		t = key * (f.frame + 1) / float(startup)
	elif f.frame < startup + m.active:
		t = key
	else:
		t = key + (length - key) * (f.frame - startup - m.active + 1) / float(maxi(Sim.recovery_of(f, m), 1))
	return [name, clampf(t, 0.0, length)]


## Plays the whole clip over the time the fighter is stuck in this action.
static func _over_stun(clip: String, f: FighterState, lengths: Dictionary) -> Array:
	var name := _resolve(clip, lengths)
	var total := f.frame + f.stun
	return [name, lengths.get(name, 0.0) * f.frame / float(maxi(total, 1))]


static func _clip(clip: String, t: float, lengths: Dictionary) -> Array:
	var name := _resolve(clip, lengths)
	return [name, clampf(t, 0.0, lengths.get(name, 0.0))]


## The clip itself if loaded, otherwise its fallback (and the fallback's fallback).
static func _resolve(clip: String, lengths: Dictionary) -> String:
	while clip != "" and not lengths.has(clip):
		clip = FALLBACKS.get(clip, "")
	return clip
