class_name SpaceBot
extends BotInput
## Pilot for the space game's bots: keeps clear of the star and goes back
## to it to recharge when low on energy; otherwise turns toward the nearest
## enemy ship close by (another team), or else the nearest asteroid it can see; thrusts when
## far, brakes when close, and fires when lined up. So the bots really shoot
## rocks and each other and score over the network, proving the whole loop
## (input -> server rules -> spawns/despawns/score -> client).
## On a client (smoke-test bots) it sees only what that client draws, like a
## player. The server flies its own bots (ServerBots) with it too: there it
## reads the rocks' positions at the current server time. Wanders when there
## is nothing to aim at.

## Enemy ships closer than this are attacked before rocks.
const ENGAGE_RANGE: float = 500.0
## Closer to the star than this, it flies straight out (gravity there beats
## most engines). Below LOW_ENERGY it heads back to recharge at
## RECHARGE_ORBIT, and it keeps SHOT_RESERVE spare when shooting.
const STAR_DANGER: float = 500.0
const LOW_ENERGY: int = 30
const RECHARGE_ORBIT: float = 650.0
const SHOT_RESERVE: float = 5.0
## Away from a fight, a short sideways burst this often (alternating sides).
const STRAFE_EVERY: float = 3.0
const STRAFE_BURST: float = 0.4

var _ship: SpaceShip
var _arena: SpaceArena
var _clock: float = 0.0


func _init(ship: SpaceShip, arena: SpaceArena) -> void:
	super(ship.peer_id())
	_ship = ship
	_arena = arena


func update(delta: float) -> void:
	if not _ship.is_alive():
		super.update(delta)
		fire = false
		strafe = 0.0
		return
	_clock += delta
	# Too close to the star: get out first. Low on energy: head back in to
	# recharge. Otherwise an enemy ship close by (PvP), else the nearest rock.
	var out: Vector2 = _ship.position - SpaceStar.CENTER
	if out.length() < STAR_DANGER:
		strafe = 0.0
		_fly_to(_ship.position + out.normalized() * 600.0, false)
		return
	if _ship.energy < LOW_ENERGY:
		strafe = 0.0
		_fly_to(SpaceStar.CENTER + out.normalized() * RECHARGE_ORBIT, false)
		return
	var aim: Variant = _nearest_enemy()
	strafe = _strafe(aim != null)
	if aim == null:
		var rock: SpaceEntity = _nearest_asteroid()
		if rock == null:
			super.update(delta)
			fire = false
			return
		aim = _where(rock)
	_fly_to(aim as Vector2, _ship.energy >= SpaceStar.SHOT_COST + SHOT_RESERVE)


## Turn towards `target`, close in or back off, and shoot when lined up (if
## `shoot`).
func _fly_to(target: Vector2, shoot: bool) -> void:
	var to: Vector2 = target - _ship.position
	var off: float = angle_difference(_ship.rendered_rotation(), to.angle())
	var dist: float = to.length()
	move.x = clampf(off * 3.0, -1.0, 1.0)
	if dist > 320.0:
		move.y = -0.8          # close in
	elif dist < 130.0:
		move.y = 0.6           # brake / back off
	else:
		move.y = -0.2
	fire = shoot and absf(off) < 0.3 and dist < 700.0
	jump = false


## In a fight, weave from side to side; otherwise now and then a burst.
func _strafe(fighting: bool) -> float:
	if fighting:
		return 1.0 if sin(_clock * 2.0) > 0.0 else -1.0
	if fmod(_clock, STRAFE_EVERY) >= STRAFE_BURST:
		return 0.0
	return 1.0 if int(_clock / STRAFE_EVERY) % 2 == 0 else -1.0


## Where the nearest enemy ship within ENGAGE_RANGE is (another team, alive,
## not protected), or null.
func _nearest_enemy() -> Variant:
	var best: Variant = null
	var best_d: float = ENGAGE_RANGE * ENGAGE_RANGE
	for p: Node in _arena.active_players():
		var other: SpaceShip = p as SpaceShip
		if other == null or other == _ship or other.color_index() == _ship.color_index() \
				or not other.is_alive() or other.is_protected():
			continue
		var d: float = other.position.distance_squared_to(_ship.position)
		if d < best_d:
			best_d = d
			best = other.position
	return best


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
