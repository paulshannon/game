class_name SpaceArena
extends GameBase
## Space: co-op asteroid shooting in an unbounded star field (the camera
## follows your ship; SpaceField keeps rocks coming around every ship). Ships with momentum
## (SpaceShip) shoot asteroids that split into smaller, more valuable pieces;
## some drop pickups. Rules are SpaceSim, run on the server by SpaceDirector.
## Its main menu is SpaceMenu.
##
## Node layout on top of GameBase's (identical on every peer where replicated):
##   Game/Entities        <- asteroids, shots, pickups (SpaceEntity), by id
##   Game/EntitySpawner   <- MultiplayerSpawner, spawn_path -> Entities
##   Game/Director        <- server only (SpaceDirector)
##   Game/Fx, Scoreboard  <- client only (SpaceFx, SpaceScoreboard)

## How the touch controls work, shown on the menu's Controls page on touch
## screens (they can't be remapped).
const TOUCH_HELP: String = "Touch: the stick's left/right turns, pushing it up thrusts; tap Fire to shoot."

var entities_root: Node
var entity_spawner: MultiplayerSpawner
var director: SpaceDirector
## Client: one server-time clock for ships and entities, so they're drawn at
## the same moment (a shot leaves the nose of the ship as drawn).
var clock := SnapshotClock.new()
var fx: SpaceFx
var camera: Camera2D
var _stars: Starfield
## Server: scores of players back at ship select, restored when they respawn.
var _banked_scores: Dictionary = {}   # peer id -> score

# Smoke test (client): latched every frame, like GameBase's.
var _best_own_score: int = 0
var _best_score_seen: int = 0
var _own_rcs_frames: int = 0
var _own_pick: Dictionary = {}
# Smoke test (server): hull and colour each player spawned with, by peer id.
var _picks: Dictionary = {}


func _ready() -> void:
	super._ready()
	entities_root = Node.new()
	entities_root.name = "Entities"
	add_child(entities_root)
	entity_spawner = MultiplayerSpawner.new()
	entity_spawner.name = "EntitySpawner"
	# Configure before add_child (see GameBase).
	entity_spawner.spawn_path = NodePath("../Entities")
	entity_spawner.spawn_function = _spawn_entity
	add_child(entity_spawner)
	if config.is_server:
		director = SpaceDirector.new()
		director.arena = self
		add_child(director)


func start_server() -> void:
	super.start_server()
	director.start()


func _build_client_world() -> void:
	# Process after the ships (children, priority 0), so the camera follows
	# where the own ship is drawn this frame, not last frame.
	process_priority = 1
	RenderingServer.set_default_clear_color(Color(0.03, 0.04, 0.09))
	var backdrop := CanvasLayer.new()
	backdrop.name = "Backdrop"
	backdrop.layer = -10  # screen-space, behind the world
	_stars = Starfield.new()
	backdrop.add_child(_stars)
	add_child(backdrop)

	camera = Camera2D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()

	fx = SpaceFx.new()
	fx.name = "Fx"
	fx.clock = clock
	add_child(fx)

	var board := SpaceScoreboard.new()
	board.name = "Scoreboard"
	board.players_root = players_root
	add_child(board)


func _spawn_roots() -> Array[Node]:
	return [players_root, entities_root]


func make_menu() -> GameMenu:
	return SpaceMenu.new(control_names(), TOUCH_HELP if DisplayServer.is_touchscreen_available() else "")


func action_button() -> StringName:
	return InputSetup.FIRE


func control_names() -> Dictionary:
	return {
		InputSetup.LEFT: "Turn left", InputSetup.RIGHT: "Turn right",
		InputSetup.UP: "Thrust", InputSetup.DOWN: "Brake", InputSetup.FIRE: "Fire",
		InputSetup.MENU: "Ship select",
	}


## Bots pick a random hull and colour (or auto), so smoke runs cover them
## all over time.
func bot_choice() -> Dictionary:
	return {"hull": randi_range(0, SpaceSim.HULLS.size() - 1),
			"color": randi_range(SpaceShip.COLOR_AUTO, SpaceShip.COLORS.size() - 1)}


## Spawn data "hull" and "color" (always a real colour: auto and anything out
## of range become the seat's colour).
func _sanitize_choice(choice: Dictionary, index: int) -> Dictionary:
	var color: int = choice_int(choice, "color", SpaceShip.COLOR_AUTO)
	if color < 0 or color >= SpaceShip.COLORS.size():
		color = index % SpaceShip.COLORS.size()
	return {"hull": SpaceSim.sanitize_hull(choice_int(choice, "hull", SpaceSim.FALCON)),
			"color": color}


