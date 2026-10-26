class_name SpaceDirector
extends Node
## Server only: runs the space match around the ships. Fills the asteroid
## belts round the star and tops them up as rocks are shot (SpaceBelts),
## turns ship shots into SHOT entities, and resolves every
## collision (shot/asteroid, shot/ship of another team, ship/asteroid,
## ship/pickup, anything/star) with SpaceSim and SpaceStar rules.
## Clients never decide a hit or a score; they only see the results as
## spawns, despawns and replicated ship state.
##
## Sits after Players in the tree, so its physics tick runs after every ship
## has moved this tick.

const ASTEROID_INTERVAL: float = 0.5  # at most one new rock this often
const PICKUP_CHANCE: float = 0.15     # per destroyed asteroid

var arena: SpaceArena

## Smoke-test and log counters.
var shots_fired: Dictionary = {}      # peer id -> shots
var asteroids_destroyed: int = 0
var ships_destroyed: int = 0
var pvp_hits: int = 0                 # shots that hit a ship (shield or not)
var pvp_kills: int = 0
var star_deaths: int = 0              # ships that flew into the star
var star_burns: int = 0               # rocks and shots it swallowed
var rocks_escaped: int = 0            # flung beyond SpaceBelts.ESCAPE_RADIUS
var pickups_taken: int = 0
## Peer id -> score, latched as it changes so it outlives the player leaving.
var scores: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _spawn_timer: float = 0.0


func _init() -> void:
	name = "Director"
	_rng.seed = 16


## The belts, full, before anyone joins.
func start() -> void:
	for ring: int in SpaceBelts.RINGS.size():
		for i: int in int(SpaceBelts.RINGS[ring].z):
			_spawn_belt_rock(SpaceBelts.point_in(ring, _rng.randf(), _rng.randf()), PlayerNet.now())


func fire(ship: SpaceShip) -> void:
	var s: SpaceSim.Ship = ship.state
	_spawn(SpaceEntity.Kind.SHOT, SpaceSim.shot_origin(s), SpaceSim.shot_velocity(s),
			PlayerNet.now(), ship.color_index(), ship.peer_id())
	shots_fired[ship.peer_id()] = int(shots_fired.get(ship.peer_id(), 0)) + 1


## A rock at `at` moving at `velocity` at server time `born`: it orbits the
## star from there (SpaceOrbit).
func spawn_asteroid(size: int, at: Vector2, velocity: Vector2, born: float) -> void:
	_spawn(SpaceEntity.Kind.ASTEROID, at, velocity, born, size)


## A new belt rock: a random size, at or near circular speed.
func _spawn_belt_rock(at: Vector2, born: float) -> void:
	spawn_asteroid(SpaceBelts.size_for(_rng.randf()), at,
			SpaceBelts.spawn_velocity(at, _rng.randf(), _rng.randf()), born)


func _spawn(kind: int, at: Vector2, velocity: Vector2, born: float, variant: int, owner: int = 0) -> void:
	arena.entity_spawner.spawn(SpaceEntity.make_data(kind, _next_id, at, velocity, born, variant, owner))
	_next_id += 1


func _physics_process(delta: float) -> void:
	var now: float = PlayerNet.now()
	var rocks: Array[SpaceEntity] = []
	var shots: Array[SpaceEntity] = []
	var pickups: Array[SpaceEntity] = []
	for n: Node in arena.entities_root.get_children():
		var e: SpaceEntity = n as SpaceEntity
		if e == null or e.is_queued_for_deletion():
			continue
		match e.kind:
			SpaceEntity.Kind.ASTEROID:
				rocks.append(e)
			SpaceEntity.Kind.SHOT:
				shots.append(e)
			_:
				pickups.append(e)

	_tend_belts(rocks, now, delta)

	var ships: Array[SpaceShip] = _ships()
	for shot: SpaceEntity in shots:
		# Swept: the whole path the shot covered this tick (~15-20 px, more
		# than a small rock's hit radius), not just where it ended up.
		var age: float = shot.age(now)
		var from: Vector2 = SpaceSim.shot_position(shot.origin, shot.velocity, maxf(age - delta, 0.0))
		var to: Vector2 = SpaceSim.shot_position(shot.origin, shot.velocity, minf(age, SpaceSim.SHOT_LIFE))
		for rock: SpaceEntity in rocks:
			if not rock.is_queued_for_deletion() and SpaceSim.sweep_hits(from, to, SpaceSim.SHOT_RADIUS,
					rock.position_at(now), rock.radius()):
				_destroy_asteroid(rock, now, _ship_of(shot.owner_peer))
				shot.queue_free()
				break
		if not shot.is_queued_for_deletion():
			for ship: SpaceShip in ships:
				# A shot's variant is its shooter's team (colour), which
				# outlives the shooter leaving.
				if SpaceSim.shot_can_hit(shot.variant, ship.state) and SpaceSim.sweep_hits(from, to,
						SpaceSim.SHOT_RADIUS, ship.state.position, SpaceSim.SHIP_RADIUS):
					_shoot_ship(ship, _ship_of(shot.owner_peer))
					shot.queue_free()
					break
		if not shot.is_queued_for_deletion() and SpaceStar.touches(to, SpaceSim.SHOT_RADIUS):
			star_burns += 1
			shot.queue_free()
		if not shot.is_queued_for_deletion() and SpaceSim.shot_expired(age):
			shot.queue_free()

	for ship: SpaceShip in ships:
		var s: SpaceSim.Ship = ship.state
		if not s.alive:
			continue
		if SpaceStar.touches(s.position, SpaceSim.SHIP_RADIUS):
			SpaceSim.destroy(s)   # no shield or spawn protection saves you
			ships_destroyed += 1
			star_deaths += 1
			print("[server] P%d flew into the star" % [ship.player_index() + 1])
			continue
		for rock: SpaceEntity in rocks:
			if rock.is_queued_for_deletion() or not SpaceSim.can_be_hit(s):
				continue
			if SpaceSim.overlaps(s.position, SpaceSim.SHIP_RADIUS, rock.position_at(now), rock.radius()):
				_destroy_asteroid(rock, now, null)
				if SpaceSim.hit_ship(s):
					ships_destroyed += 1
					print("[server] P%d destroyed (score %d)" % [ship.player_index() + 1, s.score])
		for pickup: SpaceEntity in pickups:
			if not pickup.is_queued_for_deletion() and s.alive \
					and SpaceSim.overlaps(s.position, SpaceSim.SHIP_RADIUS, pickup.position_at(now), SpaceSim.PICKUP_RADIUS):
				SpaceSim.apply_pickup(s, pickup.variant)
				scores[ship.peer_id()] = s.score
				ship.pickups += 1
				pickups_taken += 1
				pickup.queue_free()

	for pickup: SpaceEntity in pickups:
		if not pickup.is_queued_for_deletion() and pickup.age(now) >= SpaceSim.PICKUP_LIFE:
			pickup.queue_free()


