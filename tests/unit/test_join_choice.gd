extends TestCase
## The join choice a client sends before its player spawns (GameBase): the
## server must turn anything into valid spawn data. Space's is ship + colour.


func test_choice_int_reads_numbers_only() -> void:
	assert_eq(GameBase.choice_int({"k": 3}, "k", 7), 3)
	assert_eq(GameBase.choice_int({"k": 2.9}, "k", 7), 2)
	assert_eq(GameBase.choice_int({}, "k", 7), 7, "missing")
	assert_eq(GameBase.choice_int({"k": "3"}, "k", 7), 7, "a string isn't a number")
	assert_eq(GameBase.choice_int({"k": [1]}, "k", 7), 7)
	assert_eq(GameBase.choice_int({"k": NAN}, "k", 7), 7)
	assert_eq(GameBase.choice_int({"k": INF}, "k", 7), 7)


func _space(choice: Dictionary, index: int) -> Dictionary:
	var arena := SpaceArena.new()
	var out: Dictionary = arena._sanitize_choice(choice, index)
	arena.free()
	return out


func test_space_keeps_a_valid_pick() -> void:
	assert_eq(_space({"hull": SpaceSim.HORNET, "color": 3}, 0), {"hull": SpaceSim.HORNET, "color": 3})


func test_space_auto_colour_is_the_seats() -> void:
	assert_eq(_space({"hull": 0, "color": SpaceShip.COLOR_AUTO}, 5)["color"], 5 % SpaceShip.COLORS.size())
	assert_eq(_space({}, 2), {"hull": SpaceSim.FALCON, "color": 2}, "nothing picked")


func test_space_junk_becomes_valid() -> void:
	var out: Dictionary = _space({"hull": 99, "color": -40, "id": 1, "pos": "x"}, 1)
	assert_eq(out, {"hull": SpaceSim.HULLS.size() - 1, "color": 1}, "only known keys, in range")
	assert_eq(_space({"hull": "big", "color": 12}, 6)["color"], 6 % SpaceShip.COLORS.size())
