extends TestCase
## The space game's rules (SpaceSim): pure functions, no scene tree.

const DT: float = 1.0 / 60.0


func _ship() -> SpaceSim.Ship:
	var s := SpaceSim.Ship.new()
	s.rotation = 0.0  # facing +x
	return s


func _run(s: SpaceSim.Ship, move: Vector2, seconds: float, fire: bool = false) -> int:
	var shots: int = 0
	for i: int in roundi(seconds / DT):
		if SpaceSim.step_ship(s, move, fire, DT):
			shots += 1
	return shots


func test_thrust_accelerates_along_facing() -> void:
	var s := _ship()
	_run(s, Vector2.UP, 0.5)
	assert_true(s.velocity.x > 100.0, "forward is +x when facing 0, got %s" % s.velocity)
	assert_near(s.velocity.y, 0.0, 0.001)
	assert_true(s.thrusting)


func test_momentum_carries_on_after_thrust() -> void:
	var s := _ship()
	_run(s, Vector2.UP, 0.5)
	var speed: float = s.velocity.length()
	var x: float = s.position.x
	_run(s, Vector2.ZERO, 0.5)
	assert_false(s.thrusting)
	assert_true(s.position.x > x + 50.0, "keeps drifting without thrust")
	assert_true(s.velocity.length() < speed, "drag slows it a little")
	assert_true(s.velocity.length() > speed * 0.6, "but keeps most of its momentum")


func test_speed_is_capped() -> void:
	var s := _ship()
	s.position = Vector2(-500, 0)
	_run(s, Vector2.UP, 3.0)
	assert_true(s.velocity.length() <= SpaceSim.MAX_SPEED + 0.001)


func test_turning_rotates_without_moving() -> void:
	var s := _ship()
	_run(s, Vector2.RIGHT, 0.25)
	assert_near(s.rotation, SpaceSim.TURN_SPEED * 0.25, 0.01)
	assert_eq(s.velocity, Vector2.ZERO)


func test_bounces_off_the_edge() -> void:
	var s := _ship()
	s.position = Vector2(SpaceSim.BOUNDS.end.x - SpaceSim.SHIP_RADIUS - 1.0, 0)
	s.velocity = Vector2(300, 0)
	SpaceSim.step_ship(s, Vector2.ZERO, false, DT)
	assert_true(s.velocity.x < 0.0, "velocity reflected")
	assert_true(SpaceSim.BOUNDS.grow(-SpaceSim.SHIP_RADIUS + 0.01).has_point(s.position))


func test_bad_input_is_sanitized() -> void:
	var s := _ship()
	SpaceSim.step_ship(s, Vector2(NAN, INF), false, DT)
	assert_true(s.position.is_finite() and s.velocity.is_finite())
	_run(s, Vector2(0, -1000), 0.1)
	var t := _ship()
	_run(t, Vector2.UP, 0.1)
	assert_near(s.velocity.length(), t.velocity.length(), 0.01, "a huge stick is a full stick")


func test_fire_respects_cooldown() -> void:
	var s := _ship()
	var shots: int = _run(s, Vector2.ZERO, 1.0, true)
	assert_eq(shots, 4, "one shot per FIRE_COOLDOWN")


func test_rapid_fire_shoots_faster_then_wears_off() -> void:
	var s := _ship()
	SpaceSim.apply_pickup(s, SpaceSim.RAPID)
	assert_true(_run(s, Vector2.ZERO, 1.0, true) >= 9)
	_run(s, Vector2.ZERO, SpaceSim.RAPID_TIME)
	assert_eq(_run(s, Vector2.ZERO, 1.0, true), 4)


func test_shot_starts_at_nose_and_keeps_ship_momentum() -> void:
	var s := _ship()
	s.velocity = Vector2(0, 100)
	assert_eq(SpaceSim.shot_origin(s), Vector2(SpaceSim.MUZZLE, 0))
	assert_eq(SpaceSim.shot_velocity(s), Vector2(SpaceSim.SHOT_SPEED, 100))


func test_shot_expires_by_age_or_leaving_the_field() -> void:
	var v := Vector2(SpaceSim.SHOT_SPEED, 0)
	assert_false(SpaceSim.shot_expired(Vector2(-500, 0), v, 0.5))
	assert_true(SpaceSim.shot_expired(Vector2(-500, 0), v, SpaceSim.SHOT_LIFE))
	assert_true(SpaceSim.shot_expired(Vector2(550, 0), v, 0.2), "left the field")


