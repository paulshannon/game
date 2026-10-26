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


func test_space_has_no_edge() -> void:
	var s := _ship()
	s.position = Vector2(50000, -30000)
	s.velocity = Vector2(300, 0)
	SpaceSim.step_ship(s, Vector2.ZERO, false, DT)
	assert_true(s.velocity.x > 0.0, "keeps going")
	assert_true(s.position.x > 50000.0)


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


func test_shot_expires_by_age() -> void:
	assert_false(SpaceSim.shot_expired(0.5))
	assert_true(SpaceSim.shot_expired(SpaceSim.SHOT_LIFE))


func test_asteroid_drifts_in_a_straight_line() -> void:
	var p0 := Vector2(-20, 30)
	var v := Vector2(100, -40)
	assert_eq(SpaceSim.asteroid_position(p0, v, 0.0), p0)
	assert_eq(SpaceSim.asteroid_position(p0, v, 1.0), Vector2(80, -10))
	assert_near(SpaceSim.asteroid_position(p0, v, 600.0).x, 59980.0, 0.01, "no edge to bounce off")


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
	s.velocity = Vector2(50, 0)
	assert_true(SpaceSim.hit_ship(s))
	assert_false(s.alive)
	assert_eq(s.position, Vector2(100, 100), "stays where it was hit (clients explode it there)")
	assert_eq(_run(s, Vector2.UP, 0.5, true), 0, "dead ships neither move nor shoot")
	assert_eq(s.position, Vector2(100, 100))
	assert_false(SpaceSim.can_respawn(s))
	_run(s, Vector2.ZERO, SpaceSim.RESPAWN_TIME)
	assert_true(SpaceSim.can_respawn(s))
	SpaceSim.respawn(s, Vector2(5, 5))
	assert_true(s.alive)
	assert_eq(s.position, Vector2(5, 5), "moved only when it respawns")
	assert_false(SpaceSim.hit_ship(s), "spawn protection")
	_run(s, Vector2.ZERO, SpaceSim.SPAWN_PROTECTION + DT)
	assert_true(SpaceSim.can_be_hit(s))


func test_shield_absorbs_one_hit() -> void:
	var s := _ship()
	SpaceSim.apply_pickup(s, SpaceSim.SHIELD)
	assert_false(SpaceSim.hit_ship(s))
	assert_true(s.alive)
	assert_false(s.shield)
	assert_false(SpaceSim.hit_ship(s), "brief grace after the shield breaks")
	_run(s, Vector2.ZERO, SpaceSim.SHIELD_GRACE + DT)
	assert_true(SpaceSim.hit_ship(s))


func test_star_pickup_scores() -> void:
	var s := _ship()
	SpaceSim.apply_pickup(s, SpaceSim.STAR)
	assert_eq(s.score, SpaceSim.STAR_POINTS)


func test_overlap() -> void:
	assert_true(SpaceSim.overlaps(Vector2.ZERO, 10.0, Vector2(15, 0), 5.0))
	assert_false(SpaceSim.overlaps(Vector2.ZERO, 10.0, Vector2(15.1, 0), 5.0))


func test_fast_shot_cannot_step_over_a_small_rock() -> void:
	# One tick of a shot from a ship at full speed (~21 px), passing a small
	# rock 15 px off-centre: both end points miss, the path doesn't.
	var step: float = (SpaceSim.SHOT_SPEED + SpaceSim.MAX_SPEED) * DT
	var from := Vector2(-step * 0.5, 15)
	var to := from + Vector2(step, 0)
	var r: float = SpaceSim.asteroid_radius(SpaceSim.SMALL)
	assert_false(SpaceSim.overlaps(from, SpaceSim.SHOT_RADIUS, Vector2.ZERO, r))
	assert_false(SpaceSim.overlaps(to, SpaceSim.SHOT_RADIUS, Vector2.ZERO, r))
	assert_true(SpaceSim.sweep_hits(from, to, SpaceSim.SHOT_RADIUS, Vector2.ZERO, r))


func test_sweep_misses_what_the_path_misses() -> void:
	var r: float = SpaceSim.asteroid_radius(SpaceSim.SMALL)
	assert_false(SpaceSim.sweep_hits(Vector2(-30, 25), Vector2(30, 25), SpaceSim.SHOT_RADIUS, Vector2.ZERO, r))
	assert_false(SpaceSim.sweep_hits(Vector2(30, 0), Vector2(60, 0), SpaceSim.SHOT_RADIUS, Vector2.ZERO, r),
			"rock behind the start")
	assert_true(SpaceSim.sweep_hits(Vector2(5, 0), Vector2(5, 0), SpaceSim.SHOT_RADIUS, Vector2.ZERO, r),
			"zero-length path is a point test")


