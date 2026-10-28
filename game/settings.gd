extends Node
## Player preferences (autoload "Settings"), saved in user://settings.cfg under [game].
## Assigning a value saves it immediately.

const PATH := "user://settings.cfg"
const SECTION := "game"

enum Shield { CENTER, LEFT, RIGHT }

## Swipe distance multipliers for Low / Normal / High sensitivity.
const SWIPE_SENSITIVITY_SCALE := [1.4, 1.0, 0.7]

var haptics := true:
	set(v): haptics = v; _save()
## Online input delay in ticks (each tick is 1/60 s).
var input_delay := 2:
	set(v): input_delay = v; _save()
## 0 low, 1 normal, 2 high.
var swipe_sensitivity := 1:
	set(v): swipe_sensitivity = v; _save()
## true: swiping right throws the left hook (the fist's path). false: swiping right throws the right hook.
var hooks_follow_fist := true:
	set(v): hooks_follow_fist = v; _save()
var shield_position := Shield.CENTER:
	set(v): shield_position = v; _save()
var show_touch_zones := true:
	set(v): show_touch_zones = v; _save()
var show_debug := not OS.has_feature("mobile"):
	set(v): show_debug = v; _save()

var _loading := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	_loading = true
	for key: String in ["haptics", "input_delay", "swipe_sensitivity", "hooks_follow_fist", "shield_position", "show_touch_zones", "show_debug"]:
		if cfg.has_section_key(SECTION, key):
			set(key, cfg.get_value(SECTION, key))
	_loading = false


func swipe_distance_scale() -> float:
	return SWIPE_SENSITIVITY_SCALE[clampi(swipe_sensitivity, 0, 2)]


func _save() -> void:
	if _loading:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keep other sections (e.g. the last joined address)
	for key: String in ["haptics", "input_delay", "swipe_sensitivity", "hooks_follow_fist", "shield_position", "show_touch_zones", "show_debug"]:
		cfg.set_value(SECTION, key, get(key))
	cfg.save(PATH)
