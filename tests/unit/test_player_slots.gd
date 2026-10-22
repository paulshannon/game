extends TestCase


func test_fills_lowest_slots_in_order() -> void:
	var s := PlayerSlots.new(3)
	assert_eq(s.claim(100), 0)
	assert_eq(s.claim(200), 1)
	assert_eq(s.claim(300), 2)


func test_rejects_when_full() -> void:
	var s := PlayerSlots.new(2)
	s.claim(100)
	s.claim(200)
	assert_eq(s.claim(300), -1)
	assert_eq(s.count(), 2)


func test_leave_then_join_in_same_frame_is_accepted() -> void:
	# Full match; one player leaves and another joins before the leaving
	# player's node is freed. Slots don't wait for the node.
	var s := PlayerSlots.new(Protocol.MAX_PLAYERS)
	for i: int in Protocol.MAX_PLAYERS:
		s.claim(1000 + i)
	s.release(1005)
	assert_eq(s.claim(2000), 5)


func test_reuses_freed_slot_instead_of_overlapping() -> void:
	# 8 join, slot 5 leaves: the newcomer takes slot 5 (its own spawn point
	# and a "P6" label), not index 8 — which would wrap onto slot 0's spawn.
	var s := PlayerSlots.new(8)
	for i: int in 8:
		s.claim(1000 + i)
	s.release(1005)
	var slot: int = s.claim(3000)
	assert_eq(slot, 5)
	assert_true(slot < 8)


func test_lowest_free_slot_wins() -> void:
	var s := PlayerSlots.new(4)
	for i: int in 4:
		s.claim(10 + i)
	s.release(13)
	s.release(11)
	assert_eq(s.claim(99), 1)
	assert_eq(s.claim(98), 3)


func test_claim_is_idempotent_and_release_unknown_is_safe() -> void:
	var s := PlayerSlots.new(4)
	assert_eq(s.claim(7), 0)
	assert_eq(s.claim(7), 0)
	assert_eq(s.count(), 1)
	s.release(12345)
	assert_eq(s.count(), 1)
