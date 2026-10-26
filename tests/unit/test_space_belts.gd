extends TestCase
## The asteroid belts (SpaceBelts): rings round the star, kept full, new
## rocks off every ship's screen, broken rocks onto neighbouring orbits.


func test_rings_sit_outside_the_spawn_ring_and_dont_overlap() -> void:
	var outer_edge: float = SpaceStar.SAFE_RADIUS
	for ring: Vector3 in SpaceBelts.RINGS:
		assert_true(ring.x - ring.y > outer_edge, "clear of the last one (and of spawns)")
		outer_edge = ring.x + ring.y
	assert_eq(SpaceBelts.target_total(), 28 + 40 + 54)


func test_points_land_in_their_ring() -> void:
	for ring: int in SpaceBelts.RINGS.size():
		for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0.5), Vector2(0.5, 0.99)]:
			var at: Vector2 = SpaceBelts.point_in(ring, uv.x, uv.y)
			assert_eq(SpaceBelts.ring_of(at), ring)
	assert_eq(SpaceBelts.ring_of(Vector2(1000, 0)), -1, "between the star and the first ring")
	assert_eq(SpaceBelts.ring_of(Vector2(10000, 0)), -1, "beyond the last")


func test_the_emptiest_ring_is_refilled_first() -> void:
	var rocks := PackedVector2Array()
	for i: int in 28:
		rocks.append(SpaceBelts.point_in(0, 0.5, i / 28.0))
	for i: int in 30:
		rocks.append(SpaceBelts.point_in(1, 0.5, i / 30.0))
	var counts: Array[int] = SpaceBelts.counts(rocks)
	assert_eq(counts, [28, 30, 0] as Array[int])
	assert_eq(SpaceBelts.neediest(counts), 2, "54 short beats 10 short")
	assert_eq(SpaceBelts.neediest([28, 40, 54] as Array[int]), -1, "all full")


func test_new_rocks_appear_off_screen() -> void:
	var ships := PackedVector2Array([Vector2(1500, 0)])
	assert_false(SpaceBelts.is_clear(Vector2(1500, 300), ships))
	assert_true(SpaceBelts.is_clear(Vector2(-1500, 0), ships))


func test_sizes_are_mostly_large() -> void:
	assert_eq(SpaceBelts.size_for(0.05), SpaceSim.SMALL)
	assert_eq(SpaceBelts.size_for(0.3), SpaceSim.MEDIUM)
	assert_eq(SpaceBelts.size_for(0.9), SpaceSim.LARGE)
	assert_eq(SpaceBelts.size_for(1.0), SpaceSim.LARGE)


func test_some_new_rocks_start_off_circular_speed() -> void:
	var at := Vector2(1500, 0)
	var circular: Vector2 = SpaceStar.circular_velocity(at)
	assert_eq(SpaceBelts.spawn_velocity(at, 0.9, 0.0), circular, "most are circular")
	assert_near(SpaceBelts.spawn_velocity(at, 0.1, 0.0).length(), circular.length() * SpaceBelts.OFF_SPEED.x, 0.01)
	assert_near(SpaceBelts.spawn_velocity(at, 0.1, 1.0).length(), circular.length() * SpaceBelts.OFF_SPEED.y, 0.01)


func test_a_broken_rock_flies_apart_and_keeps_its_momentum() -> void:
	var at := Vector2(0, 1500)
	var v: Vector2 = SpaceStar.circular_velocity(at)
	var pieces: Array = SpaceBelts.split(SpaceSim.LARGE, at, v, 0.7, 1.0)
	assert_eq(pieces.size(), 2)
	var p0: Vector2 = pieces[0][0]
	var p1: Vector2 = pieces[1][0]
	var v0: Vector2 = pieces[0][1]
	var v1: Vector2 = pieces[1][1]
	assert_near(p0.distance_to(p1), SpaceBelts.SPLIT_GAP * 2.0, 0.01, "they start apart")
	assert_near((v0 + v1).distance_to(v * 2.0), 0.0, 0.01, "equal and opposite kicks")
	assert_near((v0 - v).length(), SpaceBelts.SPLIT_KICK.y, 0.01, "full kick at roll 1")
	assert_true(SpaceBelts.split(SpaceSim.SMALL, at, v, 0.0, 0.0).is_empty(), "the smallest just goes")


func test_hard_kicks_can_escape_or_dive_into_the_star() -> void:
	var at := Vector2(1500, 0)
	var v: Vector2 = SpaceStar.circular_velocity(at)
	var forward: Vector2 = v.normalized()
	# Kicked straight ahead: past escape speed (sqrt(2) x circular here).
	var fast: Array = SpaceBelts.split(SpaceSim.LARGE, at, v, forward.angle(), 1.0)
	assert_false(SpaceOrbit.new(fast[0][0], fast[0][1], 0.0).is_bound(), "escapes")
	# Its twin, kicked straight back, falls nearly straight in.
	var slow := SpaceOrbit.new(fast[1][0], fast[1][1], 0.0)
	var closest: float = INF
	for i: int in 400:
		closest = minf(closest, SpaceStar.distance(slow.position_at(i * 0.05)))
	assert_true(closest < SpaceStar.RADIUS + 40.0, "dives into the star (closest %.0f px)" % closest)
	assert_true(SpaceBelts.escaped(Vector2(SpaceBelts.ESCAPE_RADIUS + 1.0, 0)))
