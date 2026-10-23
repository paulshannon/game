class_name SpaceSim
extends RefCounted
## Pure rules for the space game: ships with momentum, shots, asteroids that
## split, pickups and score. No nodes, no networking: the server runs these,
## tests call them directly, and client-side prediction could reuse them.
##
## Asteroids, shots and pickups move on fixed paths from their spawn data
## (origin, velocity, birth time), so any peer can work out where one is at
## any server time without per-tick replication: see asteroid_position().

## The playfield. Ships bounce off its edges, asteroids too; shots leave it.
const BOUNDS := Rect2(-600.0, -320.0, 1200.0, 640.0)

# --- ships --------------------------------------------------------------------

const TURN_SPEED: float = 4.2         # rad/s at full left/right
const THRUST: float = 560.0           # px/s² at full forward
const REVERSE_THRUST: float = 240.0   # px/s² at full back (a brake, mostly)
const MAX_SPEED: float = 440.0
const DRAG: float = 0.5               # 1/s: coasting keeps momentum, but not forever
const WALL_BOUNCE: float = 0.5        # speed kept when bouncing off the edge
const SHIP_RADIUS: float = 18.0

const RESPAWN_TIME: float = 2.0
const SPAWN_PROTECTION: float = 2.0   # invulnerable after (re)spawning
const SHIELD_GRACE: float = 1.0       # invulnerable after the shield absorbs a hit

# --- shots --------------------------------------------------------------------

const FIRE_COOLDOWN: float = 0.25
const RAPID_COOLDOWN: float = 0.1
const SHOT_SPEED: float = 820.0
const SHOT_LIFE: float = 0.9
const SHOT_RADIUS: float = 4.0
const MUZZLE: float = 26.0            # shots start this far ahead of the ship

# --- asteroids ----------------------------------------------------------------

const SMALL: int = 0
const MEDIUM: int = 1
const LARGE: int = 2
const ASTEROID_RADIUS: Array[float] = [13.0, 21.0, 40.0]
const ASTEROID_POINTS: Array[int] = [100, 50, 20]
const SPLIT_ANGLE: float = 0.6        # children fly off this far either side
const SPLIT_SPEEDUP: float = 1.35

# --- pickups ------------------------------------------------------------------

const RAPID: int = 0     # faster fire for RAPID_TIME
const SHIELD: int = 1    # absorbs one hit
const STAR: int = 2      # STAR_POINTS
const PICKUP_KINDS: int = 3
const RAPID_TIME: float = 8.0
const STAR_POINTS: int = 250
const PICKUP_RADIUS: float = 16.0
const PICKUP_LIFE: float = 12.0


class Ship:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	## Facing angle; 0 points along +x, like Vector2.angle().
	var rotation: float = -PI / 2.0
	var alive: bool = true
	var thrusting: bool = false
	var cooldown: float = 0.0
	var respawn_in: float = 0.0
	var protected_for: float = 0.0
	var shield: bool = false
	var rapid_for: float = 0.0
	var score: int = 0


static func facing(s: Ship) -> Vector2:
	return Vector2.from_angle(s.rotation)


## One tick. move.x turns, -move.y thrusts (up = forward, down = brake), the
## same stick or keys as the box games. Returns true when the ship fires.
static func step_ship(s: Ship, move: Vector2, fire: bool, delta: float) -> bool:
	s.cooldown = maxf(s.cooldown - delta, 0.0)
	s.protected_for = maxf(s.protected_for - delta, 0.0)
	s.rapid_for = maxf(s.rapid_for - delta, 0.0)
	if not s.alive:
		s.respawn_in = maxf(s.respawn_in - delta, 0.0)
		s.thrusting = false
		return false

	var m: Vector2 = ArenaSim.sanitize_move(move)
	s.rotation = wrapf(s.rotation + m.x * TURN_SPEED * delta, -PI, PI)
	var push: float = -m.y
	s.thrusting = push > 0.1
	var accel: float = THRUST if push > 0.0 else REVERSE_THRUST
	s.velocity += facing(s) * push * accel * delta
	s.velocity = (s.velocity * exp(-DRAG * delta)).limit_length(MAX_SPEED)
	s.position += s.velocity * delta
	_bounce(s)

	if fire and s.cooldown <= 0.0:
		s.cooldown = RAPID_COOLDOWN if s.rapid_for > 0.0 else FIRE_COOLDOWN
		return true
	return false


