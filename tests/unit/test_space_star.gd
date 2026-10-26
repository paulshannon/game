extends TestCase
## The star at the centre and ships' energy (SpaceStar), and how
## SpaceSim.step_ship uses them.

const DT: float = 1.0 / 60.0


func _ship(at: Vector2) -> SpaceSim.Ship:
	var s := SpaceSim.Ship.new()
	s.rotation = 0.0
	s.position = at
	return s


func test_gravity_points_at_the_star_and_falls_off_with_distance_squared() -> void:
	var near: Vector2 = SpaceStar.pull(Vector2(1000, 0))
	var far: Vector2 = SpaceStar.pull(Vector2(2000, 0))
	assert_true(near.x < 0.0 and absf(near.y) < 0.001, "towards the centre")
	assert_near(near.length() / far.length(), 4.0, 0.01, "inverse square")
	assert_near(SpaceStar.pull(Vector2(0, -95)).length(), SpaceStar.MAX_PULL, 0.01, "capped near the surface")
	assert_eq(SpaceStar.pull(SpaceStar.CENTER), Vector2.ZERO)


func test_an_idle_ship_falls_in() -> void:
	var s := _ship(Vector2(600, 0))
	for i: int in 120:
		SpaceSim.step_ship(s, Vector2.ZERO, false, DT)
	assert_true(s.position.x < 600.0 and s.velocity.x < 0.0)


func test_recharge_is_faster_nearer_the_star() -> void:
	assert_near(SpaceStar.recharge_rate(Vector2(300, 0)), SpaceStar.RECHARGE_NEAR, 0.001, "full rate close in")
	assert_near(SpaceStar.recharge_rate(Vector2(800, 0)), SpaceStar.RECHARGE_NEAR * 0.5, 0.001, "half at twice the distance")
	assert_near(SpaceStar.recharge_rate(Vector2(1e6, 0)), SpaceStar.RECHARGE_MIN, 0.001, "never nothing")


func test_engines_and_guns_spend_energy_and_it_recharges() -> void:
	var s := _ship(Vector2(0, 100000))
	s.energy = 50.0
	SpaceSim.step_ship(s, Vector2.UP, false, 1.0)   # one second at full thrust
	assert_near(s.energy, 50.0 - SpaceStar.THRUST_COST + SpaceStar.RECHARGE_MIN, 0.01)
	var before: float = s.energy
	assert_true(SpaceSim.step_ship(s, Vector2.ZERO, true, DT))
	assert_near(s.energy, before - SpaceStar.SHOT_COST + SpaceStar.RECHARGE_MIN * DT, 0.01)
	assert_true(s.energy_used > 0.0 and s.energy_gained > 0.0)


func test_no_energy_no_engines_no_guns() -> void:
	var s := _ship(Vector2(0, 100000))
	s.energy = 0.0
	SpaceSim.step_ship(s, Vector2.UP, true, DT, 1.0)
	assert_false(s.thrusting, "the recharge this tick only buys a sliver")
	assert_eq(s.strafing, 0)
	s.energy = SpaceStar.SHOT_COST - 1.0
	s.cooldown = 0.0
	assert_false(SpaceSim.step_ship(s, Vector2.ZERO, true, DT), "a shot needs a full SHOT_COST")


func test_engines_get_what_energy_can_pay_for() -> void:
	var low := _ship(Vector2(0, 100000))
	var full := _ship(Vector2(0, 100000))
	low.energy = SpaceStar.THRUST_COST * DT * 0.25   # a quarter tick of thrust
	SpaceSim.step_ship(low, Vector2.UP, false, DT)
	SpaceSim.step_ship(full, Vector2.UP, false, DT)
	assert_true(low.velocity.length() < full.velocity.length() * 0.5)
	assert_near(low.energy, 0.0, 0.0001, "spent the lot, this tick's recharge included")


