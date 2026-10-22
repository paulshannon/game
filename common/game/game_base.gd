class_name GameBase
extends Node
## Shared match plumbing for every prototype: player spawning/despawning on
## the server and replication to clients. Subclasses supply the world and the
## player type.
##
## Node layout (identical on every peer — RPCs and replication resolve by path):
##   Main/Game
##     Players/          <- spawned players live here, named by peer id
##     PlayerSpawner     <- MultiplayerSpawner, spawn_path -> Players
##     (world nodes added by subclass)

var config: LaunchConfig

var players_root: Node
var spawner: MultiplayerSpawner

var _slots := PlayerSlots.new()

# Smoke-test bookkeeping. The per-frame client part only runs during a smoke
# run (config.run_seconds > 0), off the web main thread in normal play.
var _peers_seen: Dictionary = {}
var _max_simultaneous: int = 0
var _final_travel: Dictionary = {}


func _ready() -> void:
	players_root = Node.new()
	players_root.name = "Players"
	add_child(players_root)

	spawner = MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	# Configure BEFORE add_child: changing spawn_path on a spawner already in
	# the tree makes it try to disconnect from a node it never tracked
	# (engine logs "Attempt to disconnect a nonexistent connection").
	spawner.spawn_path = NodePath("../Players")
	# A custom spawn function lets players be built in code (no .tscn to keep
	# in sync). It runs on the server AND on every client with the same data.
	spawner.spawn_function = _spawn_from_data
	add_child(spawner)

	if not config.is_server:
		_build_client_world()


## Called by Main after the WebSocket server is listening.
func start_server() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func local_player() -> Node:
	if not Net.is_online():
		return null
	return players_root.get_node_or_null(str(multiplayer.get_unique_id()))


# --- subclass hooks -----------------------------------------------------------

func _build_client_world() -> void:
	pass


## Whether the game has a jump (shows the touch Jump button).
func uses_jump() -> bool:
	return false


## A start menu for people (not bots), or null for the plain join button.
## Called once on clients; the menu outlives game rebuilds after a disconnect.
func make_menu() -> GameMenu:
	return null


func _spawn_position(_index: int) -> Variant:
	return null


func _create_player(_data: Dictionary) -> Node:
	push_error("GameBase._create_player not implemented")
	return Node.new()


# --- server -------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	var index: int = _slots.claim(id)
	if index == -1:
		print("[server] rejecting peer %d: match full" % id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# Golden-ratio hue spacing gives distinct colors for any player count.
	var hue: float = fmod(index * 0.61803398875, 1.0)
	spawner.spawn({"id": id, "index": index, "hue": hue, "pos": _spawn_position(index)})
	_peers_seen[id] = true
	_max_simultaneous = maxi(_max_simultaneous, _slots.count())
	print("[server] peer %d joined slot %d (%d in match)" % [id, index, _slots.count()])


func _on_peer_disconnected(id: int) -> void:
	_slots.release(id)
	var p: Node = players_root.get_node_or_null(str(id))
	if p != null:
		_final_travel[id] = float(p.get("traveled"))
		# Removing the node is enough: the spawner replicates the despawn.
		p.queue_free()
	print("[server] peer %d left (%d in match)" % [id, _slots.count()])


## Players still in the match: excludes ones queue_free'd this frame.
func active_players() -> Array[Node]:
	var out: Array[Node] = []
	for p: Node in players_root.get_children():
		if not p.is_queued_for_deletion():
			out.append(p)
	return out


func _spawn_from_data(data: Variant) -> Node:
	var d: Dictionary = data
	var p: Node = _create_player(d)
	p.name = str(d["id"])
	return p


# --- smoke test ---------------------------------------------------------------

var _own_moved: bool = false
var _remote_moved: bool = false


func _process(_delta: float) -> void:
	if config.is_server or config.run_seconds <= 0.0 or not Net.is_online():
		return
	# Latch results every frame: by report time other clients may already
	# have left and their player nodes been despawned.
	var players: Array[Node] = active_players()
	_max_simultaneous = maxi(_max_simultaneous, players.size())
	var own: Node = local_player()
	for p: Node in players:
		_peers_seen[p.name] = true
		if float(p.get("rendered_distance")) > 1.0:
			if p == own:
				_own_moved = true
			else:
				_remote_moved = true


func smoke_report() -> Dictionary:
	if config.is_server:
		var travel: Dictionary = _final_travel.duplicate()
		for p: Node in active_players():
			travel[int(str(p.name))] = float(p.get("traveled"))
		var all_moved: bool = not travel.is_empty()
		for id: Variant in travel:
			if float(travel[id]) < 1.0:
				all_moved = false
		var ok: bool = _peers_seen.size() >= config.expect_peers and all_moved
		return {"ok": ok, "peers_seen": _peers_seen.size(), "max_simultaneous": _max_simultaneous,
				"travel": travel}
	var need_remote: bool = config.expect_peers > 1
	var ok_client: bool = Net.is_online() and _max_simultaneous >= config.expect_peers \
			and _own_moved and (_remote_moved or not need_remote)
	return {"ok": ok_client, "peer": multiplayer.get_unique_id() if Net.is_online() else 0,
			"max_simultaneous": _max_simultaneous, "own_moved": _own_moved, "remote_moved": _remote_moved}
