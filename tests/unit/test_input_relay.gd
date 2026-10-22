extends TestCase
## Server-side input handling that doesn't need a network.


func test_held_input_is_kept_within_timeout() -> void:
	var r := InputRelay.new()
	r.accept_input(Vector2.RIGHT, true)
	r.age_input(Protocol.INPUT_TIMEOUT * 0.5)
	assert_eq(r.move, Vector2.RIGHT)
	assert_true(r.jump)
	r.free()


func test_stale_input_is_released() -> void:
	var r := InputRelay.new()
	r.accept_input(Vector2.RIGHT, true)
	for i: int in 20:  # 20 physics ticks > INPUT_TIMEOUT
		r.age_input(1.0 / 60.0)
	assert_eq(r.move, Vector2.ZERO)
	assert_false(r.jump)
	r.free()


func test_new_input_restarts_timeout() -> void:
	var r := InputRelay.new()
	r.accept_input(Vector2.RIGHT, false)
	r.age_input(Protocol.INPUT_TIMEOUT * 0.9)
	r.accept_input(Vector2.UP, false)
	r.age_input(Protocol.INPUT_TIMEOUT * 0.9)
	assert_eq(r.move, Vector2.UP)
	r.free()


func test_accepted_input_is_sanitized() -> void:
	var r := InputRelay.new()
	r.accept_input(Vector2(10, 0), false)
	assert_near(r.move.length(), 1.0)
	r.free()
