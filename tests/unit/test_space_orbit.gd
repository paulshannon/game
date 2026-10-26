extends TestCase
## SpaceOrbit: rocks' and pickups' paths round the star, in closed form from
## their spawn data. Checked against a fine numeric integration and the
## conserved quantities of two-body motion.

const MU: float = SpaceStar.GRAVITY


## Reference: RK4 in small steps under the same (uncapped) pull.
func _integrate(p: Vector2, v: Vector2, seconds: float, step: float = 1.0 / 2000.0) -> Vector2:
	var pos := Vector2(p)
	var vel := Vector2(v)
	var accel := func(at: Vector2) -> Vector2: return -at * MU / pow(at.length(), 3.0)
	for i: int in roundi(seconds / step):
		var a1: Vector2 = accel.call(pos)
		var a2: Vector2 = accel.call(pos + vel * step * 0.5)
		var a3: Vector2 = accel.call(pos + (vel + a1 * step * 0.5) * step * 0.5)
		var a4: Vector2 = accel.call(pos + (vel + a2 * step * 0.5) * step)
		pos += (vel + (vel + a1 * step * 0.5) * 2.0 + (vel + a2 * step * 0.5) * 2.0 + (vel + a3 * step)) * step / 6.0
		vel += (a1 + a2 * 2.0 + a3 * 2.0 + a4) * step / 6.0
	return pos


func _energy(o: SpaceOrbit, t: float) -> float:
	return o.velocity_at(t).length_squared() * 0.5 - MU / (o.position_at(t) - SpaceStar.CENTER).length()


func test_a_circular_orbit_stays_round_and_keeps_its_period() -> void:
	var at := Vector2(1500, 0)
	var o := SpaceOrbit.new(at, SpaceStar.circular_velocity(at), 10.0)
	assert_true(o.is_bound())
	var period: float = TAU / absf(SpaceStar.orbit_speed(1500.0))
	assert_near(o.position_at(10.0 + period * 0.25).length(), 1500.0, 0.05)
	assert_near(o.position_at(10.0 + period * 0.25).y, 1500.0 * SpaceStar.ORBIT_DIRECTION, 0.1, "a quarter turn, clockwise")
	assert_near(o.position_at(10.0 + period).distance_to(at), 0.0, 0.1, "back after one lap")
	assert_eq(o.position_at(5.0), at, "held at its origin before it's born")


func test_an_ellipse_matches_step_by_step_integration() -> void:
	var at := Vector2(1500, 0)
	var v: Vector2 = SpaceStar.circular_velocity(at) * 0.88 + Vector2(40, 0)
	var o := SpaceOrbit.new(at, v, 0.0)
	for t: float in [0.7, 3.0, 9.0]:
		var expected: Vector2 = _integrate(at, v, t)
		assert_near(o.position_at(t).distance_to(expected), 0.0, 0.5, "at %.1f s" % t)


func test_an_escape_matches_integration_and_keeps_going() -> void:
	var at := Vector2(0, -1500)
	var v: Vector2 = SpaceStar.circular_velocity(at) * 1.7
	var o := SpaceOrbit.new(at, v, 0.0)
	assert_false(o.is_bound())
	assert_near(o.position_at(4.0).distance_to(_integrate(at, v, 4.0)), 0.0, 0.5)
	assert_true(o.position_at(60.0).length() > o.position_at(30.0).length(), "still leaving")


func test_energy_and_angular_momentum_are_kept_for_hours() -> void:
	var at := Vector2(-2300, 900)
	var v: Vector2 = SpaceStar.circular_velocity(at) * 1.1
	var o := SpaceOrbit.new(at, v, 100.0)
	var e0: float = _energy(o, 100.0)
	var h0: float = (at - SpaceStar.CENTER).cross(v)
	for t: float in [100.5, 160.0, 900.0, 3700.0]:
		assert_near(_energy(o, t), e0, absf(e0) * 1e-4, "energy at %.0f s" % t)
		assert_near((o.position_at(t) - SpaceStar.CENTER).cross(o.velocity_at(t)), h0, absf(h0) * 1e-4)


func test_the_same_answer_however_and_whenever_asked() -> void:
	# The server asks every tick; a late joiner asks once, much later.
	var at := Vector2(1600, 400)
	var v: Vector2 = SpaceStar.circular_velocity(at) * 0.9
	var ticked := SpaceOrbit.new(at, v, 0.0)
	var late := SpaceOrbit.new(at, v, 0.0)
	for i: int in 3600:
		ticked.position_at(i / 60.0)
	assert_near(late.position_at(60.0).distance_to(ticked.position_at(60.0)), 0.0, 0.01)


func test_a_rock_at_rest_falls_straight_in() -> void:
	var o := SpaceOrbit.new(Vector2(1500, 0), Vector2.ZERO, 0.0)
	var r1: float = o.position_at(5.0).length()
	var r2: float = o.position_at(10.0).length()
	assert_true(r1 < 1500.0 and r2 < r1, "falling (%.0f, %.0f)" % [r1, r2])
	assert_false(is_nan(r2))
