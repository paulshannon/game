extends TestCase
## Each hull's art: its sprite loads, and its jets sit where a ship's jets
## belong (flames behind, nozzles mirrored, nose ahead of tail), different
## for every hull.


func test_every_hull_has_its_own_jet_layout() -> void:
	var seen: Array[String] = []
	for h: int in SpaceSim.HULLS.size():
		var layout: String = var_to_str(SpaceHullArt.JETS[h])
		assert_false(layout in seen, "hull %d shares its jets with another" % h)
		seen.append(layout)
	assert_eq(SpaceHullArt.JETS.size(), SpaceSim.HULLS.size())


func test_flames_are_behind_the_ship() -> void:
	for h: int in SpaceSim.HULLS.size():
		assert_true(SpaceHullArt.flames(h).size() >= 1)
		for jet: Vector3 in SpaceHullArt.flames(h):
			assert_true(SpaceHullArt.to_body(Vector2(jet.x, jet.y)).x < 0.0, "hull %d flame aft" % h)
			assert_true(jet.z > 0.0)


func test_nozzles_are_mirrored_with_the_nose_ahead() -> void:
	for h: int in SpaceSim.HULLS.size():
		for at_nose: bool in [true, false]:
			var r: Vector2 = SpaceHullArt.nozzle(h, at_nose, true)
			var l: Vector2 = SpaceHullArt.nozzle(h, at_nose, false)
			assert_true(r.y > 0.0 and l.y < 0.0, "right is +y")
			assert_eq(r, Vector2(l.x, -l.y), "mirrored")
		assert_true(SpaceHullArt.nozzle(h, true, true).x > SpaceHullArt.nozzle(h, false, true).x,
				"hull %d: nose nozzle ahead of the tail one" % h)


func test_sprites_load_in_every_colour() -> void:
	for h: int in SpaceSim.HULLS.size():
		for c: String in SpaceShip.COLORS:
			assert_true(load(SpaceHullArt.texture(h, c)) is Texture2D, "%d %s" % [h, c])
