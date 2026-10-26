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


func test_a_broken_rock_parts_onto_neighbouring_orbits() -> void:
	var at := Vector2(0, 1500)
	var pieces: PackedVector2Array = SpaceBelts.split_points(SpaceSim.LARGE, at)
	assert_eq(pieces.size(), 2)
	assert_near(pieces[0].length(), 1500.0 - SpaceBelts.SPLIT_SPREAD, 0.01, "one inside")
	assert_near(pieces[1].length(), 1500.0 + SpaceBelts.SPLIT_SPREAD, 0.01, "one outside")
	# Inner goes round faster, so they drift apart along the ring.
	var later: float = 10.0
	var inner: Vector2 = SpaceStar.orbit_position(pieces[0], 0.0, later)
	var outer: Vector2 = SpaceStar.orbit_position(pieces[1], 0.0, later)
	assert_true(inner.distance_to(outer) > 2.0 * SpaceBelts.SPLIT_SPREAD + 20.0)
	assert_true(SpaceBelts.split_points(SpaceSim.SMALL, at).is_empty(), "the smallest just goes")
