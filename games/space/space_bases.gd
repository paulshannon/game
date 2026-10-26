class_name SpaceBases
extends RefCounted
## Pure rules for the teams' starbases: one per colour (SpaceShip.COLORS),
## equally spaced on an outer rim beyond the asteroid belts, where that
## team's ships spawn and respawn. No nodes: SpaceArena, SpaceShip and tests
## call these; SpaceBaseView draws them.
##
## The bases orbit the star together at circular speed, so where one is at
## any server time comes from the time alone (nothing replicated), and a ship
## spawned next to its base at the same speed (SpaceSim.respawn) keeps pace
## with it instead of falling in.

## Out past the outer belt (SpaceBelts.RINGS: 3600 ± 280), well inside
## SpaceBelts.ESCAPE_RADIUS.
const RIM_RADIUS: float = 4600.0
const COUNT: int = 4
## Ships spawn this far from their base's centre, spread round it by slot.
const SPAWN_DISTANCE: float = 230.0


## The angle round the star (from +x) of team `team`'s base at server time `t`.
static func angle(team: int, t: float) -> float:
	return posmod(team, COUNT) * TAU / COUNT + SpaceStar.orbit_speed(RIM_RADIUS) * t


static func position(team: int, t: float) -> Vector2:
	return SpaceStar.CENTER + Vector2.from_angle(angle(team, t)) * RIM_RADIUS


## Where a ship of `team` in seat `slot` (re)spawns at server time `t`: next
## to its base, each seat on its own side of it.
static func spawn_point(team: int, slot: int, t: float) -> Vector2:
	var around: float = angle(team, t) + posmod(slot, Protocol.MAX_PLAYERS) * TAU / Protocol.MAX_PLAYERS
	return position(team, t) + Vector2.from_angle(around) * SPAWN_DISTANCE
