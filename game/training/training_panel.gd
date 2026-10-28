class_name TrainingPanel
extends CanvasLayer
## Training controls and frame data. The table is computed from moves.tres (advantage assumes the
## punch connects on its first active frame); "Last" is what actually happened, measured live.

const MOVE_NAMES := ["-", "Jab", "Hook L", "Hook R", "Uppercut", "Dodge L", "Dodge R"]

## The TrainingMatch this panel controls.
var training: Node

var _box: PanelContainer
var _content: VBoxContainer
var _toggle: Button
var _dummy: OptionButton
var _slow: CheckButton
var _pause: CheckButton
var _step: Button
var _last: Label
var _table: Label
var _last_counts := [-1, -1]
var _mono := SystemFont.new()


func _ready() -> void:
	layer = 7
	_mono.font_names = PackedStringArray(["Menlo", "Monospace"])
	_box = PanelContainer.new()
	_box.theme = _compact_theme()
	_box.add_to_group(TouchControls.BLOCKER_GROUP)
	_box.resized.connect(_layout)
	add_child(_box)
	var outer := VBoxContainer.new()
	_box.add_child(outer)
	_toggle = Button.new()
	_toggle.text = "TRAINING ▾"
	_toggle.pressed.connect(func() -> void: _set_expanded(not _content.visible))
	outer.add_child(_toggle)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	outer.add_child(_content)
	_dummy = OptionButton.new()
	for name: String in DummySource.MODE_NAMES:
		_dummy.add_item("Dummy: " + name)
	_dummy.item_selected.connect(func(i: int) -> void: training.set_dummy_mode(i as DummySource.Mode))
	_content.add_child(_dummy)
	_check("Refill health", true, func(on: bool) -> void: training.refill_health = on)
	_check("Infinite stamina", false, func(on: bool) -> void: training.infinite_stamina = on)
	_slow = _check("Slow motion ¼  (F5)", false, func(on: bool) -> void: training.set_slow_motion(on))
	_pause = _check("Pause  (F6)", false, func(on: bool) -> void:
		training.paused = on
		_step.disabled = not on)
	var row := HBoxContainer.new()
	_content.add_child(row)
	_step = _button(row, "Step  (F7)", func() -> void: training.step_once())
	_step.disabled = true
	_button(row, "Reload moves  (F9)", func() -> void: training.reload_moves())

	_last = Label.new()
	_last.add_theme_font_size_override("font_size", 17)
	_last.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_last.custom_minimum_size = Vector2(400, 0)
	_last.text = "Throw a punch at the dummy."
	_content.add_child(_last)
	_table = Label.new()
	_table.add_theme_font_override("font", _mono)
	_table.add_theme_font_size_override("font_size", 12)
	_content.add_child(_table)

	get_viewport().size_changed.connect(_layout)
	_set_expanded(not OS.has_feature("mobile"))
	refresh_table.call_deferred()


func toggle_slow() -> void:
	_slow.button_pressed = not _slow.button_pressed


func toggle_pause() -> void:
	_pause.button_pressed = not _pause.button_pressed


func refresh_table() -> void:
	var moves: MoveSet = training.moves
	var lines := PackedStringArray(["move      start act rec  dmg  stam  on hit  on block"])
	for move in [MoveSet.JAB, MoveSet.HOOK_L, MoveSet.HOOK_R, MoveSet.UPPERCUT]:
		var m := moves.get_move(move)
		lines.append("%-9s %5d %3d %3d %4d %5d  %+6d  %+8d" % [MOVE_NAMES[move], m.startup, m.active, m.recovery,
			m.damage, m.stamina_cost, m.advantage_on_hit(), m.advantage_on_block()])
	for move in [MoveSet.DODGE_L, MoveSet.DODGE_R]:
		var m := moves.get_move(move)
		lines.append("%-9s %5d %3d %3d    - %5d  (active = invulnerable)" % [MOVE_NAMES[move], m.startup, m.active, m.recovery, m.stamina_cost])
	_table.text = "\n".join(lines)


func _process(_delta: float) -> void:
	if training == null:
		return
	for i in 2:
		var analyzer: FrameAnalyzer = training.analyzers[i]
		if analyzer.count != _last_counts[i]:
			_last_counts[i] = analyzer.count
			if not analyzer.last.is_empty():
				_last.text = _describe(analyzer.last, i)


func _describe(r: Dictionary, attacker: int) -> String:
	var who := "You" if attacker == 0 else "Dummy"
	var text := "%s: %s — startup %d, active %d, recovery %d — %s" % [
		who, MOVE_NAMES[r.move], r.startup, r.active, r.recovery, r.result.to_upper()]
	if r.damage > 0:
		text += ", %d dmg" % r.damage
	if r.advantage != null:
		var adv: int = r.advantage
		var whose := "you" if attacker == 0 else "dummy"
		text += ", %+d (%s)" % [adv, "%s acts first" % whose if adv > 0 else ("even" if adv == 0 else "punishable")]
	return text


func _set_expanded(on: bool) -> void:
	_content.visible = on
	_toggle.text = "TRAINING ▴" if on else "TRAINING ▾"
	_layout.call_deferred()


func _check(text: String, on: bool, changed: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(changed)
	_content.add_child(c)
	return c


func _button(parent: Control, text: String, pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(pressed)
	parent.add_child(b)
	return b


## Smaller fonts and flat toggles, so the panel doesn't swamp the fight.
static func _compact_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 6
	flat.content_margin_right = 6
	flat.content_margin_top = 2
	flat.content_margin_bottom = 2
	for style: String in ["normal", "pressed", "hover", "focus", "hover_pressed"]:
		t.set_stylebox(style, "CheckButton", flat)
	return t


func _layout() -> void:
	var safe := SafeArea.rect(get_viewport())
	_box.reset_size()
	_box.position = Vector2(safe.end.x - _box.size.x - 8, safe.position.y + safe.size.y * 0.14)
