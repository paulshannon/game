extends TestCase
## StateTimeline: discrete state released on the server timeline.

var _changes: Array[Vector3] = []   # before, after, at


func _record(before: int, after: int, at: float) -> void:
	_changes.append(Vector3(before, after, at))


func test_first_value_is_a_baseline_not_a_change() -> void:
	_changes.clear()
	var tl := StateTimeline.new(1)
	tl.push(5.0, 0)          # a late joiner sees a ship that's already dead
	tl.advance(6.0, _record)
	assert_eq(tl.current(), 0)
	assert_true(_changes.is_empty())


func test_changes_wait_for_render_time() -> void:
	_changes.clear()
	var tl := StateTimeline.new()
	tl.push(1.0, 1)
	tl.push(2.0, 0)
	tl.advance(1.5, _record)
	assert_eq(tl.current(), 1)
	assert_true(_changes.is_empty(), "the change is in the future")
	tl.advance(2.0, _record)
	assert_eq(tl.current(), 0)
	assert_eq(_changes, [Vector3(1, 0, 2.0)] as Array[Vector3])


func test_repeats_are_dropped_and_each_change_reported_once() -> void:
	_changes.clear()
	var tl := StateTimeline.new()
	for i: int in 10:
		tl.push(1.0 + i * 0.05, 3)    # sent with every snapshot
	tl.push(2.0, 4)
	tl.push(2.05, 4)
	tl.push(2.1, 5)
	tl.advance(10.0, _record)
	assert_eq(_changes, [Vector3(3, 4, 2.0), Vector3(4, 5, 2.1)] as Array[Vector3])


func test_out_of_order_stamp_is_kept_in_order() -> void:
	_changes.clear()
	var tl := StateTimeline.new()
	tl.push(2.0, 1)
	tl.push(1.0, 2)   # can't happen before the previous one
	tl.advance(1.5, _record)
	assert_eq(tl.current(), 0, "nothing released before 2.0")
	tl.advance(2.0, _record)
	assert_eq(tl.current(), 2)
