class_name SpaceSim
extends RefCounted
## Pure rules for the space game: ships with momentum, shots, asteroids that
## split, pickups and score. No nodes, no networking: the server runs these,
## tests call them directly, and client-side prediction could reuse them.
##
## Asteroids, shots and pickups move on paths fixed by their spawn data
## (origin, velocity, birth time), so any peer can work out where one is at
## any server time without per-tick replication: shots fly straight
## (shot_position), asteroids and pickups orbit the star
## (SpaceOrbit) in belts (SpaceBelts).
##
## Space is unbounded: nothing has an edge to bounce off.

# --- ships --------------------------------------------------------------------

# The all-rounder's handling (hull FALCON); the other hulls trade these off.
const TURN_SPEED: float = 4.2         # rad/s at full left/right
const THRUST: float = 560.0           # px/s² at full forward
const REVERSE_THRUST: float = 240.0   # px/s² at full back (a brake, mostly)
## Sideways thrust (strafe), as a share of the hull's forward thrust.
const STRAFE_FACTOR: float = 0.6
## There's no drag and no speed cap: a ship coasts on for ever, and only its
## own engines (and the star's pull) change its speed.
const SHIP_RADIUS: float = 18.0

const RESPAWN_TIME: float = 2.0
const SPAWN_PROTECTION: float = 2.0   # invulnerable after (re)spawning
const SHIELD_GRACE: float = 1.0       # invulnerable after the shield absorbs a hit
const SHIP_KILL_POINTS: int = 200     # shooting down a ship of another team

# --- shots --------------------------------------------------------------------

const FIRE_COOLDOWN: float = 0.25    # the all-rounder's; see HULLS
const RAPID_COOLDOWN: float = 0.1
const SHOT_SPEED: float = 820.0
const SHOT_LIFE: float = 0.9
const SHOT_RADIUS: float = 4.0
const MUZZLE: float = 26.0            # shots start this far ahead of the ship

# --- hulls: the ship a player picks when joining -----------------------------

const FALCON: int = 0
const COMET: int = 1
const HORNET: int = 2
const GUNSHIP: int = 3
## By hull: name and one line for the menu, and handling. Collision size and
## shots are the same for every hull, so none is harder to hit.
const HULLS: Array[Dictionary] = [
	{"name": "Falcon", "blurb": "All-rounder", "thrust": THRUST,
		"turn": TURN_SPEED, "cooldown": FIRE_COOLDOWN},
	{"name": "Comet", "blurb": "Fastest, slow to fire", "thrust": 700.0,
		"turn": 3.8, "cooldown": 0.32},
	{"name": "Hornet", "blurb": "Turns tightest", "thrust": 520.0,
		"turn": 5.6, "cooldown": 0.22},
	{"name": "Gunship", "blurb": "Fires fastest, heavy", "thrust": 440.0,
		"turn": 3.4, "cooldown": 0.15},
]

# --- asteroids ----------------------------------------------------------------

const SMALL: int = 0
const MEDIUM: int = 1
const LARGE: int = 2
const ASTEROID_RADIUS: Array[float] = [13.0, 21.0, 40.0]
const ASTEROID_POINTS: Array[int] = [100, 50, 20]

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
	## Colours are teams (SpaceShip.COLORS index): shots only hit other teams.
	var team: int = 0
	## Which of HULLS (set_hull), and its handling.
	var hull: int = FALCON
	var thrust: float = THRUST
	var turn_speed: float = TURN_SPEED
	var fire_cooldown: float = FIRE_COOLDOWN
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	## Facing angle; 0 points along +x, like Vector2.angle().
	var rotation: float = -PI / 2.0
	var alive: bool = true
	var thrusting: bool = false
	## Firing the reverse thrusters (down on the stick): clients draw RCS puffs.
	var braking: bool = false
	## -1 turning left (anticlockwise), 1 right, 0 not turning. Cosmetic too.
	var turning: int = 0
	## -1 strafing left, 1 right, 0 not. Cosmetic (side thrusters).
	var strafing: int = 0
	var cooldown: float = 0.0
	var respawn_in: float = 0.0
	var protected_for: float = 0.0
	var shield: bool = false
	var rapid_for: float = 0.0
	var score: int = 0
	## Engines and guns spend it; it recharges near the star (SpaceStar).
	var energy: float = SpaceStar.ENERGY_MAX
	## Totals, for the smoke test.
	var energy_used: float = 0.0
	var energy_gained: float = 0.0


## A valid hull for any value a client sends.
static func sanitize_hull(hull: int) -> int:
	return clampi(hull, 0, HULLS.size() - 1)


static func set_hull(s: Ship, hull: int) -> void:
	s.hull = sanitize_hull(hull)
	var h: Dictionary = HULLS[s.hull]
	s.thrust = float(h["thrust"])
	s.turn_speed = float(h["turn"])
	s.fire_cooldown = float(h["cooldown"])


static func facing(s: Ship) -> Vector2:
	return Vector2.from_angle(s.rotation)


