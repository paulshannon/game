class_name SpaceStar
extends RefCounted
## Pure rules for the star at the centre of the map and the ships' energy.
## No nodes: SpaceSim.step_ship and SpaceDirector call these on the server,
## tests call them directly.
##
## Gravity pulls ships, and holds rocks and pickups in orbit (SpaceOrbit: a
## closed form from the spawn data, so nothing about them is replicated after
## the spawn). Shots fly straight: they live under a second. Touching the star
## destroys a ship and burns up rocks and shots. Energy recharges faster the
## closer you are, and engines and guns spend it.

const CENTER := Vector2.ZERO
## Touching this destroys a ship (and burns rocks and shots).
const RADIUS: float = 450.0
## Pull = GRAVITY / r² (px/s²), capped at MAX_PULL. At 900 px that's ~90 (a
## nudge); at the surface it's ~355, under the weakest hull's thrust (the
## Gunship's 440), so any ship's engines can still climb out at full
## throttle, slowly (if it has the energy: near the star it recharges faster
## than the main engine burns). MAX_PULL only matters inside the star, which
## nothing survives, but keeps the pull finite there.
const GRAVITY: float = 7.2e7
const MAX_PULL: float = 400.0
## Nobody (re)spawns closer than this.
const SAFE_RADIUS: float = 900.0

# --- energy -------------------------------------------------------------------

const ENERGY_MAX: float = 100.0
## Recharge per second: RECHARGE_NEAR within NEAR_RADIUS, falling off as
## 1/distance beyond it (half at twice the distance), never below RECHARGE_MIN.
const RECHARGE_NEAR: float = 40.0
const NEAR_RADIUS: float = 500.0
const RECHARGE_MIN: float = 1.5
## Spent per second at full push, and per shot.
const THRUST_COST: float = 10.0
const REVERSE_COST: float = 6.0
const STRAFE_COST: float = 8.0
const SHOT_COST: float = 7.0


static func distance(at: Vector2) -> float:
	return at.distance_to(CENTER)


## Gravity's acceleration on something at `at` (px/s²), towards the star.
static func pull(at: Vector2) -> Vector2:
	var to: Vector2 = CENTER - at
	var r2: float = to.length_squared()
	if r2 < 1.0:
		return Vector2.ZERO
	return to / sqrt(r2) * minf(GRAVITY / r2, MAX_PULL)


## Energy per second a ship at `at` gains.
static func recharge_rate(at: Vector2) -> float:
	return maxf(RECHARGE_MIN, RECHARGE_NEAR * NEAR_RADIUS / maxf(distance(at), NEAR_RADIUS))


## Whether a circle at `at` touches the star.
static func touches(at: Vector2, radius: float) -> bool:
	return distance(at) <= RADIUS + radius


## `at`, moved straight out to SAFE_RADIUS if it's closer than that.
static func safe_spot(at: Vector2) -> Vector2:
	var r: float = distance(at)
	if r >= SAFE_RADIUS:
		return at
	var out: Vector2 = (at - CENTER) / r if r > 0.001 else Vector2.RIGHT
	return CENTER + out * SAFE_RADIUS


## Rocks and pickups orbit the star (SpaceOrbit: circles, ellipses, dives
## and escapes, in closed form from their spawn data). Belts are spawned at
## or near circular speed, all going round the same way.
const ORBIT_DIRECTION: float = 1.0   # +1: clockwise on screen (y is down)


## Angular speed (rad/s) of a circular orbit `radius` out: GRAVITY / r² is the
## centripetal pull, so w² r = GRAVITY / r².
static func orbit_speed(radius: float) -> float:
	return ORBIT_DIRECTION * sqrt(GRAVITY / (radius * radius * radius))


## The velocity that keeps something at `at` on a circle round the star.
static func circular_velocity(at: Vector2) -> Vector2:
	var rel: Vector2 = at - CENTER
	var r: float = rel.length()
	if r < 1.0:
		return Vector2.ZERO
	return rel.rotated(PI / 2.0 * ORBIT_DIRECTION) / r * sqrt(GRAVITY / r)


## Energy per second for this much engine use (push: -1 brake .. 1 thrust;
## side: -1 .. 1 strafe).
static func engine_cost(push: float, side: float) -> float:
	var main: float = push * THRUST_COST if push > 0.0 else -push * REVERSE_COST
	return main + absf(side) * STRAFE_COST
