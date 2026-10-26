class_name SpaceBot
extends BotInput
## Smoke-test pilot for the space game: turns toward the nearest asteroid it
## can see, thrusts when far, brakes when close, and fires when lined up. So
## the bots really shoot rocks and score over the network, proving the whole
## loop (input -> server rules -> spawns/despawns/score -> client).
## On a client (smoke-test bots) it sees only what that client draws, like a
## player. The server flies its own bots (ServerBots) with it too: there it
## reads the rocks' positions at the current server time. Wanders when there
## is nothing to aim at.

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
	var to: Vector2 = _where(target) - _ship.position
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
		if e == null or e.kind != SpaceEntity.Kind.ASTEROID or not (_arena.config.is_server or e.visible):
			continue
		var d: float = _where(e).distance_squared_to(_ship.position)
		if d < best_d:
			best_d = d
			best = e
	return best


## The server doesn't move entities between ticks (every peer computes their
## paths), so it asks for the position now; a client uses what it draws.
func _where(e: SpaceEntity) -> Vector2:
	return e.position_at(PlayerNet.now()) if _arena.config.is_server else e.position
