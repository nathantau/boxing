class_name ResultsPanel
extends CanvasLayer
## End-of-match panel under the HUD's YOU WIN / YOU LOSE banner: round score plus Rematch and Menu.

signal rematch_pressed
signal menu_pressed

var _panel: PanelContainer
var _score: Label
var _status: Label
var _rematch: Button


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	_panel.add_to_group(TouchControls.BLOCKER_GROUP)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)
	_score = Label.new()
	_score.add_theme_font_size_override("font_size", 34)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_score)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(1, 0.75, 0.35))
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_rematch = _button(row, "Rematch", rematch_pressed)
	_button(row, "Menu", menu_pressed)
	visible = false
	get_viewport().size_changed.connect(_layout)


func show_result(state: MatchState, viewer: int, names: PackedStringArray) -> void:
	_score.text = "%s  %d – %d  %s" % [names[viewer], state.wins(viewer), state.wins(1 - viewer), names[1 - viewer]]
	set_status("")
	visible = true
	_layout.call_deferred()


## A line above the buttons, e.g. "Waiting for your opponent…". Disables Rematch while waiting.
func set_status(text: String, waiting := false) -> void:
	_status.text = text
	_status.visible = text != ""
	_rematch.disabled = waiting


func _button(parent: Control, text: String, pressed: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: pressed.emit())
	parent.add_child(b)
	return b


func _layout() -> void:
	var safe := SafeArea.rect(get_viewport())
	_panel.reset_size()
	_panel.position = Vector2(safe.get_center().x - _panel.size.x * 0.5, safe.position.y + safe.size.y * 0.55)
