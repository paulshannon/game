extends TestCase


func test_empty_returns_null() -> void:
	var b := SnapshotBuffer.new()
	assert_eq(b.sample(1.0), null)


func test_interpolates_midpoint() -> void:
	var b := SnapshotBuffer.new()
	b.push(1.0, Vector2(0, 0))
	b.push(2.0, Vector2(10, 20))
	var v: Vector2 = b.sample(1.5)
	assert_near(v.x, 5.0)
	assert_near(v.y, 10.0)


func test_holds_ends_instead_of_extrapolating() -> void:
	var b := SnapshotBuffer.new()
	b.push(1.0, Vector3(0, 0, 0))
	b.push(2.0, Vector3(4, 0, 0))
	assert_eq(b.sample(0.0), Vector3(0, 0, 0))
	assert_eq(b.sample(9.0), Vector3(4, 0, 0))


func test_angular_takes_short_way() -> void:
	var b := SnapshotBuffer.new(true)
	b.push(0.0, deg_to_rad(350.0))
	b.push(1.0, deg_to_rad(10.0))
	var a: float = b.sample(0.5)
	assert_near(wrapf(rad_to_deg(a), 0.0, 360.0), 0.0, 0.01)


func test_quaternion_slerp() -> void:
	var b := SnapshotBuffer.new()
	b.push(0.0, Quaternion.IDENTITY)
	b.push(1.0, Quaternion(Vector3.UP, PI / 2.0))
	var q: Quaternion = b.sample(0.5)
	assert_near(q.get_angle(), PI / 4.0, 0.001)


func test_capacity_is_bounded() -> void:
	var b := SnapshotBuffer.new()
	for i: int in 100:
		b.push(float(i), float(i))
	assert_eq(b.size(), SnapshotBuffer.CAPACITY)


func test_non_monotonic_push_is_corrected() -> void:
	var b := SnapshotBuffer.new()
	b.push(2.0, 0.0)
	b.push(1.0, 10.0)  # arrived "late"; must not break bsearch ordering
	assert_near(float(b.sample(5.0)), 10.0)
