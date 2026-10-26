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
var _menu: GameMenu
var _elapsed: float = 0.0
var _finished: bool = false
var _connects: int = 0
var _resetting: bool = false


func _ready() -> void:
	_config = LaunchConfig.from_environment()
	InputSetup.ensure_actions()

	_add_game()
	if _config.is_server:
		_start_server()
	else:
		_start_client()


func _add_game() -> void:
	_game = _make_game(_config.game)
	_game.name = "Game"
	_game.config = _config
	add_child(_game)


func _make_game(game: String) -> GameBase:
	match game:
		"3d":
			return Arena3D.new()
		"space":
			return SpaceArena.new()
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
	var touch: bool = DisplayServer.is_touchscreen_available()
	if not _config.bot:
		InputBindings.load_saved()  # the player's remapped controls, if any
		# Child of Main, not the game, so it survives the game being rebuilt
		# after a disconnect. Harmless on non-touch screens: draws nothing
		# until a touch arrives.
		var controls := TouchControls.new(_game.action_button())
		controls.name = "TouchControls"
		add_child(controls)
		_menu = _game.make_menu()
		if _menu != null:
			_menu.name = "Menu"
			add_child(_menu)
			_menu.play_requested.connect(_join)
	# A game with a menu shows its controls on the menu's settings page.
	var help: String = "" if _menu != null else "  —  " + _game.controls_help(touch)
	Net.connected.connect(func(id: int) -> void:
		_connects += 1
		_hud.set_status("Connected" + help)
		print("[client] connected as peer %d" % id))
	Net.connection_failed.connect(func() -> void:
		print("[client] connection failed: %s" % _config.url)
		_on_connection_lost("Could not reach %s" % _config.url, "Try again"))
	Net.disconnected.connect(func() -> void:
		print("[client] disconnected")
		_on_connection_lost("Disconnected from server", "Rejoin"))

	if _menu != null:
		_menu.show_menu()
	elif OS.has_feature("web") and not _config.bot:
		_hud.set_status("Game: %s   Server: %s" % [_config.game, _config.url])
		_hud.show_start(_join, "Tap to join" if touch else "Click to join")
	else:
		_join()


func _join() -> void:
	if _menu != null:
		_game.join_choice = _menu.choice()
	elif _config.bot:
		_game.join_choice = _game.bot_choice()
	_hud.set_status("Connecting to %s ..." % _config.url)
	var err: Error = Net.join(_config.url)
	if err != OK:
		_hud.set_status("Bad server URL: %s" % _config.url)
		push_error("[client] join failed: %s" % error_string(err))


## Tear down the dead session and offer a fresh one. People get a button
## (any platform); bots retry on their own so smoke tests can restart servers.
func _on_connection_lost(status: String, button: String) -> void:
	if _finished or _resetting:
		return
	_resetting = true
	await _reset_game()
	_resetting = false
	_hud.set_status(status)
	if _config.bot:
		await get_tree().create_timer(Protocol.REJOIN_DELAY).timeout
		if not _finished:
			_join()
	elif _menu != null:
		_menu.show_menu(status, button)
	else:
		_hud.show_start(_join, button)


## Same order as quitting (see _shutdown_game): free the game, let a frame
## pass, and only then swap in the offline peer. The fresh game must be in
## the tree before the next join, for the same reason as at startup.
func _reset_game() -> void:
	_shutdown_game()
	await get_tree().process_frame
	Net.close()
	_add_game()


func _process(delta: float) -> void:
	if _config.run_seconds <= 0.0 or _finished or _resetting:
		return
	_elapsed += delta
	if _elapsed < _config.run_seconds:
		return
	_finished = true
	var report: Dictionary = _game.smoke_report()
	if not _config.is_server:
		report["reconnects"] = maxi(_connects - 1, 0)
	var role: String = "server" if _config.is_server else "client"
	print("SMOKE_RESULT role=%s game=%s %s" % [role, _config.game, JSON.stringify(report)])
	var code: int = 0 if bool(report.get("ok", false)) else 1
	if not _config.is_server:
		# Start the close handshake and keep polling briefly so the server sees
		# a clean disconnect rather than a dropped socket.
		Net.close_socket()
		await get_tree().create_timer(0.5).timeout
	_shutdown_game()
	await get_tree().process_frame
	Net.close_socket()
	get_tree().quit(code)


## Free the game (and its MultiplayerSpawner) in a normal frame, then close
## the socket without swapping peers (see Net.close_socket). Tearing these down in
## the other order makes Godot 4.7 release builds log a spurious
## "Attempt to disconnect a nonexistent connection" error.
func _shutdown_game() -> void:
	if _game != null:
		_game.free_spawned()
		remove_child(_game)
		_game.queue_free()
		_game = null
