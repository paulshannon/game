extends TestCase
## The teams' starbases (SpaceBases): equally spaced on the outer rim,
## orbiting together, with each team's ships spawning beside its own.

const DT: float = 1.0 / 60.0


func test_bases_are_equally_spaced_on_the_rim_at_any_time() -> void:
	for t: float in [0.0, 37.5, 1234.0]:
		for team: int in SpaceBases.COUNT:
			var at: Vector2 = SpaceBases.position(team, t)
			var next: Vector2 = SpaceBases.position((team + 1) % SpaceBases.COUNT, t)
			assert_near(SpaceStar.distance(at), SpaceBases.RIM_RADIUS, 0.01)
			assert_near(absf(angle_difference(at.angle(), next.angle())), TAU / SpaceBases.COUNT, 0.0001)
	assert_eq(SpaceBases.COUNT, SpaceShip.COLORS.size(), "one per colour")


func test_bases_orbit_at_circular_speed() -> void:
	var t: float = 50.0
	var at: Vector2 = SpaceBases.position(2, t)
	var moved: Vector2 = (SpaceBases.position(2, t + 0.01) - at) / 0.01
	var circular: Vector2 = SpaceStar.circular_velocity(at)
	assert_near(moved.distance_to(circular), 0.0, 0.5, "along the circle, at gravity's speed")


func test_spawn_points_are_beside_your_own_base_and_apart() -> void:
	var t: float = 12.0
	var seen: Array[Vector2] = []
	for slot: int in Protocol.MAX_PLAYERS:
		var at: Vector2 = SpaceBases.spawn_point(1, slot, t)
		assert_near(at.distance_to(SpaceBases.position(1, t)), SpaceBases.SPAWN_DISTANCE, 0.01)
		for other: Vector2 in seen:
			assert_true(at.distance_to(other) > 60.0, "seats don't overlap")
		seen.append(at)


func test_a_ship_spawned_at_its_base_keeps_pace_with_it() -> void:
	var t: float = 3.0
	var s := SpaceSim.Ship.new()
	SpaceSim.respawn(s, SpaceBases.spawn_point(0, 5, t))
	for i: int in 20 * 60:
		SpaceSim.step_ship(s, Vector2.ZERO, false, DT)
	var base: Vector2 = SpaceBases.position(0, t + 20.0)
	assert_true(s.position.distance_to(base) < SpaceBases.SPAWN_DISTANCE + 60.0,
			"20 s idle, still by its base (%.0f px)" % s.position.distance_to(base))