func test_respawn_refills_and_safe_spot_keeps_clear_of_the_star() -> void:
	var s := _ship(Vector2(0, 100000))
	s.energy = 3.0
	SpaceSim.respawn(s, SpaceStar.safe_spot(Vector2(50, 0)))
	assert_near(s.energy, SpaceStar.ENERGY_MAX, 0.001)
	assert_near(SpaceStar.distance(s.position), SpaceStar.SAFE_RADIUS, 0.01)
	assert_true(s.position.x > 0.0, "straight out the way it was")
	assert_eq(SpaceStar.safe_spot(Vector2(5000, 0)), Vector2(5000, 0), "already safe")
	assert_near(SpaceStar.distance(SpaceStar.safe_spot(SpaceStar.CENTER)), SpaceStar.SAFE_RADIUS, 0.01)


func test_the_star_destroys_whatever_touches_it() -> void:
	assert_true(SpaceStar.touches(Vector2(SpaceStar.RADIUS + 10, 0), 18.0))
	assert_false(SpaceStar.touches(Vector2(SpaceStar.RADIUS + 30, 0), 18.0))
	var s := _ship(Vector2(80, 0))
	s.shield = true
	s.protected_for = 2.0
	SpaceSim.destroy(s)
	assert_false(s.alive, "shield and spawn protection don't help")


# --- orbits -------------------------------------------------------------------

func test_an_orbit_keeps_its_radius_and_goes_round_at_gravitys_speed() -> void:
	var origin := Vector2(1500, 0)
	var w: float = SpaceStar.orbit_speed(1500.0)
	assert_near(w * w * 1500.0, SpaceStar.GRAVITY / (1500.0 * 1500.0), 1e-6, "w² r = GRAVITY / r²")
	var quarter: float = (PI / 2.0) / absf(w)
	var at: Vector2 = SpaceStar.orbit_position(origin, 10.0, 10.0 + quarter)
	assert_near(at.length(), 1500.0, 0.01, "stays on its circle")
	assert_near(at.x, 0.0, 0.05, "a quarter turn later")
	assert_near(at.y, 1500.0 * SpaceStar.ORBIT_DIRECTION, 0.05, "clockwise on screen (y down)")
	assert_eq(SpaceStar.orbit_position(origin, 10.0, 5.0), origin, "held at its origin before it's born")


func test_inner_orbits_are_faster() -> void:
	assert_true(absf(SpaceStar.orbit_speed(1400.0)) > absf(SpaceStar.orbit_speed(1600.0)))


func test_an_orbit_is_the_same_whenever_asked() -> void:
	# A late joiner asks once, an hour on; the server asked every tick. A closed
	# form gives the same answer either way, with no stepping.
	var origin := Vector2(-1800, 900)
	var hour: float = 3600.0
	var at: Vector2 = SpaceStar.orbit_position(origin, 100.0, 100.0 + hour)
	assert_near(at.length(), origin.length(), 0.05, "still on its circle after an hour")
	var expected: Vector2 = origin.rotated(fmod(SpaceStar.orbit_speed(origin.length()) * hour, TAU))
	assert_near(at.distance_to(expected), 0.0, 0.05)


func test_orbit_velocity_is_along_the_circle() -> void:
	var v: Vector2 = SpaceStar.orbit_velocity(Vector2(2000, 0), 0.0, 0.0)
	assert_near(v.x, 0.0, 0.001, "tangential")
	assert_near(v.length(), sqrt(SpaceStar.GRAVITY / 2000.0), 0.01, "v = sqrt(GRAVITY / r)")
	# A ship at that speed and spot circles too, under step_ship's gravity.
	var s := _ship(Vector2(2000, 0))
	s.velocity = v
	for i: int in 600:
		s.energy = SpaceStar.ENERGY_MAX
		SpaceSim.step_ship(s, Vector2.ZERO, false, DT)
	assert_true(absf(s.position.length() - 2000.0) < 2000.0 * 0.25, "roughly round (drag slows it)")
