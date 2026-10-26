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


# --- rocks fall ---------------------------------------------------------------

func test_a_rock_far_away_drifts_almost_straight() -> void:
	var fall := SpaceStar.Fall.new(Vector2(0, 100000), Vector2(100, 0), 10.0)
	assert_eq(fall.position_at(10.0), Vector2(0, 100000), "where it was spawned")
	assert_eq(fall.position_at(5.0), Vector2(0, 100000), "held there before its birth")
	assert_near(fall.position_at(11.0).x, 100.0, 0.5)
	assert_near(fall.position_at(11.0).y, 100000.0, 0.5)


func test_a_rock_near_the_star_curves_towards_it() -> void:
	var fall := SpaceStar.Fall.new(Vector2(800, 0), Vector2(0, 100), 0.0)
	var at: Vector2 = fall.position_at(2.0)
	assert_true(at.x < 700.0, "pulled in, got %s" % at)
	assert_true(at.y > 0.0, "still carried along by its own motion")
	assert_true(fall.velocity_at(2.0).x < -50.0, "falling inwards")


func test_every_peer_agrees_on_a_rock_however_it_steps() -> void:
	# The server asks every tick; a late joiner asks once, much later.
	var server := SpaceStar.Fall.new(Vector2(1200, 300), Vector2(-60, 40), 100.0)
	var late := SpaceStar.Fall.new(Vector2(1200, 300), Vector2(-60, 40), 100.0)
	for i: int in 300:
		server.position_at(100.0 + i / 60.0)
	assert_eq(late.position_at(105.0), server.position_at(105.0), "the same steps give the same path")


func test_a_slightly_earlier_time_coasts_back() -> void:
	var fall := SpaceStar.Fall.new(Vector2(1000, 0), Vector2(0, 50), 0.0)
	var later: Vector2 = fall.position_at(1.0)
	var earlier: Vector2 = fall.position_at(0.98)
	assert_true(earlier.distance_to(later) < 3.0)


func test_every_hull_can_climb_out_under_full_thrust() -> void:
	for h: int in SpaceSim.HULLS.size():
		assert_true(float(SpaceSim.HULLS[h]["thrust"]) > SpaceStar.MAX_PULL,
				"%s's engines beat the strongest pull" % SpaceSim.HULLS[h]["name"])
		# Right at the surface, nose out, full thrust: it climbs.
		var s := SpaceSim.Ship.new()
		SpaceSim.set_hull(s, h)
		s.position = Vector2(SpaceStar.RADIUS + 25.0, 0)
		s.rotation = 0.0   # facing +x: away from the star
		for i: int in 120:
			SpaceSim.step_ship(s, Vector2.UP, false, 1.0 / 60.0)
		assert_true(s.alive and s.position.x > SpaceStar.RADIUS + 60.0 and s.velocity.x > 0.0,
				"%s climbs out, at %s" % [SpaceSim.HULLS[h]["name"], s.position])
