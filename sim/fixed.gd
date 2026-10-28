class_name Fixed
## Integer helpers for the sim. GDScript int division truncates toward zero on every platform.


## value * percent / 100, e.g. pct(70, 150) == 105.
@warning_ignore("integer_division")
static func pct(value: int, percent: int) -> int:
	return value * percent / 100


## Ticks to whole seconds, rounded up (for the round clock).
@warning_ignore("integer_division")
static func ticks_to_seconds(ticks: int, tick_rate: int) -> int:
	return (ticks + tick_rate - 1) / tick_rate
