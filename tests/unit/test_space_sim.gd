extends TestCase
## The space game's rules (SpaceSim): pure functions, no scene tree.

const DT: float = 1.0 / 60.0


## Far from the star: its pull there is a few thousandths of a px/s².
const FAR := Vector2(0, 200000)


func _ship() -> SpaceSim.Ship:
	var s := SpaceSim.Ship.new()
	s.rotation = 0.0  # facing +x
	s.position = FAR
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
	assert_near(s.velocity.length(), speed, speed * 0.01, "no drag: only the star's faint pull")


func test_no_drag_and_no_speed_cap() -> void:
	var s := _ship()
	for i: int in 20 * 60:
		s.energy = SpaceStar.ENERGY_MAX   # this is about speed, not the tank
		SpaceSim.step_ship(s, Vector2.UP, false, DT)
	var expected: float = SpaceSim.THRUST * 20.0
	assert_near(s.velocity.length(), expected, expected * 0.05, "keeps speeding up under thrust")


func test_turning_rotates_without_moving() -> void:
	var s := _ship()
	_run(s, Vector2.RIGHT, 0.25)
	assert_near(s.rotation, SpaceSim.TURN_SPEED * 0.25, 0.01)
	assert_near(s.velocity.length(), 0.0, 0.01, "only the star's faint pull")


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
	assert_eq(SpaceSim.shot_origin(s), FAR + Vector2(SpaceSim.MUZZLE, 0))
	assert_eq(SpaceSim.shot_velocity(s), Vector2(SpaceSim.SHOT_SPEED, 100))


func test_shot_expires_by_age() -> void:
	assert_false(SpaceSim.shot_expired(0.5))
	assert_true(SpaceSim.shot_expired(SpaceSim.SHOT_LIFE))


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
	# One tick of a shot from a ship doing 1400 px/s (~37 px), passing a
	# small rock 15 px off-centre: both end points miss, the path doesn't.
	var step: float = (SpaceSim.SHOT_SPEED + 1400.0) * DT
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
		assert_true(fastest.thrust >= s.thrust, "most thrust: the highest cruise speed")
		assert_true(nimble.turn_speed >= s.turn_speed)
		assert_true(gunner.fire_cooldown <= s.fire_cooldown)


func test_hull_handling_is_used_by_step() -> void:
	var comet := _ship()
	SpaceSim.set_hull(comet, SpaceSim.COMET)
	var falcon := _ship()
	_run(comet, Vector2.UP, 3.0)
	_run(falcon, Vector2.UP, 3.0)
	assert_true(comet.velocity.length() > falcon.velocity.length(), "more thrust, faster")

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


# --- teams and PvP ------------------------------------------------------------

func test_shots_hit_other_teams_only() -> void:
	var target := _ship()
	target.team = 1
	assert_true(SpaceSim.shot_can_hit(0, target), "another team")
	assert_false(SpaceSim.shot_can_hit(1, target), "no friendly fire")
	target.protected_for = 1.0
	assert_false(SpaceSim.shot_can_hit(0, target), "spawn protection: shots fly through")
	target.protected_for = 0.0
	target.alive = false
	assert_false(SpaceSim.shot_can_hit(0, target), "not a wreck")


func test_a_shield_takes_a_shot() -> void:
	var target := _ship()
	target.shield = true
	assert_false(SpaceSim.hit_ship(target), "shield absorbs it")
	assert_true(target.alive)
	assert_false(SpaceSim.shot_can_hit(1, target), "then a moment of grace")


func test_smallest_team_prefers_the_seat_on_a_tie() -> void:
	assert_eq(SpaceSim.smallest_team([0, 0, 0, 0] as Array[int], 2), 2)
	assert_eq(SpaceSim.smallest_team([1, 0, 0, 1] as Array[int], 3), 1, "next empty one after the seat's")
	assert_eq(SpaceSim.smallest_team([2, 1, 2, 2] as Array[int], 6), 1)


# --- strafe -------------------------------------------------------------------

func test_strafe_pushes_sideways_without_turning() -> void:
	var s := _ship()   # facing +x, so its right side is +y (y is down)
	for i: int in 30:
		SpaceSim.step_ship(s, Vector2.ZERO, false, DT, 1.0)
	assert_true(s.velocity.y > 50.0, "strafing right moves towards +y, got %s" % s.velocity)
	assert_near(s.velocity.x, 0.0, 0.001)
	assert_near(s.rotation, 0.0, 0.001, "the nose stays put")
	assert_eq(s.strafing, 1)


func test_strafe_is_weaker_than_thrust_and_capped() -> void:
	var side := _ship()
	var ahead := _ship()
	for i: int in 30:
		SpaceSim.step_ship(side, Vector2.ZERO, false, DT, -1.0)
		SpaceSim.step_ship(ahead, Vector2.UP, false, DT)
	assert_true(side.velocity.length() < ahead.velocity.length())
	assert_eq(side.strafing, -1)
	SpaceSim.step_ship(side, Vector2.ZERO, false, DT, INF)
	assert_eq(side.strafing, 0, "a non-finite strafe is ignored")
	for i: int in 1200:
		SpaceSim.step_ship(side, Vector2.UP, false, DT, 1.0)
	# Thrust and strafe together push sqrt(1 + 0.6²) times as hard, for at
	# most the 1230 ticks either was on (and the tank runs dry well before).
	var limit: float = side.thrust * sqrt(1.0 + SpaceSim.STRAFE_FACTOR * SpaceSim.STRAFE_FACTOR) * 1230.0 * DT
	assert_true(side.velocity.length() <= limit * 1.001, "never more than thrust + strafe")
