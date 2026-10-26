class_name SpaceDirector
extends Node
## Server only: runs the space match around the ships. Keeps the unbounded
## asteroid field topped up around every ship and removes rocks left far
## behind (SpaceField), turns ship shots into SHOT entities, and resolves every
## collision (shot/asteroid, ship/asteroid, ship/pickup) with SpaceSim rules.
## Clients never decide a hit or a score; they only see the results as
## spawns, despawns and replicated ship state.
##
## Sits after Players in the tree, so its physics tick runs after every ship
## has moved this tick.

const ASTEROID_INTERVAL: float = 0.5  # at most one new rock this often
const ASTEROID_SPEED := Vector2(45.0, 100.0)
## The first rocks, around the origin before anyone joins: close enough to
## shoot at once (players start 160 px out).
const START_DISTANCE := Vector2(350.0, SpaceField.ENTRY_DISTANCE)
const PICKUP_CHANCE: float = 0.15     # per destroyed asteroid

var arena: SpaceArena

## Smoke-test and log counters.
var shots_fired: Dictionary = {}      # peer id -> shots
var asteroids_destroyed: int = 0
var asteroids_dropped: int = 0        # left far behind (SpaceField.is_stray)
var ships_destroyed: int = 0
var pickups_taken: int = 0
## Peer id -> score, latched as it changes so it outlives the player leaving.
var scores: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _spawn_timer: float = 0.0


func _init() -> void:
	name = "Director"
	_rng.seed = 16


## The initial field, before anyone joins.
func start() -> void:
	for i: int in SpaceField.ROCKS_PER_ANCHOR:
		var at: Vector2 = SpaceField.entry_point(Vector2.ZERO, _rng.randf() * TAU,
				_rng.randf_range(START_DISTANCE.x, START_DISTANCE.y))
		spawn_asteroid(SpaceSim.LARGE, at, _random_velocity(), PlayerNet.now())


func fire(ship: SpaceShip) -> void:
	var s: SpaceSim.Ship = ship.state
	_spawn(SpaceEntity.Kind.SHOT, SpaceSim.shot_origin(s), SpaceSim.shot_velocity(s),
			PlayerNet.now(), ship.player_index() % SpaceShip.COLORS.size(), ship.peer_id())
	shots_fired[ship.peer_id()] = int(shots_fired.get(ship.peer_id(), 0)) + 1


func spawn_asteroid(size: int, at: Vector2, velocity: Vector2, born: float) -> void:
	_spawn(SpaceEntity.Kind.ASTEROID, at, velocity, born, size)


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

	_tend_field(rocks, now, delta)

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
		if not shot.is_queued_for_deletion() and SpaceSim.shot_expired(age):
			shot.queue_free()

	for ship: SpaceShip in _ships():
		var s: SpaceSim.Ship = ship.state
		if not s.alive:
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
					and SpaceSim.overlaps(s.position, SpaceSim.SHIP_RADIUS, pickup.origin, SpaceSim.PICKUP_RADIUS):
				SpaceSim.apply_pickup(s, pickup.variant)
				scores[ship.peer_id()] = s.score
				ship.pickups += 1
				pickups_taken += 1
				pickup.queue_free()

	for pickup: SpaceEntity in pickups:
		if not pickup.is_queued_for_deletion() and pickup.age(now) >= SpaceSim.PICKUP_LIFE:
			pickup.queue_free()


## Score it to `scorer` (null for a ram), split it, maybe drop a pickup.
func _destroy_asteroid(rock: SpaceEntity, now: float, scorer: SpaceShip) -> void:
	var at: Vector2 = rock.position_at(now)
	if scorer != null:
		scorer.state.score += SpaceSim.asteroid_points(rock.variant)
		scores[scorer.peer_id()] = scorer.state.score
	for v: Vector2 in SpaceSim.split_velocities(rock.variant, rock.velocity):
		spawn_asteroid(rock.variant - 1, at, v, now)
	if _rng.randf() < PICKUP_CHANCE:
		_spawn(SpaceEntity.Kind.PICKUP, at, Vector2.ZERO, now, _rng.randi() % SpaceSim.PICKUP_KINDS)
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


## Where the field is kept: every ship (parked where it was destroyed, if
## it was), or the origin while nobody plays.
func _anchors() -> PackedVector2Array:
	var out := PackedVector2Array()
	for ship: SpaceShip in _ships():
		out.append(ship.state.position)
	if out.is_empty():
		out.append(Vector2.ZERO)
	return out


## Drop rocks nobody is near any more, and bring a new one in for the ship
## with the emptiest surroundings. A removed rock explodes on clients only if
## it's on their screen (SpaceFx), and a stray is off everyone's.
func _tend_field(rocks: Array[SpaceEntity], now: float, delta: float) -> void:
	var anchors: PackedVector2Array = _anchors()
	var positions := PackedVector2Array()
	for rock: SpaceEntity in rocks:
		var at: Vector2 = rock.position_at(now)
		if SpaceField.is_stray(at, anchors):
			asteroids_dropped += 1
			rock.queue_free()
		else:
			positions.append(at)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	var needy: int = SpaceField.neediest(anchors, positions)
	if needy == -1:
		return
	_spawn_timer = ASTEROID_INTERVAL
	var anchor: Vector2 = anchors[needy]
	var at: Vector2 = SpaceField.entry_point(anchor, _rng.randf() * TAU)
	for attempt: int in 12:
		if SpaceField.is_clear(at, anchors):
			break
		at = SpaceField.entry_point(anchor, _rng.randf() * TAU)
	var speed: float = _rng.randf_range(ASTEROID_SPEED.x, ASTEROID_SPEED.y)
	spawn_asteroid(SpaceSim.LARGE, at, SpaceField.entry_velocity(at, anchor, _rng.randf_range(-1.0, 1.0), speed), now)


func _random_velocity() -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(ASTEROID_SPEED.x, ASTEROID_SPEED.y)
