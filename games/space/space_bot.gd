class_name SpaceBot
extends BotInput
## Smoke-test pilot for the space game: turns toward the nearest asteroid it
## can see, thrusts when far, brakes when close, and fires when lined up. So
## the bots really shoot rocks and score over the network, proving the whole
## loop (input -> server rules -> spawns/despawns/score -> client).
## Sees only what this client draws, like a player. Wanders when there is
## nothing to aim at.

var _ship: SpaceShip
var _arena: SpaceArena


func _init(ship: SpaceShip, arena: SpaceArena) -> void:
	super(ship.peer_id())
	_ship = ship
	_arena = arena


func update(delta: float) -> void:
	var target: SpaceEntity = _nearest_asteroid()
	if target == null or not _ship.is_alive():
		super.update(delta)
		fire = false
		return
	var to: Vector2 = target.position - _ship.position
	var off: float = angle_difference(_ship.rendered_rotation(), to.angle())
	var dist: float = to.length()
	move.x = clampf(off * 3.0, -1.0, 1.0)
	if dist > 320.0:
		move.y = -0.8          # close in
	elif dist < 130.0:
		move.y = 0.6           # brake / back off
	else:
		move.y = -0.2
	fire = absf(off) < 0.3 and dist < 700.0
	jump = false


func _nearest_asteroid() -> SpaceEntity:
	var best: SpaceEntity = null
	var best_d: float = INF
	for n: Node in _arena.entities_root.get_children():
		var e: SpaceEntity = n as SpaceEntity
		if e == null or e.kind != SpaceEntity.Kind.ASTEROID or not e.visible:
			continue
		var d: float = e.position.distance_squared_to(_ship.position)
		if d < best_d:
			best_d = d
			best = e
	return best
