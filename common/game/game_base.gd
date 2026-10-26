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
## Client: what the player picked before joining (in space: ship and colour,
## {"hull": int, "color": int}), set by main.gd before connecting. Sent to the
## server, which rebuilds it from known keys (_sanitize_choice) and adds those
## to the spawn data.
var join_choice: Dictionary = {}

var players_root: Node
var spawner: MultiplayerSpawner

var _slots := PlayerSlots.new()
## Server: players the server flies itself (the first person in picks how many).
var bots := ServerBots.new(self)
## Server: peers holding a slot whose player isn't spawned yet (waiting for
## their join request).
var _awaiting: Dictionary = {}   # peer id -> true

## Client: leave_to_select() calls in this game (smoke test).
var reselects: int = 0
## Client: how many times our own player was spawned (smoke test).
var own_spawns: int = 0

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
		multiplayer.connected_to_server.connect(send_join)
		_build_client_world()


## Client, once connected (and again after leave_to_select()): ask the
## server to spawn our player with join_choice.
func send_join() -> void:
	_request_spawn.rpc_id(1, join_choice)


## Client: despawn our player but stay connected, keeping the seat, so the
## player can pick again (the menu's ship select) and send_join() back in.
func leave_to_select() -> void:
	reselects += 1
	# Stop sending input now: the server removes the player when this request
	# arrives, and input sent after it would be for a player that's gone.
	var relay: Node = local_player().get_node_or_null("InputRelay") if local_player() != null else null
	if relay != null:
		relay.set_physics_process(false)
	_request_despawn.rpc_id(1)


## Called by Main after the WebSocket server is listening.
func start_server() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Server, before the game leaves the tree: free everything the spawners
## track while they're still in the tree, so each one untracks its nodes
## normally. A spawner that leaves the tree first (a later sibling of its
## spawn root does) untracks them itself, and Godot 4.7 release builds log
## "Attempt to disconnect a nonexistent connection ... tree_exiting" for
## each node still there.
func free_spawned() -> void:
	if not config.is_server:
		return
	for root: Node in _spawn_roots():
		for n: Node in root.get_children():
			n.free()


## Every spawner's spawn_path root. Games with more spawners add theirs.
func _spawn_roots() -> Array[Node]:
	return [players_root]


func local_player() -> Node:
	if not Net.is_online():
		return null
	return players_root.get_node_or_null(str(multiplayer.get_unique_id()))


# --- subclass hooks -----------------------------------------------------------

func _build_client_world() -> void:
	pass


## The game's one action besides moving (InputSetup.JUMP, InputSetup.FIRE),
## or empty for none. Shows the touch button and the keyboard hint.
func action_button() -> StringName:
	return &""


## The game's names for its actions, in display order, for a controls
## settings page (ControlsEditor).
func control_names() -> Dictionary:
	var names: Dictionary = {
		InputSetup.LEFT: "Move left", InputSetup.RIGHT: "Move right",
		InputSetup.UP: "Move up", InputSetup.DOWN: "Move down",
	}
	var act: StringName = action_button()
	if not act.is_empty():
		names[act] = InputSetup.label(act)
	names[InputSetup.MENU] = "Back to select"
	return names


## The controls hint in the status line (games without a menu; a menu shows
## the controls on its own settings page instead).
func controls_help(touch: bool) -> String:
	var act: StringName = action_button()
	var verb: String = InputSetup.label(act).to_lower()
	if touch:
		return "drag on the left to move" + ("" if act.is_empty() else ", tap %s to %s" % [InputSetup.label(act), verb])
	return "WASD / arrows to move" + ("" if act.is_empty() else ", Space to " + verb)


## A start menu for people (not bots), or null for the plain join button.
## Called once on clients; the menu outlives game rebuilds after a disconnect.
func make_menu() -> GameMenu:
	return null


## What a bot picks for join_choice (smoke tests). Any value is fine: the
## server sanitizes it.
func bot_choice() -> Dictionary:
	return {}


## Server: a client's join_choice made safe, as small primitives for the
## spawn data. Clients can send anything: build a fresh Dictionary from the
## keys the game knows (choice_int), never pass theirs on.
func _sanitize_choice(_choice: Dictionary, _index: int) -> Dictionary:
	return {}