static func _bounce(s: Ship) -> void:
	var r: Rect2 = BOUNDS.grow(-SHIP_RADIUS)
	if s.position.x < r.position.x or s.position.x > r.end.x:
		s.position.x = clampf(s.position.x, r.position.x, r.end.x)
		s.velocity.x = -s.velocity.x * WALL_BOUNCE
	if s.position.y < r.position.y or s.position.y > r.end.y:
		s.position.y = clampf(s.position.y, r.position.y, r.end.y)
		s.velocity.y = -s.velocity.y * WALL_BOUNCE


static func can_respawn(s: Ship) -> bool:
	return not s.alive and s.respawn_in <= 0.0


static func respawn(s: Ship, at: Vector2) -> void:
	s.alive = true
	s.position = at
	s.velocity = Vector2.ZERO
	s.rotation = -PI / 2.0
	s.protected_for = SPAWN_PROTECTION
	s.shield = false
	s.rapid_for = 0.0
	s.cooldown = 0.0


static func can_be_hit(s: Ship) -> bool:
	return s.alive and s.protected_for <= 0.0


## An asteroid hit the ship. The shield absorbs it; otherwise the ship is
## destroyed and parked at `respawn_at` (hidden) until it respawns there.
## Returns true when the ship was destroyed.
static func hit_ship(s: Ship, respawn_at: Vector2) -> bool:
	if not can_be_hit(s):
		return false
	if s.shield:
		s.shield = false
		s.protected_for = SHIELD_GRACE
		return false
	s.alive = false
	s.thrusting = false
	s.respawn_in = RESPAWN_TIME
	s.velocity = Vector2.ZERO
	s.position = respawn_at
	return true


## Where a shot starts and how it flies (it keeps the ship's momentum).
static func shot_origin(s: Ship) -> Vector2:
	return s.position + facing(s) * MUZZLE


static func shot_velocity(s: Ship) -> Vector2:
	return facing(s) * SHOT_SPEED + s.velocity


static func shot_position(origin: Vector2, velocity: Vector2, age: float) -> Vector2:
	return origin + velocity * age


static func shot_expired(origin: Vector2, velocity: Vector2, age: float) -> bool:
	return age >= SHOT_LIFE or not BOUNDS.has_point(shot_position(origin, velocity, age))


## An asteroid drifts in a straight line and bounces off the edges. Computed in
## closed form from its spawn data, so it needs no state and no replication.
static func asteroid_position(origin: Vector2, velocity: Vector2, age: float, size: int) -> Vector2:
	var r: Rect2 = BOUNDS.grow(-asteroid_radius(size))
	return Vector2(
			_reflect(origin.x, velocity.x * age, r.position.x, r.end.x),
			_reflect(origin.y, velocity.y * age, r.position.y, r.end.y))


## Position after travelling `distance` from `x` between walls lo and hi:
## a triangle wave with period 2 * (hi - lo).
static func _reflect(x: float, distance: float, lo: float, hi: float) -> float:
	var span: float = hi - lo
	if span <= 0.0:
		return lo
	var u: float = fposmod(clampf(x, lo, hi) - lo + distance, 2.0 * span)
	return lo + (u if u <= span else 2.0 * span - u)


static func asteroid_radius(size: int) -> float:
	return ASTEROID_RADIUS[clampi(size, SMALL, LARGE)]


static func asteroid_points(size: int) -> int:
	return ASTEROID_POINTS[clampi(size, SMALL, LARGE)]


## Velocities of the pieces a destroyed asteroid breaks into (empty for the
## smallest size): two faster pieces either side of its heading.
static func split_velocities(size: int, velocity: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if size <= SMALL:
		return out
	out.append(velocity.rotated(SPLIT_ANGLE) * SPLIT_SPEEDUP)
	out.append(velocity.rotated(-SPLIT_ANGLE) * SPLIT_SPEEDUP)
	return out


static func overlaps(a: Vector2, radius_a: float, b: Vector2, radius_b: float) -> bool:
	return a.distance_squared_to(b) <= (radius_a + radius_b) * (radius_a + radius_b)


static func apply_pickup(s: Ship, kind: int) -> void:
	match kind:
		RAPID:
			s.rapid_for = RAPID_TIME
		SHIELD:
			s.shield = true
		STAR:
			s.score += STAR_POINTS
