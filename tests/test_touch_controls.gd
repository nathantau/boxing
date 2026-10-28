extends GutTest
## Swipe and zone recognition, driven with synthetic touch events on a 1280x720 safe area.

const SAFE := Rect2(0, 0, 1280, 720)
const CENTER := Vector2(640, 300)

var touch: TouchControls


func before_each() -> void:
	touch = TouchControls.new()
	add_child_autofree(touch)
	touch._safe = SAFE
	# Defaults, regardless of what's saved in this machine's settings.
	touch.hooks_follow_fist = true
	touch.swipe_distance_scale = 1.0
	touch.shield_position = Settings.Shield.CENTER


func down(pos: Vector2, index := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = true
	touch._input(e)


func move(pos: Vector2, index := 0) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	touch._input(e)


func up(pos: Vector2, index := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = false
	touch._input(e)


func swipe(path: Array[Vector2]) -> int:
	down(path[0])
	for p in path.slice(1):
		move(p)
	up(path[-1])
	return touch.source.consume()


func test_swipe_up_is_jab() -> void:
	assert_eq(swipe([CENTER, CENTER + Vector2(5, -60)]), InputBits.JAB)


func test_swipe_right_is_left_hook() -> void:
	# Hooks follow the fist: the left hook travels left to right.
	var expected := InputBits.HOOK_L
	assert_eq(swipe([CENTER, CENTER + Vector2(70, -10)]), expected)


func test_diagonal_up_left_is_hook() -> void:
	var expected := InputBits.HOOK_R
	assert_eq(swipe([CENTER, CENTER + Vector2(-50, -40)]), expected)


func test_down_then_up_is_uppercut() -> void:
	down(CENTER)
	move(CENTER + Vector2(0, 50))
	move(CENTER + Vector2(0, 80))
	assert_eq(touch.source.consume(), 0, "nothing fires on the way down")
	move(CENTER + Vector2(0, 30))
	assert_eq(touch.source.consume(), InputBits.UPPERCUT, "fires as soon as the finger comes back up")
	up(CENTER)
	assert_eq(touch.source.consume(), 0, "and only once")


func test_plain_down_swipe_uppercuts_on_release() -> void:
	assert_eq(swipe([CENTER, CENTER + Vector2(0, 60)]), InputBits.UPPERCUT)


func test_tiny_movement_does_nothing() -> void:
	assert_eq(swipe([CENTER, CENTER + Vector2(10, -10)]), 0)


func test_one_punch_per_touch() -> void:
	assert_eq(swipe([CENTER, CENTER + Vector2(0, -60), CENTER + Vector2(120, -60)]), InputBits.JAB)


func test_edges_hold_dodge() -> void:
	down(Vector2(40, 300))
	assert_eq(touch.source.consume(), InputBits.DODGE_L)
	assert_eq(touch.source.consume(), InputBits.DODGE_L, "held, not one-off")
	up(Vector2(40, 300))
	assert_eq(touch.source.consume(), 0)
	down(Vector2(1240, 300))
	assert_eq(touch.source.consume(), InputBits.DODGE_R)


func test_shield_holds_block() -> void:
	down(touch._shield_center())
	assert_eq(touch.source.consume(), InputBits.BLOCK)
	up(touch._shield_center())
	assert_eq(touch.source.consume(), 0)


func test_dodge_and_swipe_with_two_fingers() -> void:
	down(Vector2(40, 300), 0)
	down(CENTER, 1)
	move(CENTER + Vector2(0, -60), 1)
	assert_eq(touch.source.consume(), InputBits.DODGE_L | InputBits.JAB)


func test_hook_direction_setting_flips_hooks() -> void:
	touch.hooks_follow_fist = false
	assert_eq(swipe([CENTER, CENTER + Vector2(70, -10)]), InputBits.HOOK_R)


func test_low_sensitivity_needs_a_longer_swipe() -> void:
	touch.swipe_distance_scale = 2.0
	assert_eq(swipe([CENTER, CENTER + Vector2(0, -50)]), 0)
	assert_eq(swipe([CENTER, CENTER + Vector2(0, -90)]), InputBits.JAB)


func test_shield_can_move_to_a_side() -> void:
	touch.shield_position = Settings.Shield.RIGHT
	assert_gt(touch._shield_center().x, SAFE.get_center().x)
	down(touch._shield_center())
	assert_eq(touch.source.consume(), InputBits.BLOCK, "right-side shield beats the dodge strip")