## One tick. move.x turns, -move.y thrusts (up = forward, down = brake), the
## same stick or keys as the box games; `strafe` (-1 left .. 1 right) pushes
## sideways. Engines and guns cost energy (SpaceStar): the engines get only
## the power the pool can pay for this tick, and a shot needs a full
## SHOT_COST. The star's gravity pulls every tick. Returns true when the ship
## fires.
static func step_ship(s: Ship, move: Vector2, fire: bool, delta: float, strafe: float = 0.0) -> bool:
	s.cooldown = maxf(s.cooldown - delta, 0.0)
	s.protected_for = maxf(s.protected_for - delta, 0.0)
	s.rapid_for = maxf(s.rapid_for - delta, 0.0)
	if not s.alive:
		s.respawn_in = maxf(s.respawn_in - delta, 0.0)
		_stop_thrusters(s)
		return false

	var gained: float = minf(SpaceStar.recharge_rate(s.position) * delta, SpaceStar.ENERGY_MAX - s.energy)
	s.energy += gained
	s.energy_gained += gained

	var m: Vector2 = ArenaSim.sanitize_move(move)
	s.rotation = wrapf(s.rotation + m.x * s.turn_speed * delta, -PI, PI)   # turning is free
	var push: float = -m.y
	var side: float = clampf(strafe, -1.0, 1.0) if is_finite(strafe) else 0.0
	# Run the engines on what the pool can pay for: all of it, some, or none.
	var need: float = SpaceStar.engine_cost(push, side) * delta
	var power: float = 1.0 if need <= s.energy else s.energy / need
	_spend(s, need * power)
	push *= power
	side *= power
	s.thrusting = push > 0.1
	s.braking = push < -0.1
	s.turning = 0 if absf(m.x) < 0.1 else (1 if m.x > 0.0 else -1)
	var accel: float = s.thrust if push > 0.0 else REVERSE_THRUST
	s.velocity += facing(s) * push * accel * delta
	s.strafing = 0 if absf(side) < 0.1 else (1 if side > 0.0 else -1)
	# Right of the nose: facing turned a quarter clockwise (y is down).
	s.velocity += facing(s).rotated(PI / 2.0) * side * s.thrust * STRAFE_FACTOR * delta
	s.velocity += SpaceStar.pull(s.position) * delta
	s.position += s.velocity * delta

	if fire and s.cooldown <= 0.0 and s.energy >= SpaceStar.SHOT_COST:
		s.cooldown = minf(RAPID_COOLDOWN, s.fire_cooldown) if s.rapid_for > 0.0 else s.fire_cooldown
		_spend(s, SpaceStar.SHOT_COST)
		return true
	return false


static func _spend(s: Ship, amount: float) -> void:
	s.energy = maxf(s.energy - amount, 0.0)
	s.energy_used += amount


static func _stop_thrusters(s: Ship) -> void:
	s.thrusting = false
	s.braking = false
	s.turning = 0
	s.strafing = 0


static func can_respawn(s: Ship) -> bool:
	return not s.alive and s.respawn_in <= 0.0


## Back in at `at`, already on a circular orbit round the star: with no drag,
## a ship left at rest would fall straight in.
static func respawn(s: Ship, at: Vector2) -> void:
	s.alive = true
	s.position = at
	s.velocity = SpaceStar.circular_velocity(at)
	s.rotation = -PI / 2.0
	s.protected_for = SPAWN_PROTECTION
	s.shield = false
	s.rapid_for = 0.0
	s.cooldown = 0.0
	s.energy = SpaceStar.ENERGY_MAX


static func can_be_hit(s: Ship) -> bool:
	return s.alive and s.protected_for <= 0.0


## PvP: whether a shot fired by `shooter_team` hits `target`. Other teams
## only (no friendly fire, so never your own ship), and not while the target
## is protected: the shot flies on through.
static func shot_can_hit(shooter_team: int, target: Ship) -> bool:
	return shooter_team != target.team and can_be_hit(target)


## The team with the fewest ships, of `teams` (ships per team); ties go to
## the first one from `prefer` on, so equal teams fill in turn.
static func smallest_team(teams: Array[int], prefer: int) -> int:
	var best: int = posmod(prefer, teams.size())
	for i: int in teams.size():
		var t: int = posmod(prefer + i, teams.size())
		if teams[t] < teams[best]:
			best = t
	return best


## An asteroid or a shot hit the ship. The shield absorbs it; otherwise the ship is
## destroyed. It stays where it was hit (hidden: clients draw the explosion at
## its position) until respawn() moves it. Moving it now would have clients
## interpolate the ship across the field before it explodes.
## Returns true when the ship was destroyed.
static func hit_ship(s: Ship) -> bool:
	if not can_be_hit(s):
		return false
	if s.shield:
		s.shield = false
		s.protected_for = SHIELD_GRACE
		return false
	destroy(s)
	return true


## Destroyed outright, shield or not (flying into the star).
static func destroy(s: Ship) -> void:
	s.alive = false
	_stop_thrusters(s)
	s.respawn_in = RESPAWN_TIME
	s.velocity = Vector2.ZERO


## Where a shot starts and how it flies (it keeps the ship's momentum).
static func shot_origin(s: Ship) -> Vector2:
	return s.position + facing(s) * MUZZLE


static func shot_velocity(s: Ship) -> Vector2:
	return facing(s) * SHOT_SPEED + s.velocity


static func shot_position(origin: Vector2, velocity: Vector2, age: float) -> Vector2:
	return origin + velocity * age


static func shot_expired(age: float) -> bool:
	return age >= SHOT_LIFE



static func asteroid_radius(size: int) -> float:
	return ASTEROID_RADIUS[clampi(size, SMALL, LARGE)]


static func asteroid_points(size: int) -> int:
	return ASTEROID_POINTS[clampi(size, SMALL, LARGE)]


## Whether something of `radius` moving from `from` to `to` in one tick
## touches the circle at `center`: the closest point of the segment, so a fast
## shot can't step over a small rock between two ticks.
static func sweep_hits(from: Vector2, to: Vector2, radius: float, center: Vector2, center_radius: float) -> bool:
	var seg: Vector2 = to - from
	var len_sq: float = seg.length_squared()
	var u: float = 0.0 if len_sq == 0.0 else clampf((center - from).dot(seg) / len_sq, 0.0, 1.0)
	return overlaps(from + seg * u, radius, center, center_radius)


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
