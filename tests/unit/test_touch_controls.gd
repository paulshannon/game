extends TestCase
## Touch input → the same actions the keyboard presses → Input.get_vector,
## which is exactly what InputRelay sends. Uses synthetic touch events; no
## viewport needed.

const VIEW := Vector2(1280, 720)


func _controls(jump: bool = true) -> TouchControls:
	InputSetup.ensure_actions()
	return TouchControls.new(InputSetup.JUMP if jump else &"")


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e


func _move() -> Vector2:
	return Input.get_vector(InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN)


func _done(c: TouchControls) -> void:
	c.release_all()
	c.free()


func test_stick_value_is_clamped_and_analog() -> void:
	var s := TouchStick.new()
	s.press(Vector2(100, 100))
	s.drag(Vector2(100 + TouchStick.RADIUS * 0.5, 100))
	assert_near(s.value().x, 0.5)
	s.drag(Vector2(100, 100 + TouchStick.RADIUS * 5.0))
	assert_near(s.value().length(), 1.0)
	assert_near(s.value().y, 1.0)
	s.release()
	assert_eq(s.value(), Vector2.ZERO)


func test_full_drag_right_moves_right() -> void:
	var c := _controls()
	assert_true(c.handle_event(_touch(0, Vector2(200, 500), true), VIEW))
	assert_true(c.handle_event(_drag(0, Vector2(200 + TouchStick.RADIUS * 2.0, 500)), VIEW))
	var m: Vector2 = _move()
	assert_near(m.x, 1.0, 0.001)
	assert_near(m.y, 0.0, 0.001)
	_done(c)


func test_half_push_is_slower_than_full() -> void:
	var c := _controls()
	c.handle_event(_touch(0, Vector2(200, 500), true), VIEW)
	c.handle_event(_drag(0, Vector2(200, 500 - TouchStick.RADIUS * 0.6)), VIEW)
	var m: Vector2 = _move()
	assert_true(m.y < -0.1 and m.y > -0.9, "half push gives partial speed, got %s" % m)
	_done(c)


func test_tiny_push_is_inside_dead_zone() -> void:
	var c := _controls()
	c.handle_event(_touch(0, Vector2(200, 500), true), VIEW)
	c.handle_event(_drag(0, Vector2(200 + TouchStick.RADIUS * 0.1, 500)), VIEW)
	assert_eq(_move(), Vector2.ZERO)
	_done(c)


func test_lifting_finger_stops_movement() -> void:
	var c := _controls()
	c.handle_event(_touch(0, Vector2(200, 500), true), VIEW)
	c.handle_event(_drag(0, Vector2(100, 500)), VIEW)
	assert_true(_move().x < -0.5)
	assert_true(c.handle_event(_touch(0, Vector2(100, 500), false), VIEW))
	assert_eq(_move(), Vector2.ZERO)
	_done(c)


func test_move_and_jump_with_two_fingers() -> void:
	var c := _controls(true)
	c.handle_event(_touch(0, Vector2(200, 500), true), VIEW)
	c.handle_event(_drag(0, Vector2(300, 500)), VIEW)
	assert_true(c.handle_event(_touch(1, c.button_center(VIEW), true), VIEW))
	assert_true(Input.is_action_pressed(InputSetup.JUMP))
	assert_true(_move().x > 0.5, "stick still held while jumping")
	c.handle_event(_touch(1, c.button_center(VIEW), false), VIEW)
	assert_false(Input.is_action_pressed(InputSetup.JUMP))
	assert_true(_move().x > 0.5, "releasing jump leaves the stick alone")
	_done(c)


func test_no_jump_button_in_games_without_jump() -> void:
	var c := _controls(false)
	assert_false(c.handle_event(_touch(1, c.button_center(VIEW), true), VIEW))
	assert_false(Input.is_action_pressed(InputSetup.JUMP))
	_done(c)


func test_right_half_touch_is_not_the_stick() -> void:
	var c := _controls()
	assert_false(c.handle_event(_touch(0, Vector2(900, 300), true), VIEW))
	assert_false(c.handle_event(_drag(0, Vector2(1000, 300)), VIEW))
	assert_eq(_move(), Vector2.ZERO)
	_done(c)


func test_other_finger_does_not_steal_the_stick() -> void:
	var c := _controls()
	c.handle_event(_touch(0, Vector2(200, 500), true), VIEW)
	c.handle_event(_drag(0, Vector2(300, 500)), VIEW)
	assert_false(c.handle_event(_touch(2, Vector2(100, 200), true), VIEW))
	assert_false(c.handle_event(_drag(2, Vector2(100, 600)), VIEW))
	assert_true(_move().x > 0.5)
	_done(c)


func test_release_all_lets_go_of_everything() -> void:
	# Focus loss / backgrounding: touch-up events may never arrive.
	var c := _controls()
	c.handle_event(_touch(0, Vector2(200, 500), true), VIEW)
	c.handle_event(_drag(0, Vector2(300, 500)), VIEW)
	c.handle_event(_touch(1, c.button_center(VIEW), true), VIEW)
	c.release_all()
	assert_eq(_move(), Vector2.ZERO)
	assert_false(Input.is_action_pressed(InputSetup.JUMP))
	c.free()


func test_fire_button_presses_fire() -> void:
	InputSetup.ensure_actions()
	var c := TouchControls.new(InputSetup.FIRE)
	assert_true(c.handle_event(_touch(1, c.button_center(VIEW), true), VIEW))
	assert_true(Input.is_action_pressed(InputSetup.FIRE))
	assert_false(Input.is_action_pressed(InputSetup.JUMP), "only the game's own action")
	c.handle_event(_touch(1, c.button_center(VIEW), false), VIEW)
	assert_false(Input.is_action_pressed(InputSetup.FIRE))
	_done(c)


func test_menu_button_presses_menu() -> void:
	var c := _controls()
	assert_true(c.handle_event(_touch(2, TouchControls.MENU_CENTER, true), VIEW))
	assert_true(Input.is_action_pressed(InputSetup.MENU))
	assert_eq(Input.get_vector(InputSetup.LEFT, InputSetup.RIGHT, InputSetup.UP, InputSetup.DOWN),
			Vector2.ZERO, "not the stick, though it's on the left half")
	c.handle_event(_touch(2, TouchControls.MENU_CENTER, false), VIEW)
	assert_false(Input.is_action_pressed(InputSetup.MENU))
	_done(c)