## Server: an int from a client's join_choice, `fallback` when missing or not
## a number. Callers still clamp it to their range.
static func choice_int(choice: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = choice.get(key)
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT and is_finite(float(v)):
		return int(clampf(float(v), -1e9, 1e9))
	return fallback


## Where a player spawns: seat `index`, `choice` the game's sanitized join
## choice (_sanitize_choice, e.g. its team).
func _spawn_position(_index: int, _choice: Dictionary) -> Variant:
	return null


func _create_player(_data: Dictionary) -> Node:
	push_error("GameBase._create_player not implemented")
	return Node.new()


# --- server -------------------------------------------------------------------

## The seat is claimed now (a full match turns the peer away at once), but
## the player only spawns when the client's join request arrives with its
## choice, so the spawn data is complete from the first frame.
func _on_peer_connected(id: int) -> void:
	var index: int = _slots.claim(id)
	if index == -1 and bots.give_up_seat():   # bots never keep a person out
		index = _slots.claim(id)
	if index == -1:
		print("[server] rejecting peer %d: match full" % id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_awaiting[id] = true


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_spawn(choice: Dictionary) -> void:
	if not config.is_server:
		return
	var id: int = multiplayer.get_remote_sender_id()
	if not _awaiting.has(id):   # unknown peer, or already spawned
		return
	_awaiting.erase(id)
	# The first person in the match decides how many bots fly.
	var want_bots: int = choice_int(choice, "bots", -1)
	if want_bots >= 0 and _spawned_people() == 0:
		bots.set_count(want_bots)
	var index: int = _slots.claim(id)
	spawn_player(id, index, choice)
	_peers_seen[id] = true
	_max_simultaneous = maxi(_max_simultaneous, _slots.count())
	print("[server] peer %d joined slot %d (%d in match)" % [id, index, _slots.count()])


@rpc("any_peer", "call_remote", "reliable", 0)
func _request_despawn() -> void:
	if not config.is_server:
		return
	var id: int = multiplayer.get_remote_sender_id()
	var p: Node = players_root.get_node_or_null(str(id))
	if p == null:   # not spawned (or not ours to remove: the path is by sender)
		return
	_player_leaving(id, p)
	# Out of the tree now, not at the end of the frame: a join request in the
	# same frame spawns a node with the same name. The spawner replicates
	# the despawn as the node exits.
	players_root.remove_child(p)
	p.queue_free()
	_awaiting[id] = true
	print("[server] peer %d back to select (seat kept)" % id)


## Server: spawns a player in seat `index` on every peer. `choice` is the
## unsanitized join choice; `extra` goes into the spawn data as is.
func spawn_player(id: int, index: int, choice: Dictionary, extra: Dictionary = {}) -> void:
	# Golden-ratio hue spacing gives distinct colors for any player count.
	var hue: float = fmod(index * 0.61803398875, 1.0)
	var data: Dictionary = _sanitize_choice(choice, index)
	data.merge(extra, true)
	data.merge({"id": id, "index": index, "hue": hue, "pos": _spawn_position(index, data)}, true)
	spawner.spawn(data)


func claim_seat(id: int) -> int:
	return _slots.claim(id)


func release_seat(id: int) -> void:
	_slots.release(id)


## Server: people (not bots) with a player in the match.
func _spawned_people() -> int:
	var n: int = 0
	for p: Node in active_players():
		if not ServerBots.is_bot(int(str(p.name))):
			n += 1
	return n


## Server: the BotInput that flies a server bot. Games give theirs a smarter
## pilot (it must read server state: nothing is drawn there).
func _make_server_bot(player: Node) -> BotInput:
	return BotInput.new(int(str(player.name)))


## Server: a player is about to be removed (left, or back to select).
## Subclasses can keep what should survive (space keeps the score).
func _player_leaving(id: int, player: Node) -> void:
	_final_travel[id] = float(_final_travel.get(id, 0.0)) + float(player.get("traveled"))


func _on_peer_disconnected(id: int) -> void:
	_slots.release(id)
	_awaiting.erase(id)
	var p: Node = players_root.get_node_or_null(str(id))
	if p != null:
		_player_leaving(id, p)
		# Removing the node is enough: the spawner replicates the despawn.
		p.queue_free()
	print("[server] peer %d left (%d in match)" % [id, _slots.count()])
	if _slots.count() == bots.count() and bots.count() > 0:   # the last person left
		bots.set_count(0)


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
	if not config.is_server and Net.is_online() and int(d["id"]) == multiplayer.get_unique_id():
		own_spawns += 1
	var relay: InputRelay = p.get_node_or_null("InputRelay") as InputRelay
	if relay != null:
		relay.action = action_button()
		if config.is_server and bool(d.get("bot", false)):
			relay.server_bot = _make_server_bot(p)
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
			var id: int = int(str(p.name))
			travel[id] = float(travel.get(id, 0.0)) + float(p.get("traveled"))
		var all_moved: bool = not travel.is_empty()
		for id: Variant in travel:
			if float(travel[id]) < 1.0:
				all_moved = false
		var ok: bool = _peers_seen.size() >= config.expect_peers and all_moved
		return {"ok": ok, "peers_seen": _peers_seen.size(), "max_simultaneous": _max_simultaneous,
				"travel": travel}
	var need_remote: bool = config.expect_peers > 1
	# Every trip back to select (bots make one) ended in a fresh spawn.
	var ok_client: bool = Net.is_online() and _max_simultaneous >= config.expect_peers \
			and _own_moved and (_remote_moved or not need_remote) and own_spawns > reselects
	return {"ok": ok_client, "peer": multiplayer.get_unique_id() if Net.is_online() else 0,
			"max_simultaneous": _max_simultaneous, "own_moved": _own_moved, "remote_moved": _remote_moved,
			"reselects": reselects, "own_spawns": own_spawns}
