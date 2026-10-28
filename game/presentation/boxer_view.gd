class_name BoxerView
extends Node3D
## Placeholder capsule boxer. The pose is a pure function of the sim state, so it is
## correct on the next frame after any rollback. Local forward is -Z and local left is -X.

const GUARD_L := Vector3(-0.22, 1.35, -0.3)
const GUARD_R := Vector3(0.22, 1.35, -0.3)
const BLOCK_L := Vector3(-0.12, 1.55, -0.35)
const BLOCK_R := Vector3(0.12, 1.55, -0.35)
const REACH := 0.75
const DODGE_SHIFT := 0.45
const HIT_TINT := Color(1.0, 0.25, 0.2)

@export var color: Color = Color(0.2, 0.4, 0.9)

@onready var _body: Node3D = $Body
@onready var _glove_l: Node3D = $Body/GloveL
@onready var _glove_r: Node3D = $Body/GloveR
@onready var _body_mesh: MeshInstance3D = $Body/Torso

var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.albedo_color = color
	for mesh: MeshInstance3D in [_body_mesh, $Body/Head as MeshInstance3D]:
		mesh.material_override = _material


func show_state(f: FighterState, moves: MoveSet) -> void:
	var glove_l := GUARD_L
	var glove_r := GUARD_R
	var shift := 0.0
	var lean := Vector3.ZERO  # x = pitch (back is +), z = roll
	var tint := color

	match f.action:
		FighterState.ATTACK:
			var t := _extension(f, moves.get_move(f.move))
			match f.move:
				MoveSet.JAB:
					glove_l = GUARD_L.lerp(Vector3(-0.08, 1.45, -0.3 - REACH), t)
				MoveSet.HOOK_L:
					glove_l = _arc(GUARD_L, Vector3(0.1, 1.45, -0.3 - REACH), Vector3(-0.6, 1.45, -0.6), t)
					lean.z = -0.15 * t
				MoveSet.HOOK_R:
					glove_r = _arc(GUARD_R, Vector3(-0.1, 1.45, -0.3 - REACH), Vector3(0.6, 1.45, -0.6), t)
					lean.z = 0.15 * t
				MoveSet.UPPERCUT:
					glove_r = _arc(GUARD_R, Vector3(0.05, 1.6, -0.3 - REACH * 0.8), Vector3(0.15, 0.9, -0.5), t)
					lean.x = 0.15 * t
		FighterState.DODGE:
			var side := -1.0 if f.move == MoveSet.DODGE_L else 1.0
			shift = side * DODGE_SHIFT * _extension(f, moves.get_move(f.move))
			lean.z = -shift * 0.6
		FighterState.BLOCK, FighterState.BLOCKSTUN:
			glove_l = BLOCK_L
			glove_r = BLOCK_R
			if f.action == FighterState.BLOCKSTUN:
				lean.x = 0.08
		FighterState.HITSTUN:
			var k := clampf(f.stun / 12.0, 0.0, 1.0)
			lean.x = 0.35 * k
			tint = color.lerp(HIT_TINT, k)
		FighterState.KO:
			lean.x = minf(f.frame / 20.0, 1.0) * 1.45

	_body.position = Vector3(shift, 0.0, 0.0)
	_body.rotation = lean
	_glove_l.position = glove_l
	_glove_r.position = glove_r
	_material.albedo_color = tint


## 0 → 1 during startup, 1 while active, 1 → 0 during recovery.
static func _extension(f: FighterState, m: MoveData) -> float:
	if f.frame < m.startup:
		return float(f.frame + 1) / m.startup
	if f.frame < m.startup + m.active:
		return 1.0
	return 1.0 - float(f.frame - m.startup - m.active + 1) / maxi(m.recovery, 1)


## Quadratic curve from guard through a control point to the target, for hooks and uppercuts.
static func _arc(from: Vector3, to: Vector3, control: Vector3, t: float) -> Vector3:
	return from.lerp(control, t).lerp(control.lerp(to, t), t)
