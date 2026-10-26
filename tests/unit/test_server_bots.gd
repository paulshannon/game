extends TestCase
## ServerBots: bots take free seats, never keep a person out, and leave
## cleanly. A stand-in game records spawns instead of replicating them.


class FakeGame extends GameBase:
	var spawned: Array[Dictionary] = []

	func _init() -> void:
		players_root = Node.new()

	func spawn_player(id: int, index: int, choice: Dictionary, extra: Dictionary = {}) -> void:
		spawned.append({"id": id, "index": index, "choice": choice, "extra": extra})
		var n := Node.new()
		n.name = str(id)
		players_root.add_child(n)


func _done(g: FakeGame) -> void:
	for n: Node in g.players_root.get_children():
		n.free()   # removed bots are only queue_free'd
	g.players_root.free()
	g.free()


func test_bots_take_seats_after_the_first_person() -> void:
	var g := FakeGame.new()
	assert_eq(g.claim_seat(100), 0, "the person is P1")
	g.bots.set_count(3)
	assert_eq(g.bots.count(), 3)
	assert_eq(g.spawned.map(func(s: Dictionary) -> int: return s["id"]), [-1, -2, -3])
	assert_eq(g.spawned.map(func(s: Dictionary) -> int: return s["index"]), [1, 2, 3])
	assert_true(bool(g.spawned[0]["extra"]["bot"]))
	assert_false(g.spawned[0]["choice"].has("bots"), "a bot doesn't ask for bots")
	_done(g)


func test_bots_fill_only_free_seats() -> void:
	var g := FakeGame.new()
	g.claim_seat(100)
	g.claim_seat(200)
	g.bots.set_count(99)
	assert_eq(g.bots.count(), Protocol.MAX_PLAYERS - 2, "two people, the rest bots")
	assert_eq(g.claim_seat(300), -1, "full")
	assert_true(g.bots.give_up_seat())
	assert_eq(g.bots.count(), Protocol.MAX_PLAYERS - 3)
	assert_true(g.claim_seat(300) != -1, "a person gets the freed seat")
	_done(g)


func test_fewer_bots_removes_the_newest_and_frees_seats() -> void:
	var g := FakeGame.new()
	g.claim_seat(100)
	g.bots.set_count(4)
	g.bots.set_count(1)
	assert_eq(g.bots.count(), 1)
	assert_eq(g.players_root.get_child_count(), 1, "removed bots left the tree")
	g.bots.set_count(0)
	assert_false(g.bots.give_up_seat(), "no bot left to give up a seat")
	assert_eq(g.claim_seat(200), 1, "seats 1.. are free again")
	assert_eq(g.bots.peak, 4)
	_done(g)
