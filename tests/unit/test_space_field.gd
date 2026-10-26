extends TestCase
## The unbounded asteroid field's rules (SpaceField): pure functions.


func _ring(center: Vector2, count: int, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in count:
		out.append(center + Vector2.from_angle(i * TAU / count) * distance)
	return out


func test_counts_only_rocks_near_the_anchor() -> void:
	var rocks: PackedVector2Array = _ring(Vector2.ZERO, 4, 500.0)
	rocks.append_array(_ring(Vector2.ZERO, 3, SpaceField.NEAR_DISTANCE + 1.0))
	assert_eq(SpaceField.count_near(Vector2.ZERO, rocks), 4)


func test_neediest_is_the_emptiest_short_anchor() -> void:
	var home := Vector2.ZERO
	var away := Vector2(20000, 0)
	var rocks: PackedVector2Array = _ring(home, SpaceField.ROCKS_PER_ANCHOR, 400.0)
	rocks.append_array(_ring(away, 2, 400.0))
	assert_eq(SpaceField.neediest(PackedVector2Array([home, away]), rocks), 1)
	rocks.append_array(_ring(away, SpaceField.ROCKS_PER_ANCHOR, 300.0))
	assert_eq(SpaceField.neediest(PackedVector2Array([home, away]), rocks), -1, "everyone has enough")


func test_anchors_close_together_share_rocks() -> void:
	var rocks: PackedVector2Array = _ring(Vector2.ZERO, SpaceField.ROCKS_PER_ANCHOR, 300.0)
	assert_eq(SpaceField.neediest(PackedVector2Array([Vector2.ZERO, Vector2(200, 0)]), rocks), -1)


func test_a_rock_is_stray_only_when_far_from_every_anchor() -> void:
	var anchors := PackedVector2Array([Vector2.ZERO, Vector2(5000, 0)])
	assert_false(SpaceField.is_stray(Vector2(SpaceField.STRAY_DISTANCE - 1.0, 0), anchors))
	assert_false(SpaceField.is_stray(Vector2(5000, SpaceField.STRAY_DISTANCE - 1.0), anchors), "near the other ship")
	assert_true(SpaceField.is_stray(Vector2(0, SpaceField.STRAY_DISTANCE + 1.0), anchors))


func test_new_rocks_enter_off_screen_and_are_not_dropped_at_once() -> void:
	# Off a 1280x720 view centred on the ship, even a large rock.
	assert_true(SpaceField.ENTRY_DISTANCE - SpaceSim.asteroid_radius(SpaceSim.LARGE) > Vector2(640, 360).length())
	var anchor := Vector2(-3000, 700)
	var at: Vector2 = SpaceField.entry_point(anchor, 1.0)
	assert_near(at.distance_to(anchor), SpaceField.ENTRY_DISTANCE, 0.01)
	assert_false(SpaceField.is_stray(at, PackedVector2Array([anchor])))


func test_entering_rocks_head_for_the_ship() -> void:
	var anchor := Vector2(100, 100)
	var at: Vector2 = SpaceField.entry_point(anchor, 2.0)
	for turn: float in [-1.0, 0.0, 1.0, 5.0]:
		var v: Vector2 = SpaceField.entry_velocity(at, anchor, turn, 80.0)
		assert_near(v.length(), 80.0, 0.001)
		var off: float = absf(angle_difference(v.angle(), (anchor - at).angle()))
		assert_true(off <= SpaceField.ENTRY_SPREAD + 0.001, "turn %s: %s rad off" % [turn, off])
	assert_true(SpaceField.entry_velocity(anchor, anchor, 0.0, 10.0).is_finite(), "degenerate: on the anchor")


func test_clear_keeps_new_rocks_off_every_ship() -> void:
	var anchors := PackedVector2Array([Vector2.ZERO, Vector2(1000, 0)])
	assert_false(SpaceField.is_clear(Vector2(1000 - SpaceField.SAFE_DISTANCE + 1.0, 0), anchors))
	assert_true(SpaceField.is_clear(Vector2(500, 0), anchors))