func test_thruster_state_follows_the_stick() -> void:
	var s := _ship()
	SpaceSim.step_ship(s, Vector2(0, 1), false, DT)
	assert_true(s.braking, "down fires the reverse thrusters")
	assert_false(s.thrusting)
	SpaceSim.step_ship(s, Vector2(-1, 0), false, DT)
	assert_false(s.braking)
	assert_eq(s.turning, -1, "left")
	SpaceSim.step_ship(s, Vector2(0.5, -1), false, DT)
	assert_eq(s.turning, 1, "right")
	assert_true(s.thrusting)
	SpaceSim.step_ship(s, Vector2(0.05, 0.05), false, DT)
	assert_eq(s.turning, 0, "a resting stick fires nothing")
	assert_false(s.braking)


func test_dead_ship_fires_no_thrusters() -> void:
	var s := _ship()
	SpaceSim.step_ship(s, Vector2(1, 1), false, DT)
	SpaceSim.hit_ship(s)
	assert_false(s.braking)
	assert_eq(s.turning, 0)
	SpaceSim.step_ship(s, Vector2(1, 1), false, DT)
	assert_false(s.braking)
	assert_eq(s.turning, 0)


# --- hulls --------------------------------------------------------------------

func test_new_ship_is_the_all_rounder() -> void:
	var s := _ship()
	assert_eq(s.hull, SpaceSim.FALCON)
	SpaceSim.set_hull(s, SpaceSim.FALCON)
	assert_near(s.thrust, SpaceSim.THRUST, 0.001)
	assert_near(s.turn_speed, SpaceSim.TURN_SPEED, 0.001)


func test_hull_out_of_range_is_clamped() -> void:
	var s := _ship()
	SpaceSim.set_hull(s, 99)
	assert_eq(s.hull, SpaceSim.HULLS.size() - 1)
	SpaceSim.set_hull(s, -5)
	assert_eq(s.hull, 0)


func test_four_hulls_each_best_at_something() -> void:
	assert_eq(SpaceSim.HULLS.size(), 4)
	var fastest := _ship()
	var nimble := _ship()
	var gunner := _ship()
	var falcon := _ship()
	SpaceSim.set_hull(fastest, SpaceSim.COMET)
	SpaceSim.set_hull(nimble, SpaceSim.HORNET)
	SpaceSim.set_hull(gunner, SpaceSim.GUNSHIP)
	for s: SpaceSim.Ship in [fastest, nimble, gunner, falcon]:
		assert_true(fastest.max_speed >= s.max_speed and fastest.thrust >= s.thrust)
		assert_true(nimble.turn_speed >= s.turn_speed)
		assert_true(gunner.fire_cooldown <= s.fire_cooldown)


func test_hull_handling_is_used_by_step() -> void:
	var comet := _ship()
	SpaceSim.set_hull(comet, SpaceSim.COMET)
	_run(comet, Vector2.UP, 3.0)
	assert_true(comet.velocity.length() > SpaceSim.MAX_SPEED, "faster than the all-rounder's cap")
	assert_true(comet.velocity.length() <= comet.max_speed + 0.001)

	var hornet := _ship()
	SpaceSim.set_hull(hornet, SpaceSim.HORNET)
	_run(hornet, Vector2.RIGHT, 0.25)
	assert_near(hornet.rotation, hornet.turn_speed * 0.25, 0.01)

	var gunship := _ship()
	SpaceSim.set_hull(gunship, SpaceSim.GUNSHIP)
	var shots: int = _run(gunship, Vector2.ZERO, 1.0, true)
	assert_true(shots >= 6, "one shot per hull cooldown (0.15 s), got %d" % shots)


func test_rapid_fire_never_slows_a_hull_down() -> void:
	var s := _ship()
	SpaceSim.set_hull(s, SpaceSim.GUNSHIP)
	SpaceSim.apply_pickup(s, SpaceSim.RAPID)
	assert_true(SpaceSim.step_ship(s, Vector2.ZERO, true, DT))
	assert_near(s.cooldown, minf(SpaceSim.RAPID_COOLDOWN, s.fire_cooldown), 0.001)
