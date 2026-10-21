extends Node
## Entry point for every build (editor run, native client, dedicated server,
## web). Reads the launch config, loads the chosen game, then hosts or joins.
##
## The game scene is added BEFORE connecting on clients. The server starts
## replicating spawns the moment a peer connects; if the MultiplayerSpawner
## isn't in the client's tree yet, those spawn packets have nowhere to go.

var _config: LaunchConfig
var _game: GameBase
var _hud: Hud
var _elapsed: float = 0.0
var _finished: bool = false


func _ready() -> void:
	_config = LaunchConfig.from_environment()
	InputSetup.ensure_actions()

	_game = _make_game(_config.game)
	_game.name = "Game"
	_game.config = _config
	add_child(_game)

	if _config.is_server:
		_start_server()
	else:
		_start_client()


func _make_game(game: String) -> GameBase:
	match game:
		"3d":
			return Arena3D.new()
		_:
			return Arena2D.new()


func _start_server() -> void:
	var err: Error = Net.host(_config.port, _config.bind_address)
	if err != OK:
		push_error("[server] could not listen on port %d: %s" % [_config.port, error_string(err)])
		get_tree().quit(1)
		return
	_game.start_server()
	print("[server] game=%s listening on %s:%d" % [_config.game, _config.bind_address, _config.port])


func _start_client() -> void:
	_hud = Hud.new()
	_hud.name = "Hud"
	add_child(_hud)
	Net.connected.connect(func(id: int) -> void:
		_hud.set_status("Connected  —  WASD / arrows to move, Space to jump")
		print("[client] connected as peer %d" % id))
	Net.connection_failed.connect(func() -> void:
		_hud.set_status("Could not reach %s" % _config.url)
		print("[client] connection failed: %s" % _config.url))
	Net.disconnected.connect(func() -> void:
		_hud.set_status("Disconnected from server")
		print("[client] disconnected"))

	if OS.has_feature("web") and not _config.bot:
		_hud.set_status("Game: %s   Server: %s" % [_config.game, _config.url])
		_hud.show_start(_join)
	else:
		_join()


func _join() -> void:
	_hud.set_status("Connecting to %s ..." % _config.url)
	var err: Error = Net.join(_config.url)
	if err != OK:
		_hud.set_status("Bad server URL: %s" % _config.url)
		push_error("[client] join failed: %s" % error_string(err))


func _process(delta: float) -> void:
	if _config.run_seconds <= 0.0 or _finished:
		return
	_elapsed += delta
	if _elapsed < _config.run_seconds:
		return
	_finished = true
	var report: Dictionary = _game.smoke_report()
	var role: String = "server" if _config.is_server else "client"
	print("SMOKE_RESULT role=%s game=%s %s" % [role, _config.game, JSON.stringify(report)])
	var code: int = 0 if bool(report.get("ok", false)) else 1
	if not _config.is_server:
		# Start the close handshake and keep polling briefly so the server sees
		# a clean disconnect rather than a dropped socket.
		Net.close_gracefully()
		await get_tree().create_timer(0.5).timeout
	_shutdown_game()
	await get_tree().process_frame
	Net.shutdown()
	get_tree().quit(code)


## Free the game (and its MultiplayerSpawner) in a normal frame, then close
## the socket without swapping peers (see Net.shutdown). Tearing these down in
## the other order makes Godot 4.7 release builds log a spurious
## "Attempt to disconnect a nonexistent connection" error.
func _shutdown_game() -> void:
	if _game != null:
		remove_child(_game)
		_game.queue_free()
		_game = null
