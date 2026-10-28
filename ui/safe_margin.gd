class_name SafeMargin
extends MarginContainer
## Keeps its children inside the screen's safe area (clear of the notch, Dynamic Island and home indicator).

@export var padding := 24


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_update)
	_update()


func _update() -> void:
	var full := get_viewport().get_visible_rect()
	var safe := SafeArea.rect(get_viewport())
	add_theme_constant_override("margin_left", int(safe.position.x - full.position.x) + padding)
	add_theme_constant_override("margin_top", int(safe.position.y - full.position.y) + padding)
	add_theme_constant_override("margin_right", int(full.end.x - safe.end.x) + padding)
	add_theme_constant_override("margin_bottom", int(full.end.y - safe.end.y) + padding)
