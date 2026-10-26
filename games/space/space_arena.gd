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
##   Game/Fx, Radar, Scoreboard  <- client only (SpaceFx, SpaceRadar, SpaceScoreboard)

## How the touch controls work, shown on the menu's Controls page on touch
## screens (they can't be remapped).
## Server bots each smoke-test client asks for.
const SMOKE_BOTS: int = 2
const TOUCH_HELP: String = "Touch: the stick's left/right turns, pushing it up thrusts; tap Fire to shoot."

var entities_root: Node
var entity_spawner: MultiplayerSpawner
var director: SpaceDirector
## Client: one server-time clock for ships and entities, so they're drawn at
## the same moment (a shot leaves the nose of the ship as drawn).
var clock := SnapshotClock.new()
var fx: SpaceFx
var radar: SpaceRadar
var camera: Camera2D
var _stars: Starfield
## Server: scores of players back at ship select, restored when they respawn.
var _banked_scores: Dictionary = {}   # peer id -> score

# Smoke test (client): latched every frame, like GameBase's.
var _best_own_score: int = 0
var _best_score_seen: int = 0
var _own_rcs_frames: int = 0
var _own_pick: Dictionary = {}
var _bot_moved: bool = false
var _own_strafe_frames: int = 0
## Server (smoke test): peers whose ship has strafed.
var strafers: Dictionary = {}
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

	radar = SpaceRadar.new()
	radar.name = "Radar"
	radar.arena = self
	add_child(radar)

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
		InputSetup.UP: "Thrust", InputSetup.DOWN: "Brake",
		InputSetup.STRAFE_LEFT: "Strafe left", InputSetup.STRAFE_RIGHT: "Strafe right",
		InputSetup.FIRE: "Fire",
		InputSetup.MENU: "Ship select",
	}


## Bots (smoke-test clients and server bots) pick a random hull and an auto
## team, so teams stay even and a smoke run always has enemies to fight.
## Smoke-test clients also ask for SMOKE_BOTS server bots (the first one in
## gets them), so every run flies some.
func bot_choice() -> Dictionary:
	return {"hull": randi_range(0, SpaceSim.HULLS.size() - 1),
			"color": SpaceShip.COLOR_AUTO, "bots": SMOKE_BOTS}


func _make_server_bot(player: Node) -> BotInput:
	return SpaceBot.new(player as SpaceShip, self)


## Spawn data "hull" and "color" (always a real colour, which is the team:
## auto and anything out of range join the smallest team, the seat's colour
## on a tie).
func _sanitize_choice(choice: Dictionary, index: int) -> Dictionary:
	var color: int = choice_int(choice, "color", SpaceShip.COLOR_AUTO)
	if color < 0 or color >= SpaceShip.COLORS.size():
		color = SpaceSim.smallest_team(team_sizes(), index)
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


## Ships per team (colour) in the match.
func team_sizes() -> Array[int]:
	var sizes: Array[int] = []
	sizes.resize(SpaceShip.COLORS.size())
	for p: Node in active_players():
		var ship: SpaceShip = p as SpaceShip
		if ship != null:
			sizes[ship.color_index()] += 1
	return sizes


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
		if ship.is_bot() and ship.rendered_distance > 1.0:
			_bot_moved = true
		if ship == own:
			_best_own_score = maxi(_best_own_score, ship.score)
			_own_rcs_frames = maxi(_own_rcs_frames, ship.rcs_frames)
			_own_strafe_frames = maxi(_own_strafe_frames, ship.strafe_frames)
			_own_pick = {"hull": ship.hull(), "color": ship.color_index()}


## On top of "everyone moved": the server saw every player shoot, rocks
## destroyed, the server bots the clients asked for fly and shoot, and a shot
## hit a ship of another team (PvP: bots join on auto, so each is on its own
## team), and every person's ship strafed. Each client drew its own shots, drew an asteroid explode, drew its
## own ship's RCS thrusters (bots turn constantly) and strafing, drew a server bot move,
## showed another ship on its radar, received a score from the server, and got
## the hull and colour it asked for. Any ship's score counts, not only its
## own: whether one particular bot lands a hit in a short run is chance (it
## may spend 2 s of it dead), and the replication path is the same.
func smoke_report() -> Dictionary:
	var report: Dictionary = super.smoke_report()
	if config.is_server:
		var people_fired: int = 0
		var bots_fired: int = 0
		for id: int in director.shots_fired:
			if ServerBots.is_bot(id):
				bots_fired += 1
			else:
				people_fired += 1
		# Smoke clients ask for SMOKE_BOTS bots: they must have flown and shot.
		report["ok"] = bool(report["ok"]) and people_fired >= config.expect_peers \
				and director.asteroids_destroyed > 0 and bots.peak >= SMOKE_BOTS and bots_fired > 0
		report["shooters"] = people_fired
		report["bot_shooters"] = bots_fired
		report["bots_peak"] = bots.peak
		var people_strafed: int = 0
		for id: int in strafers:
			if not ServerBots.is_bot(id):
				people_strafed += 1
		report["strafers"] = people_strafed
		report["pvp_hits"] = director.pvp_hits
		report["pvp_kills"] = director.pvp_kills
		report["ok"] = bool(report["ok"]) and director.pvp_hits > 0 \
				and people_strafed >= config.expect_peers
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
	report["bot_moved"] = _bot_moved
	report["radar_ships"] = radar.ships_shown
	report["own_strafe_frames"] = _own_strafe_frames
	report["ok"] = bool(report["ok"]) and fx.own_shots_seen > 0 and fx.explosions_seen > 0 \
			and _best_score_seen > 0 and _own_rcs_frames > 0 and _got_what_was_asked() and _bot_moved \
			and radar.ships_shown > 0 and _own_strafe_frames > 0
	return report


## Client (smoke): the own ship has the picked hull, and the picked colour
## unless it asked for auto (then any colour will do).
func _got_what_was_asked() -> bool:
	if _own_pick.is_empty() or int(_own_pick["hull"]) != int(join_choice.get("hull", -1)):
		return false
	var asked: int = int(join_choice.get("color", SpaceShip.COLOR_AUTO))
	return asked == SpaceShip.COLOR_AUTO or int(_own_pick["color"]) == asked
