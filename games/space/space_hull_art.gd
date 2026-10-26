class_name SpaceHullArt
extends RefCounted
## How each hull (SpaceSim.HULLS) looks: its Kenney sprite, and where its
## jets are on that sprite. Purely visual: collision is the same circle for
## every hull (SpaceSim.SHIP_RADIUS).
##
## Jet positions are in sprite pixels with the nose up, measured from the
## sprite's centre (+x right, +y towards the tail), so they read straight off
## the art. Thrusters come in mirrored pairs: give the right-hand one.

const PACK: String = SpaceShip.PACK

## By hull: main engine flames as Vector3(x, y, scale), where (x, y) is the
## hull's back edge at that engine (measured off the sprite's alpha): the
## flame hangs from there with no gap. Then the right-hand RCS nozzles at the
## nose and at the tail (wingtips); their puffs start RCS_GAP out.
const JETS: Array[Dictionary] = [
	{   # Falcon: twin flames under the yellow wing engines, pods at the wingtips.
		"flames": [Vector3(-25, 25, 0.6), Vector3(25, 25, 0.6)],
		"nose": Vector2(11, -26), "tail": Vector2(48, 18),
	},
	{   # Comet: twin flames under the outboard engines, far-out wingtips.
		"flames": [Vector3(-33, 33, 0.65), Vector3(33, 33, 0.65)],
		"nose": Vector2(6, -27), "tail": Vector2(55, 8),
	},
	{   # Hornet: one big central flame and two small ones on the wing strips.
		"flames": [Vector3(0, 37, 0.9), Vector3(-36, 27, 0.4), Vector3(36, 27, 0.4)],
		"nose": Vector2(6, -28), "tail": Vector2(48, 24),
	},
	{   # Gunship: twin flames from the tapered rear, nose jets on the prongs.
		"flames": [Vector3(-11, 35, 0.7), Vector3(11, 35, 0.7)],
		"nose": Vector2(15, -37), "tail": Vector2(50, 12),
	},
]

## The Gunship is Kenney's enemy ship 2, which comes in other colours:
## orange players get the black one.
const ENEMY_COLORS: Dictionary = {"blue": "Blue", "green": "Green", "orange": "Black", "red": "Red"}


## The sprite for a hull in one of SpaceShip.COLORS. Player ships point up,
## the enemy ship (Gunship) down: see points_down().
static func texture(hull: int, color: String) -> String:
	if hull == SpaceSim.GUNSHIP:
		return PACK + "Enemies/enemy%s2.png" % ENEMY_COLORS.get(color, "Blue")
	return PACK + "playerShip%d_%s.png" % [SpaceSim.sanitize_hull(hull) + 1, color]


static func points_down(hull: int) -> bool:
	return hull == SpaceSim.GUNSHIP


## Main flames: Vector3(x, y, scale) in sprite pixels (nose up); (x, y) is
## where the flame's top edge goes.
static func flames(hull: int) -> Array:
	return JETS[SpaceSim.sanitize_hull(hull)]["flames"]


## An RCS nozzle in the ship body's frame (+x the nose, +y the right side,
## at SpaceShip.SHIP_SCALE): `at_nose` or at the tail, `right` or left.
static func nozzle(hull: int, at_nose: bool, right: bool) -> Vector2:
	var p: Vector2 = JETS[SpaceSim.sanitize_hull(hull)]["nose" if at_nose else "tail"]
	return to_body(Vector2(p.x if right else -p.x, p.y))


## Sprite pixels (nose up) to the body's frame: the art is turned a quarter
## clockwise so the nose points along +x, and scaled.
static func to_body(sprite_px: Vector2) -> Vector2:
	return Vector2(-sprite_px.y, sprite_px.x) * SpaceShip.SHIP_SCALE
