class_name MatchView
extends Node3D
## Everything you see in a match: arena, boxers, camera, HUD, touch overlay, debug text, the
## MENU button and the end-of-match panel. Purely a view of a MatchState; LocalMatch and
## OnlineMatch drive it.

signal menu_pressed

const ACTION_NAMES := ["idle", "attack", "block", "dodge", "hitstun", "blockstun", "KO", "parry", "stagger", "down"]
const MOVE_NAMES := ["-", "jab", "hook L", "hook R", "uppercut", "dodge L", "dodge R"]

@onready var touch: TouchControls = $TouchLayer/TouchControls
@onready var hud: Hud = $HUDLayer/HUD
@onready var debug_label: Label = $DebugHUD/Label
@onready var results: ResultsPanel = $Results
@onready var _boxers: Array[BoxerView] = [$BoxerA, $BoxerB]
@onready var _camera: CameraRig = $Camera
@onready var fx: MatchFx = $Fx

var moves: MoveSet:
	set(value):
		moves = value
		hud.moves = value
## Which fighter's shoulder the camera is behind.
var viewer := 0

var _menu_button: Button


func _ready() -> void:
	fx.boxers = _boxers
	fx.camera = _camera
	_menu_button = Button.new()
	_menu_button.text = "MENU"
	_menu_button.custom_minimum_size = Vector2(88, 44)
	_menu_button.add_theme_font_size_override("font_size", 18)
	_menu_button.add_to_group(TouchControls.BLOCKER_GROUP)
	_menu_button.pressed.connect(func() -> void: menu_pressed.emit())
	$HUDLayer.add_child(_menu_button)
	get_viewport().size_changed.connect(_place_debug)
	_place_debug()


func set_viewer(player: int) -> void:
	viewer = player
	hud.viewer = player
	fx.viewer = player
	_camera.focus = _boxers[player]
	_camera.target = _boxers[1 - player]
	_camera.snap()


func show_state(state: MatchState) -> void:
	for i in 2:
		_boxers[i].show_state(state.fighters[i], moves, state.tick)
	hud.state = state
	fx.show_state(state, moves)
	var over := state.phase == MatchState.Phase.MATCH_OVER
	if over and not results.visible:
		results.show_result(state, viewer, hud.names)
	elif not over and results.visible:
		results.visible = false


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
	var safe := SafeArea.rect(get_viewport())
	debug_label.position = safe.position + Vector2(16, hud.top_height() + 24)
	_menu_button.position = Vector2(safe.get_center().x - _menu_button.custom_minimum_size.x * 0.5, safe.position.y + hud.top_height() + 6)
