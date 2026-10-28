class_name InputSource
## Turns a device into InputBits for the sim. Call sample() every rendered frame and consume()
## once per sim tick: anything pressed since the last tick is latched, so a tap shorter than a
## tick is never lost, and when several ticks run in one frame a press only shows up in the first.

## Bits currently held down (block, dodge). Subclasses that poll a device override _read() instead.
var held := 0
var _latched := 0


## A one-off input such as a swipe: it shows up for exactly one tick.
func press(bits: int) -> void:
	_latched |= bits


func sample() -> void:
	_latched |= _read()


func consume() -> int:
	var bits := _latched | _read()
	_latched = 0
	return bits


func _read() -> int:
	return held
