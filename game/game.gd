extends Node
## Scene paths and the settings the menu passes to a match (autoload "Game").

const MENU := "res://ui/main_menu.tscn"
const LOCAL_MATCH := "res://game/local_match.tscn"
const ONLINE_MATCH := "res://game/online_match.tscn"
const TRAINING := "res://game/training/training_match.tscn"

## P2 in the next local match: an AISource.Level, or -1 for a second human on this device.
var p2_control: int = AISource.Level.NORMAL


var _fade: ColorRect


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	layer.add_child(_fade)


## Switches scene right away (nothing waits on the fade, which matters for online starts),
## then fades in from black.
func goto(scene: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene)
	_fade.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.05)
	tween.tween_property(_fade, "modulate:a", 0.0, 0.4)
