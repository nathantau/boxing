class_name CameraRig
extends Camera3D
## Over-the-shoulder camera: behind and above `focus`, looking at `target`.

const OFFSET := Vector3(1.25, 1.9, 2.6)
const LOOK_HEIGHT := 1.2
## Aim this far to the right of the opponent so our own boxer sits lower-left, out of the way.
const LOOK_SIDE := 0.3
const FOLLOW_SPEED := 12.0
## Camera shake: trauma (0..1) decays per second; shake strength is trauma squared.
const TRAUMA_DECAY := 2.2
const MAX_SHAKE_OFFSET := 0.08
const MAX_SHAKE_ROLL := 0.04

var focus: Node3D
var target: Node3D

var _trauma := 0.0
var _shake_time := 0.0


## Visual only (not simulated), so it's fine that it uses floats and real time.
func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func snap() -> void:
	global_position = _desired_position()
	look_at(_look_point())


func _process(delta: float) -> void:
	if focus == null or target == null:
		return
	global_position = global_position.lerp(_desired_position(), minf(1.0, FOLLOW_SPEED * delta))
	look_at(_look_point())
	if _trauma > 0.0:
		_shake_time += delta * 40.0
		var shake := _trauma * _trauma
		h_offset = sin(_shake_time * 1.3) * MAX_SHAKE_OFFSET * shake
		v_offset = sin(_shake_time * 1.7 + 1.0) * MAX_SHAKE_OFFSET * shake
		rotate_object_local(Vector3.FORWARD, sin(_shake_time * 0.9 + 2.0) * MAX_SHAKE_ROLL * shake)
		_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)
	else:
		h_offset = 0.0
		v_offset = 0.0


func _desired_position() -> Vector3:
	return focus.global_transform * OFFSET


func _look_point() -> Vector3:
	return target.global_position + Vector3.UP * LOOK_HEIGHT + focus.global_basis.x * LOOK_SIDE
