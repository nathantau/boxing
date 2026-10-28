class_name MatchView
extends Node3D
## Everything you see in a match: arena, boxers, camera, HUD, touch overlay and debug text.
## Purely a view of a MatchState; LocalMatch and OnlineMatch drive it.

const ACTION_NAMES := ["idle", "attack", "block", "dodge", "hitstun", "blockstun", "KO", "parry", "stagger", "down"]
const MOVE_NAMES := ["-", "jab", "hook L", "hook R", "uppercut", "dodge L", "dodge R"]

@onready var touch: TouchControls = $TouchLayer/TouchControls
@onready var hud: Hud = $HUDLayer/HUD
@onready var debug_label: Label = $DebugHUD/Label
@onready var _boxers: Array[BoxerView] = [$BoxerA, $BoxerB]
@onready var _camera: CameraRig = $Camera

var moves: MoveSet:
	set(value):
		moves = value
		hud.moves = value
## Which fighter's shoulder the camera is behind.
var viewer := 0


func _ready() -> void:
	get_viewport().size_changed.connect(_place_debug)
	_place_debug()


func set_viewer(player: int) -> void:
	viewer = player
	hud.viewer = player
	_camera.focus = _boxers[player]
	_camera.target = _boxers[1 - player]
	_camera.snap()


func show_state(state: MatchState) -> void:
	for i in 2:
		_boxers[i].show_state(state.fighters[i], moves)
	hud.state = state


## One line per fighter for the debug text.
func fighter_debug_lines(state: MatchState, control_names: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for i in 2:
		var f := state.fighters[i]
		lines.append("P%d %-9s HP %4d  ST %4d%s  %-9s %-8s f%-3d stun %-3d knock %d" % [
			i + 1, control_names[i], f.health, f.stamina, "x" if f.exhausted else " ", ACTION_NAMES[f.action],
			MOVE_NAMES[f.move], f.frame, f.stun, f.knock_meter])
	return lines


func _place_debug() -> void:
	debug_label.position = SafeArea.rect(get_viewport()).position + Vector2(16, hud.top_height() + 24)