## Around the origin at the start; once people have flown off, a newcomer
## joins them instead (round the first ship still in the match).
func _spawn_position(index: int) -> Variant:
	var around: Vector2 = Vector2.ZERO
	for p: Node in active_players():
		var ship: SpaceShip = p as SpaceShip
		if ship != null:
			around = ship.state.position
			break
	return around + Vector2.from_angle(index * TAU / Protocol.MAX_PLAYERS) * 160.0


func _create_player(data: Dictionary) -> Node:
	var p := SpaceShip.new()
	p.setup(data, config.is_server, config.bot, self)
	if config.is_server:
		p.state.score = int(_banked_scores.get(int(data["id"]), 0))
		_banked_scores.erase(int(data["id"]))
		_picks[int(data["id"])] = [p.hull(), p.color_index()]
	return p


## Changing ship keeps your score: bank it until the new ship spawns.
func _player_leaving(id: int, player: Node) -> void:
	super._player_leaving(id, player)
	_banked_scores[id] = (player as SpaceShip).state.score


func _on_peer_disconnected(id: int) -> void:
	super._on_peer_disconnected(id)
	_banked_scores.erase(id)


func _spawn_entity(data: Variant) -> Node:
	var e := SpaceEntity.new()
	e.setup(data as Dictionary)
	if not config.is_server:
		e.setup_client(clock, fx)
	return e


# --- smoke test ---------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if camera != null:
		# The ship is drawn interpolated already, so the camera just sits on it
		# (and stays where it was destroyed until it respawns there).
		var own: Node2D = local_player() as Node2D
		if own != null:
			camera.position = own.position
		_stars.scroll = camera.position
	if config.is_server or config.run_seconds <= 0.0 or not Net.is_online():
		return
	var own: Node = local_player()
	for p: Node in active_players():
		var ship: SpaceShip = p as SpaceShip
		_best_score_seen = maxi(_best_score_seen, ship.score)
		if ship == own:
			_best_own_score = maxi(_best_own_score, ship.score)
			_own_rcs_frames = maxi(_own_rcs_frames, ship.rcs_frames)
			_own_pick = {"hull": ship.hull(), "color": ship.color_index()}


## On top of "everyone moved": the server saw every player shoot and rocks
## destroyed; each client drew its own shots, drew an asteroid explode, drew
## its own ship's RCS thrusters (bots turn constantly), and received a score
## from the server, and its own ship is the hull and colour it asked for. Any ship's score counts, not only its
## own: whether one particular bot lands a hit in a short run is chance (it
## may spend 2 s of it dead), and the replication path is the same.
func smoke_report() -> Dictionary:
	var report: Dictionary = super.smoke_report()
	if config.is_server:
		var everyone_fired: bool = director.shots_fired.size() >= config.expect_peers
		report["ok"] = bool(report["ok"]) and everyone_fired and director.asteroids_destroyed > 0
		report["shooters"] = director.shots_fired.size()
		report["asteroids_destroyed"] = director.asteroids_destroyed
		report["asteroids_dropped"] = director.asteroids_dropped
		report["ships_destroyed"] = director.ships_destroyed
		report["pickups_taken"] = director.pickups_taken
		report["scores"] = director.scores
		report["picks"] = _picks
		return report
	report["own_shots_seen"] = fx.own_shots_seen
	report["explosions_seen"] = fx.explosions_seen
	report["own_score"] = _best_own_score
	report["own_rcs_frames"] = _own_rcs_frames
	report["best_score_seen"] = _best_score_seen
	report["pick"] = {"asked": join_choice, "got": _own_pick}
	report["ok"] = bool(report["ok"]) and fx.own_shots_seen > 0 and fx.explosions_seen > 0 \
			and _best_score_seen > 0 and _own_rcs_frames > 0 and _got_what_was_asked()
	return report


## Client (smoke): the own ship has the picked hull, and the picked colour
## unless it asked for auto (then any colour will do).
func _got_what_was_asked() -> bool:
	if _own_pick.is_empty() or int(_own_pick["hull"]) != int(join_choice.get("hull", -1)):
		return false
	var asked: int = int(join_choice.get("color", SpaceShip.COLOR_AUTO))
	return asked == SpaceShip.COLOR_AUTO or int(_own_pick["color"]) == asked
