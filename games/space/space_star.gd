class_name SpaceStar
extends RefCounted
## Pure rules for the star at the centre of the map and the ships' energy.
## No nodes: SpaceSim.step_ship and SpaceDirector call these on the server,
## tests call them directly.
##
## Gravity pulls ships and rocks (shots fly straight: they live under a
## second). A rock's path is a Fall: stepped from its spawn data the same way
## on every peer, so nothing about it is replicated after the spawn. Touching
## the star destroys a ship and burns up rocks and shots. Energy recharges
## faster the closer you are, and engines and guns spend it.

const CENTER := Vector2.ZERO
## Touching this destroys a ship (and burns rocks and shots).
const RADIUS: float = 90.0
## Pull = GRAVITY / r² (px/s²), capped at MAX_PULL. At 900 px that's ~90 (a
## nudge); from ~425 px in it's the full MAX_PULL, just under the weakest
## hull's thrust (the Gunship's 440), so any ship's engines can still climb
## out at full throttle, slowly (if it has the energy: near the star it
## recharges faster than the main engine burns).
const GRAVITY: float = 7.2e7
const MAX_PULL: float = 400.0
## Nobody (re)spawns closer than this.
const SAFE_RADIUS: float = 900.0

# --- energy -------------------------------------------------------------------

const ENERGY_MAX: float = 100.0
## Recharge per second: RECHARGE_NEAR within NEAR_RADIUS, falling off as
## 1/distance beyond it (half at twice the distance), never below RECHARGE_MIN.
const RECHARGE_NEAR: float = 40.0
const NEAR_RADIUS: float = 400.0
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


## A rock's path under gravity, from its spawn data (origin, velocity, born).
## Every peer takes the same fixed STEPs from the same start, so they all
## agree on where it is without replicating it: forward in whole steps to the
## time asked, then a straight-line coast for the remainder. Asking for an
## earlier time than the last step (a client's render time can slew back a
## little) coasts backwards from there. Steps are kept, so following a rock
## through time costs one step per STEP; a late joiner pays for a rock's
## whole life once.
class Fall:
	const STEP: float = 1.0 / 30.0

	var origin: Vector2
	var born: float
	var t: float
	var pos: Vector2
	var vel: Vector2

	func _init(p_origin: Vector2, p_velocity: Vector2, p_born: float) -> void:
		origin = p_origin
		born = p_born
		t = p_born
		pos = p_origin
		vel = p_velocity

	func position_at(at: float) -> Vector2:
		if at <= born:
			return origin
		_advance(at)
		return pos + vel * (at - t)

	func velocity_at(at: float) -> Vector2:
		_advance(at)
		return vel

	func _advance(at: float) -> void:
		while t + STEP <= at:
			vel += SpaceStar.pull(pos) * STEP
			pos += vel * STEP
			t += STEP


## Energy per second for this much engine use (push: -1 brake .. 1 thrust;
## side: -1 .. 1 strafe).
static func engine_cost(push: float, side: float) -> float:
	var main: float = push * THRUST_COST if push > 0.0 else -push * REVERSE_COST
	return main + absf(side) * STRAFE_COST
