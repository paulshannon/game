class_name SpaceArena
extends GameBase
## Space: co-op asteroid shooting in a bounded star field. Ships with momentum
## (SpaceShip) shoot asteroids that split into smaller, more valuable pieces;
## some drop pickups. Rules are SpaceSim, run on the server by SpaceDirector.
## Its main menu is SpaceMenu.
##
## Node layout on top of GameBase's (identical on every peer where replicated):
##   Game/Entities        <- asteroids, shots, pickups (SpaceEntity), by id
##   Game/EntitySpawner   <- MultiplayerSpawner, spawn_path -> Entities
##   Game/Director        <- server only (SpaceDirector)
##   Game/Fx, Scoreboard  <- client only (SpaceFx, SpaceScoreboard)

var entities_root: Node
var entity_spawner: MultiplayerSpawner
var director: SpaceDirector
## Client: one server-time clock for ships and entities, so they're drawn at
## the same moment (a shot leaves the nose of the ship as drawn).
var clock := SnapshotClock.new()
var fx: SpaceFx

# Smoke test (client): latched every frame, like GameBase's.
var _best_own_score: int = 0
var _best_score_seen: int = 0
var _own_rcs_frames: int = 0


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
	RenderingServer.set_default_clear_color(Color(0.03, 0.04, 0.09))
	var backdrop := CanvasLayer.new()
	backdrop.name = "Backdrop"
	backdrop.layer = -10  # screen-space, behind the world
	backdrop.add_child(Starfield.new())
	add_child(backdrop)

	var r: Rect2 = SpaceSim.BOUNDS
	var edge := Line2D.new()
	edge.name = "Edge"
	edge.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	edge.closed = true
	edge.width = 3.0
	edge.default_color = Color(SpaceUi.ACCENT, 0.6)
	edge.z_index = -9
	add_child(edge)

	var cam := Camera2D.new()
	cam.name = "Camera"
	add_child(cam)
	cam.make_current()

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
	return SpaceMenu.new()


func action_button() -> StringName:
	return InputSetup.FIRE


func controls_help(touch: bool) -> String:
	if touch:
		return "stick: left/right turns, up thrusts  ·  tap Fire to shoot"
	return "Left/Right (A/D) turn, Up (W) thrust, Down (S) brake, Space fire"


func _spawn_position(index: int) -> Variant:
	return Vector2.from_angle(index * TAU / Protocol.MAX_PLAYERS) * 160.0


func _create_player(data: Dictionary) -> Node:
	var p := SpaceShip.new()
	p.setup(data, config.is_server, config.bot, self)
	return p


func _spawn_entity(data: Variant) -> Node:
	var e := SpaceEntity.new()
	e.setup(data as Dictionary)
	if not config.is_server:
		e.setup_client(clock, fx)
	return e


# --- smoke test ---------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if config.is_server or config.run_seconds <= 0.0 or not Net.is_online():
		return
	var own: Node = local_player()
	for p: Node in active_players():
		var ship: SpaceShip = p as SpaceShip
		_best_score_seen = maxi(_best_score_seen, ship.score)
		if ship == own:
			_best_own_score = maxi(_best_own_score, ship.score)
			_own_rcs_frames = maxi(_own_rcs_frames, ship.rcs_frames)


## On top of "everyone moved": the server saw every player shoot and rocks
## destroyed; each client drew its own shots, drew an asteroid explode, drew
## its own ship's RCS thrusters (bots turn constantly), and received a score
## from the server. Any ship's score counts, not only its
## own: whether one particular bot lands a hit in a short run is chance (it
## may spend 2 s of it dead), and the replication path is the same.
func smoke_report() -> Dictionary:
	var report: Dictionary = super.smoke_report()
	if config.is_server:
		var everyone_fired: bool = director.shots_fired.size() >= config.expect_peers
		report["ok"] = bool(report["ok"]) and everyone_fired and director.asteroids_destroyed > 0
		report["shooters"] = director.shots_fired.size()
		report["asteroids_destroyed"] = director.asteroids_destroyed
		report["ships_destroyed"] = director.ships_destroyed
		report["pickups_taken"] = director.pickups_taken
		report["scores"] = director.scores
		return report
	report["own_shots_seen"] = fx.own_shots_seen
	report["explosions_seen"] = fx.explosions_seen
	report["own_score"] = _best_own_score
	report["own_rcs_frames"] = _own_rcs_frames
	report["best_score_seen"] = _best_score_seen
	report["ok"] = bool(report["ok"]) and fx.own_shots_seen > 0 and fx.explosions_seen > 0 \
			and _best_score_seen > 0 and _own_rcs_frames > 0
	return report
