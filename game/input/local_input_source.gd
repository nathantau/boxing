class_name LocalInputSource
extends InputSource
## One player's keyboard set plus one gamepad, turned into InputBits.

const P1_KEYS := {
	InputBits.JAB: [KEY_W],
	InputBits.HOOK_L: [KEY_Q],
	InputBits.HOOK_R: [KEY_E],
	InputBits.UPPERCUT: [KEY_S],
	InputBits.BLOCK: [KEY_SPACE],
	InputBits.DODGE_L: [KEY_A],
	InputBits.DODGE_R: [KEY_D],
}

const P2_KEYS := {
	InputBits.JAB: [KEY_I],
	InputBits.HOOK_L: [KEY_U],
	InputBits.HOOK_R: [KEY_O],
	InputBits.UPPERCUT: [KEY_K],
	InputBits.BLOCK: [KEY_P],
	InputBits.DODGE_L: [KEY_J],
	InputBits.DODGE_R: [KEY_L],
}

const PAD_BUTTONS := {
	InputBits.JAB: [JOY_BUTTON_X],
	InputBits.HOOK_L: [JOY_BUTTON_LEFT_SHOULDER],
	InputBits.HOOK_R: [JOY_BUTTON_RIGHT_SHOULDER],
	InputBits.UPPERCUT: [JOY_BUTTON_Y],
	InputBits.BLOCK: [JOY_BUTTON_B],
	InputBits.DODGE_L: [JOY_BUTTON_DPAD_LEFT],
	InputBits.DODGE_R: [JOY_BUTTON_DPAD_RIGHT],
}

const STICK_DEADZONE := 0.6
const TRIGGER_THRESHOLD := 0.5

var _keys: Dictionary
## Index into Input.get_connected_joypads(), so P1 gets the first pad and P2 the second.
var _pad_slot: int


func _init(keys: Dictionary, pad_slot: int) -> void:
	_keys = keys
	_pad_slot = pad_slot


func _read() -> int:
	var bits := 0
	for bit: int in _keys:
		for key: Key in _keys[bit]:
			if Input.is_physical_key_pressed(key):
				bits |= bit

	var pads := Input.get_connected_joypads()
	if _pad_slot < pads.size():
		var device: int = pads[_pad_slot]
		for bit: int in PAD_BUTTONS:
			for button: JoyButton in PAD_BUTTONS[bit]:
				if Input.is_joy_button_pressed(device, button):
					bits |= bit
		var stick_x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if stick_x < -STICK_DEADZONE:
			bits |= InputBits.DODGE_L
		elif stick_x > STICK_DEADZONE:
			bits |= InputBits.DODGE_R
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD:
			bits |= InputBits.BLOCK
	return bits
