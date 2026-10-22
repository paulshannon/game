extends TestCase
## PlayerNet's client-side buffering, without a network or scene tree.


func test_nothing_to_render_before_first_stamped_snapshot() -> void:
	var n := PlayerNet.new(false)
	n.on_position(0.0, Vector3.ONE)  # spawn-time value, before any server tick
	assert_false(n.can_render())
	n.on_time(10.0)
	assert_false(n.can_render(), "still no stamped position")
	n.on_position(10.0, Vector3.ONE)
	assert_true(n.can_render())


func test_samples_on_server_timeline() -> void:
	var n := PlayerNet.new(false)
	n.on_time(10.0)
	n.on_position(10.0, Vector3(0, 0, 0))
	n.on_time(10.1)
	n.on_position(10.1, Vector3(10, 0, 0))
	var p: Vector3 = n.position_at(10.05)
	assert_near(p.x, 5.0)


func test_rotation_is_null_until_received_and_angular_in_2d() -> void:
	var n := PlayerNet.new(true)
	assert_eq(n.rotation_at(1.0), null)
	n.on_rotation(1.0, deg_to_rad(350.0))
	n.on_rotation(2.0, deg_to_rad(10.0))
	var a: float = n.rotation_at(1.5)
	assert_near(wrapf(rad_to_deg(a), 0.0, 360.0), 0.0, 0.01)


func test_server_side_never_buffers() -> void:
	var n := PlayerNet.new(false)
	n.server_side = true
	n.on_time(10.0)
	n.on_position(10.0, Vector3.ONE)
	assert_false(n.can_render())
