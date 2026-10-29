extends Node3D
## The live 3D scene behind the main menu: the arena, a boxer idling under the ring light,
## and a camera drifting slowly around them.

const ARENA := preload("res://game/presentation/arena.tscn")
const MOVES := preload("res://sim/moves.tres")
## Boxer stands right of centre so the menu on the left doesn't cover him.
const BOXER_POS := Vector3(0.5, 0.0, -1.6)
const DRIFT_SPEED := 0.06
const ORBIT_RADIUS := 3.6  # keeps the camera inside the ropes

var _camera: Camera3D
var _rig: CharacterRig
var _idle := FighterState.new()
var _tick := 0
var _time := 0.0


func _ready() -> void:
	add_child(ARENA.instantiate())
	var model := CharacterRig.find_model("boxer")
	if model != "":
		_rig = CharacterRig.new()
		add_child(_rig)
		if _rig.setup(model):
			_rig.position = BOXER_POS
			_rig.rotation.y = PI  # face the camera
		else:
			_rig.queue_free()
			_rig = null
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	_time += delta
	_tick += 1
	if _rig != null:
		_rig.show_state(_idle, _tick, MOVES)
	# A slow sway in front of the boxer, looking slightly up at him like a broadcast hero shot.
	var angle := sin(_time * DRIFT_SPEED * TAU) * 0.35
	var eye := BOXER_POS + Vector3(sin(angle) * ORBIT_RADIUS - 1.4, 1.1, cos(angle) * ORBIT_RADIUS)
	_camera.look_at_from_position(eye, BOXER_POS + Vector3(-1.3, 1.15, 0.0))