## PvP: the shield takes the hit, or the ship is destroyed and `shooter`
## (null if they left) scores.
func _shoot_ship(ship: SpaceShip, shooter: SpaceShip) -> void:
	pvp_hits += 1
	if not SpaceSim.hit_ship(ship.state):
		return
	ships_destroyed += 1
	pvp_kills += 1
	if shooter != null:
		shooter.state.score += SpaceSim.SHIP_KILL_POINTS
		scores[shooter.peer_id()] = shooter.state.score
	print("[server] P%d shot down P%d" % [shooter.player_index() + 1 if shooter != null else 0,
			ship.player_index() + 1])


## Score it to `scorer` (null for a ram), break it into two pieces kicked
## apart at random (onto new orbits, some wild), maybe drop a pickup (which
## carries on along the rock's orbit).
func _destroy_asteroid(rock: SpaceEntity, now: float, scorer: SpaceShip) -> void:
	var at: Vector2 = rock.position_at(now)
	var velocity: Vector2 = rock.velocity_at(now)
	if scorer != null:
		scorer.state.score += SpaceSim.asteroid_points(rock.variant)
		scores[scorer.peer_id()] = scorer.state.score
	for piece: Array in SpaceBelts.split(rock.variant, at, velocity, _rng.randf() * TAU, _rng.randf()):
		spawn_asteroid(rock.variant - 1, piece[0], piece[1], now)
	if _rng.randf() < PICKUP_CHANCE:
		_spawn(SpaceEntity.Kind.PICKUP, at, velocity, now, _rng.randi() % SpaceSim.PICKUP_KINDS)
	asteroids_destroyed += 1
	rock.queue_free()


func _ships() -> Array[SpaceShip]:
	var out: Array[SpaceShip] = []
	for p: Node in arena.active_players():
		var ship: SpaceShip = p as SpaceShip
		if ship != null:
			out.append(ship)
	return out


func _ship_of(peer: int) -> SpaceShip:
	var p: Node = arena.players_root.get_node_or_null(str(peer))
	return p as SpaceShip if p != null and not p.is_queued_for_deletion() else null


## Burn rocks that dived into the star, drop ones that escaped, and top the
## belts up: when a ring is short of rocks, a new one appears in it (one per
## ASTEROID_INTERVAL), somewhere off every ship's screen.
func _tend_belts(rocks: Array[SpaceEntity], now: float, delta: float) -> void:
	var positions := PackedVector2Array()
	for rock: SpaceEntity in rocks:
		var at: Vector2 = rock.position_at(now)
		if SpaceStar.touches(at, rock.radius()):
			star_burns += 1   # dived in: clients that can see it watch it burst
			rock.queue_free()
		elif SpaceBelts.escaped(at):
			rocks_escaped += 1   # flung out of the system: off everyone's screen
			rock.queue_free()
		else:
			positions.append(at)
	_spawn_timer -= delta
	if _spawn_timer > 0.0 or positions.size() >= SpaceBelts.target_total() * SpaceBelts.MAX_OVERFILL:
		return
	var ring: int = SpaceBelts.neediest(SpaceBelts.counts(positions))
	if ring == -1:
		return
	_spawn_timer = ASTEROID_INTERVAL
	var ships := PackedVector2Array()
	for ship: SpaceShip in _ships():
		ships.append(ship.state.position)
	for attempt: int in 12:
		var at: Vector2 = SpaceBelts.point_in(ring, _rng.randf(), _rng.randf())
		if SpaceBelts.is_clear(at, ships):
			_spawn_belt_rock(at, now)
			return