func test_asteroid_moves_in_a_line_then_bounces() -> void:
	var size: int = SpaceSim.LARGE
	var p0 := Vector2(0, 0)
	var v := Vector2(100, 0)
	assert_eq(SpaceSim.asteroid_position(p0, v, 1.0, size), Vector2(100, 0))
	var wall: float = SpaceSim.BOUNDS.end.x - SpaceSim.asteroid_radius(size)
	# Travels to the wall, then comes back the same distance it overshot.
	var t: float = (wall + 50.0) / 100.0
	assert_near(SpaceSim.asteroid_position(p0, v, t, size).x, wall - 50.0, 0.01)


func test_asteroid_stays_inside_forever() -> void:
	var size: int = SpaceSim.SMALL
	var r: Rect2 = SpaceSim.BOUNDS.grow(-SpaceSim.asteroid_radius(size) + 0.01)
	for i: int in 200:
		var p: Vector2 = SpaceSim.asteroid_position(Vector2(10, -20), Vector2(173, -91), i * 7.3, size)
		assert_true(r.has_point(p), "at %d: %s" % [i, p])


func test_asteroid_path_is_continuous() -> void:
	# Interpolating clients sample it every frame: no jumps at the bounces.
	var prev: Vector2 = SpaceSim.asteroid_position(Vector2.ZERO, Vector2(240, 130), 0.0, SpaceSim.MEDIUM)
	for i: int in range(1, 2000):
		var p: Vector2 = SpaceSim.asteroid_position(Vector2.ZERO, Vector2(240, 130), i * DT, SpaceSim.MEDIUM)
		assert_true(p.distance_to(prev) <= 275.0 * DT + 0.01, "jump at tick %d" % i)
		prev = p


func test_split_gives_two_faster_smaller_pieces() -> void:
	var v := Vector2(50, 0)
	var parts: Array[Vector2] = SpaceSim.split_velocities(SpaceSim.LARGE, v)
	assert_eq(parts.size(), 2)
	for p: Vector2 in parts:
		assert_near(p.length(), 50.0 * SpaceSim.SPLIT_SPEEDUP, 0.01)
	assert_true(parts[0].y * parts[1].y < 0.0, "one each side")
	assert_true(SpaceSim.split_velocities(SpaceSim.SMALL, v).is_empty())


func test_smaller_asteroids_are_worth_more() -> void:
	assert_true(SpaceSim.asteroid_points(SpaceSim.SMALL) > SpaceSim.asteroid_points(SpaceSim.MEDIUM))
	assert_true(SpaceSim.asteroid_points(SpaceSim.MEDIUM) > SpaceSim.asteroid_points(SpaceSim.LARGE))
	assert_eq(SpaceSim.asteroid_points(99), SpaceSim.asteroid_points(SpaceSim.LARGE), "clamped")


func test_hit_destroys_ship_and_it_respawns_protected() -> void:
	var s := _ship()
	s.position = Vector2(100, 100)
	assert_true(SpaceSim.hit_ship(s, Vector2(5, 5)))
	assert_false(s.alive)
	assert_eq(s.position, Vector2(5, 5), "parked at its spawn point while dead")
	assert_eq(_run(s, Vector2.UP, 0.5, true), 0, "dead ships neither move nor shoot")
	assert_false(SpaceSim.can_respawn(s))
	_run(s, Vector2.ZERO, SpaceSim.RESPAWN_TIME)
	assert_true(SpaceSim.can_respawn(s))
	SpaceSim.respawn(s, Vector2(5, 5))
	assert_true(s.alive)
	assert_false(SpaceSim.hit_ship(s, Vector2.ZERO), "spawn protection")
	_run(s, Vector2.ZERO, SpaceSim.SPAWN_PROTECTION + DT)
	assert_true(SpaceSim.can_be_hit(s))


func test_shield_absorbs_one_hit() -> void:
	var s := _ship()
	SpaceSim.apply_pickup(s, SpaceSim.SHIELD)
	assert_false(SpaceSim.hit_ship(s, Vector2.ZERO))
	assert_true(s.alive)
	assert_false(s.shield)
	assert_false(SpaceSim.hit_ship(s, Vector2.ZERO), "brief grace after the shield breaks")
	_run(s, Vector2.ZERO, SpaceSim.SHIELD_GRACE + DT)
	assert_true(SpaceSim.hit_ship(s, Vector2.ZERO))


func test_star_pickup_scores() -> void:
	var s := _ship()
	SpaceSim.apply_pickup(s, SpaceSim.STAR)
	assert_eq(s.score, SpaceSim.STAR_POINTS)


func test_overlap() -> void:
	assert_true(SpaceSim.overlaps(Vector2.ZERO, 10.0, Vector2(15, 0), 5.0))
	assert_false(SpaceSim.overlaps(Vector2.ZERO, 10.0, Vector2(15.1, 0), 5.0))
