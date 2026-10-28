extends Node
## Scene paths and the settings the menu passes to a match (autoload "Game").

const MENU := "res://ui/main_menu.tscn"
const LOCAL_MATCH := "res://game/local_match.tscn"
const ONLINE_MATCH := "res://game/online_match.tscn"

## P2 in the next local match: an AISource.Level, or -1 for a second human on this device.
var p2_control: int = AISource.Level.NORMAL


func goto(scene: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene)
