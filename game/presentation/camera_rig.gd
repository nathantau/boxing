class_name CameraRig
extends Camera3D
## Over-the-shoulder camera: behind and above `focus`, looking at `target`.

const OFFSET := Vector3(1.25, 1.9, 2.6)
const LOOK_HEIGHT := 1.2
## Aim this far to the right of the opponent so our own boxer sits lower-left, out of the way.
const LOOK_SIDE := 0.3
const FOLLOW_SPEED := 12.0

var focus: Node3D
var target: Node3D


func snap() -> void:
	global_position = _desired_position()
	look_at(_look_point())


func _process(delta: float) -> void:
	if focus == null or target == null:
		return
	global_position = global_position.lerp(_desired_position(), minf(1.0, FOLLOW_SPEED * delta))
	look_at(_look_point())


func _desired_position() -> Vector3:
	return focus.global_transform * OFFSET


func _look_point() -> Vector3:
	return target.global_position + Vector3.UP * LOOK_HEIGHT + focus.global_basis.x * LOOK_SIDE
