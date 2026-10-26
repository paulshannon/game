class_name SpaceEntity
extends Node2D
## An asteroid, a shot or a pickup. Spawned by the server through the arena's
## EntitySpawner; removing the node on the server despawns it everywhere.
##
## Each one moves on a fixed path from its spawn data (SpaceSim), so nothing
## is replicated after the spawn: any peer computes its position at any
## server time. Clients draw it at the same server time as the ships
## (the arena's shared SnapshotClock), INTERP_DELAY in the past.
##
## That delay is why a client keeps a "ghost" for a moment after the despawn
## arrives: the server removed the entity at its "now", but the client is
## still drawing the past. The ghost (built from the same data, outside the
## replicated tree) keeps drawing until the client's render time reaches the
## removal, then plays the effect (an asteroid explodes) and goes. So shots
## and asteroids vanish where they visibly meet, not ~100 ms before.

enum Kind { ASTEROID, SHOT, PICKUP }

const PACK: String = "res://assets/kenney/space-shooter-remastered/PNG/"
const METEORS: Array[Array] = [   # by size: small, medium, large
	["Meteors/meteorBrown_small1.png", "Meteors/meteorBrown_small2.png", "Meteors/meteorGrey_small1.png"],
	["Meteors/meteorBrown_med1.png", "Meteors/meteorBrown_med3.png", "Meteors/meteorGrey_med2.png"],
	["Meteors/meteorBrown_big1.png", "Meteors/meteorBrown_big2.png", "Meteors/meteorBrown_big3.png",
			"Meteors/meteorBrown_big4.png", "Meteors/meteorGrey_big1.png"],
]
## By shooter colour (SpaceShip.COLORS: blue, green, orange, red).
const LASERS: Array[String] = ["Lasers/laserBlue01.png", "Lasers/laserGreen11.png",
		"Lasers/laserRed01.png", "Lasers/laserRed16.png"]
## By pickup kind (SpaceSim.RAPID, SHIELD, STAR).
const PICKUPS: Array[String] = ["Power-ups/powerupBlue_bolt.png",
		"Power-ups/powerupGreen_shield.png", "Power-ups/powerupYellow_star.png"]

var kind: int = Kind.ASTEROID
var id: int = 0
var origin: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
## Server time it was spawned at.
var born: float = 0.0
## Asteroid size, pickup kind, or the shooter's slot for shots.
var variant: int = 0
## Shots: the peer that fired (scores the hit). 0 otherwise.
var owner_peer: int = 0

var _data: Dictionary = {}
## Asteroids: their path under the star's gravity (same steps on every peer).
var _fall: SpaceStar.Fall = null
var _clock: SnapshotClock = null
var _fx: SpaceFx = null
var _ghost_until: float = INF
var _shown: bool = false


## Spawn data: small primitives only (sent to every client, and to late joiners).
static func make_data(p_kind: int, p_id: int, p_origin: Vector2, p_velocity: Vector2,
		p_born: float, p_variant: int, p_owner: int = 0) -> Dictionary:
	return {"k": p_kind, "n": p_id, "p": p_origin, "v": p_velocity, "t": p_born,
			"s": p_variant, "o": p_owner}


## Every peer, before the node enters the tree.
func setup(data: Dictionary) -> void:
	_data = data
	kind = int(data["k"])
	id = int(data["n"])
	origin = data["p"]
	velocity = data["v"]
	born = float(data["t"])
	variant = int(data["s"])
	owner_peer = int(data["o"])
	if kind == Kind.ASTEROID:
		_fall = SpaceStar.Fall.new(origin, velocity, born)
	name = "E%d" % id
	position = position_at(born)


## Clients: draw on `clock`'s timeline. A ghost stops at `ghost_until`.
func setup_client(clock: SnapshotClock, fx: SpaceFx, ghost_until: float = INF, shown: bool = false) -> void:
	_clock = clock
	_fx = fx
	_ghost_until = ghost_until
	_shown = shown
	visible = false
	_build_visuals()


func is_ghost() -> bool:
	return _ghost_until < INF


func radius() -> float:
	match kind:
		Kind.ASTEROID:
			return SpaceSim.asteroid_radius(variant)
		Kind.SHOT:
			return SpaceSim.SHOT_RADIUS
	return SpaceSim.PICKUP_RADIUS


## Its velocity at a server time (asteroids: bent by gravity since the spawn).
func velocity_at(server_time: float) -> Vector2:
	return _fall.velocity_at(server_time) if _fall != null else velocity


func age(server_time: float) -> float:
	return server_time - born


## Where it is at a server time (held at its origin before it was born).
## Asteroids fall towards the star; shots fly straight; pickups stay put.
func position_at(server_time: float) -> Vector2:
	var a: float = maxf(age(server_time), 0.0)
	match kind:
		Kind.ASTEROID:
			return _fall.position_at(server_time)
		Kind.SHOT:
			return SpaceSim.shot_position(origin, velocity, a)
	return origin


func _process(_delta: float) -> void:
	if _clock == null or not _clock.is_synced():
		return
	var t: float = _clock.render_time(PlayerNet.now())
	if t >= _ghost_until:
		if kind == Kind.ASTEROID and _shown:
			_fx.explode(global_position, radius())
		queue_free()
		return
	visible = t >= born
	if not visible:
		return
	if not _shown:
		_shown = true
		if age(t) < 0.25:   # not for old shots a late joiner is told about
			_fx.on_appeared(self)
	position = position_at(t)
	match kind:
		Kind.ASTEROID:
			rotation = (float(id % 7) - 3.0) * 0.25 * age(t)
		Kind.PICKUP:
			scale = Vector2.ONE * (1.0 + 0.12 * sin(age(t) * 5.0))


func _exit_tree() -> void:
	# Despawned by the server (or the whole game is going away: the ghost
	# layer checks it is still in the tree). The removal happened at about
	# the server's current time, which the client draws INTERP_DELAY later.
	if _fx != null and not is_ghost():
		var removed_at: float = _clock.render_time(PlayerNet.now()) + Protocol.INTERP_DELAY
		_fx.leave_ghost.call_deferred(_data, removed_at, _shown)


## Every texture an entity can use, to load them before play starts.
static func texture_paths() -> Array[String]:
	var out: Array[String] = []
	for sizes: Array in METEORS:
		for path: String in sizes:
			out.append(PACK + path)
	for path: String in LASERS + PICKUPS:
		out.append(PACK + path)
	return out


func _build_visuals() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	match kind:
		Kind.ASTEROID:
			var options: Array = METEORS[clampi(variant, 0, METEORS.size() - 1)]
			sprite.texture = load(PACK + str(options[id % options.size()])) as Texture2D
			var tex: Vector2 = sprite.texture.get_size()
			sprite.scale = Vector2.ONE * (2.2 * radius() / maxf(tex.x, tex.y))
		Kind.SHOT:
			sprite.texture = load(PACK + LASERS[variant % LASERS.size()]) as Texture2D
			sprite.rotation = velocity.angle() + PI / 2.0   # the art points up
			sprite.scale = Vector2.ONE * 0.6
		_:
			sprite.texture = load(PACK + PICKUPS[clampi(variant, 0, PICKUPS.size() - 1)]) as Texture2D
	add_child(sprite)
