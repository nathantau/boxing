class_name SettingsPanel
extends VBoxContainer
## The settings screen inside the main menu. Every change applies and saves immediately.

signal closed


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_check("Haptics", Settings.haptics, func(on: bool) -> void: Settings.haptics = on)
	_choice("Online input delay", ["0 ticks (0 ms)", "1 tick (17 ms)", "2 ticks (33 ms)", "3 ticks (50 ms)", "4 ticks (67 ms)"],
		clampi(Settings.input_delay, 0, 4), func(i: int) -> void: Settings.input_delay = i)
	_choice("Swipe sensitivity", ["Low", "Normal", "High"], Settings.swipe_sensitivity,
		func(i: int) -> void: Settings.swipe_sensitivity = i)
	_choice("Swipe right throws", ["Left hook (follows the fist)", "Right hook"], 0 if Settings.hooks_follow_fist else 1,
		func(i: int) -> void: Settings.hooks_follow_fist = i == 0)
	_choice("Block button", ["Center", "Left", "Right"], Settings.shield_position,
		func(i: int) -> void: Settings.shield_position = i)
	_check("Show touch zones", Settings.show_touch_zones, func(on: bool) -> void: Settings.show_touch_zones = on)
	_check("Show debug info", Settings.show_debug, func(on: bool) -> void: Settings.show_debug = on)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: closed.emit())
	add_child(back)


func _check(text: String, on: bool, changed: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(changed)
	add_child(c)


func _choice(text: String, options: Array, selected: int, changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var pick := OptionButton.new()
	for option: String in options:
		pick.add_item(option)
	pick.selected = selected
	pick.item_selected.connect(changed)
	row.add_child(pick)
	add_child(row)
