extends TestCase


func test_sanitize_rejects_non_finite() -> void:
	assert_eq(ArenaSim.sanitize_move(Vector2(NAN, 1.0)), Vector2.ZERO)
	assert_eq(ArenaSim.sanitize_move(Vector2(INF, 0.0)), Vector2.ZERO)


func test_sanitize_clamps_length() -> void:
	assert_near(ArenaSim.sanitize_move(Vector2(100.0, 0.0)).length(), 1.0)
	assert_eq(ArenaSim.sanitize_move(Vector2(0.5, 0.0)), Vector2(0.5, 0.0))


func test_2d_cannot_exceed_speed_even_with_cheating_input() -> void:
	var s := ArenaSim.State2D.new()
	for i: int in 120:
		ArenaSim.step_2d(s, Vector2(1000.0, 0.0), 1.0 / 60.0)
	assert_true(s.velocity.length() <= ArenaSim.SPEED_2D + 0.001, "speed %f" % s.velocity.length())


func test_2d_stays_in_bounds() -> void:
	var s := ArenaSim.State2D.new()
	for i: int in 600:
		ArenaSim.step_2d(s, Vector2(1.0, 1.0), 1.0 / 60.0)
	var b: Rect2 = ArenaSim.BOUNDS_2D
	assert_true(s.position.x >= b.position.x and s.position.x <= b.end.x
			and s.position.y >= b.position.y and s.position.y <= b.end.y, "pos %s" % str(s.position))
	assert_eq(s.velocity, Vector2.ZERO, "velocity into walls should be zeroed")


func test_3d_jump_lands_back_on_floor() -> void:
	var s := ArenaSim.State3D.new()
	ArenaSim.step_3d(s, Vector2.ZERO, true, 1.0 / 60.0)
	assert_false(s.on_floor, "should be airborne after jump")
	assert_true(s.position.y > 0.0)
	for i: int in 120:
		ArenaSim.step_3d(s, Vector2.ZERO, false, 1.0 / 60.0)
	assert_true(s.on_floor, "should land within 2s")
	assert_near(s.position.y, 0.0)


func test_3d_no_double_jump() -> void:
	var s := ArenaSim.State3D.new()
	ArenaSim.step_3d(s, Vector2.ZERO, true, 1.0 / 60.0)
	var vy: float = s.velocity.y
	ArenaSim.step_3d(s, Vector2.ZERO, true, 1.0 / 60.0)
	assert_true(s.velocity.y < vy, "second jump must not add speed")


func test_facing_keeps_previous_when_still() -> void:
	var prev := Quaternion(Vector3.UP, 1.0)
	assert_eq(ArenaSim.facing_from_velocity(Vector3.ZERO, prev), prev)
