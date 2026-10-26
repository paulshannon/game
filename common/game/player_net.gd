class_name PlayerNet
extends RefCounted
## Network plumbing every player type shares, so a game's player script keeps
## only its simulation step and its visuals. Players extend Node2D or Node3D,
## so they can't share a base class; each one holds a PlayerNet instead.
##
## Server: owns the player's InputRelay (read relay.move / relay.jump) and the
## synchronizer that replicates SYNCED.
## Client: buffers each snapshot stamped with the server time it was simulated
## at (net_time), and samples it on the server timeline via SnapshotClock.
##
## The player declares the synced properties itself (the synchronizer reads
## them off the node) and forwards their setters here:
##   var net_time: float = 0.0:
##       set(v): net_time = v; _net.on_time(v)
##   var net_position: Vector2 = Vector2.ZERO:
##       set(v): net_position = v; _net.on_position(net_time, v)
##   var net_rotation: float = 0.0:
##       set(v): net_rotation = v; _net.on_rotation(net_time, v)

## net_time must come first: the synchronizer applies properties in list
## order, so the time is set before the values it stamps.
const SYNCED: Array[String] = ["net_time", "net_position", "net_rotation"]

var peer_id: int = 0
## Slot in the match (0..MAX_PLAYERS-1). Used for labels and spawn points —
## peer ids are huge random ints.
var player_index: int = 0
var color: Color = Color.WHITE
## Flown by the server (ServerBots), not by a person.
var is_bot: bool = false
var server_side: bool = false
var relay: InputRelay

var _clock := SnapshotClock.new()
var _pos_buf := SnapshotBuffer.new()
var _rot_buf: SnapshotBuffer


## `angular_rotation`: true when rotation is a float angle (2D), false for a
## Quaternion (3D).
func _init(angular_rotation: bool) -> void:
	_rot_buf = SnapshotBuffer.new(angular_rotation)


## Call from the player's setup(), before it enters the tree. Reads the spawn
## data and adds the InputRelay and the synchronizer under `player`.
## `extra_synced`: the player's own props sent with every snapshot after
## SYNCED, so their setters can stamp them with net_time like the position
## (state whose changes must line up with what's drawn).
## `on_change_props`: rarely changing props (score, health), sent only when
## they change (Replication), unstamped.
func setup(player: Node, data: Dictionary, is_server_side: bool, use_bot: bool,
		extra_synced: PackedStringArray = PackedStringArray(),
		on_change_props: PackedStringArray = PackedStringArray()) -> void:
	server_side = is_server_side
	peer_id = int(data["id"])
	player_index = int(data["index"])
	is_bot = bool(data.get("bot", false))
	color = Color.from_hsv(float(data["hue"]), 0.65, 0.95)

	relay = InputRelay.new()
	relay.name = "InputRelay"
	relay.owner_peer = peer_id
	relay.use_bot = use_bot
	player.add_child(relay)
	player.add_child(Replication.make_synchronizer(PackedStringArray(SYNCED) + extra_synced, on_change_props))


## Client: map this player's snapshots with a clock shared with other things
## drawn on the server timeline (other players, projectiles), so they all
## render at the same server time. Call before the first snapshot arrives.
func use_clock(clock: SnapshotClock) -> void:
	_clock = clock


func on_time(t: float) -> void:
	if not server_side:
		_clock.observe(t, now())


## Snapshots before the first server tick (t == 0, e.g. at spawn) are skipped:
## they have no place on the server timeline yet.
func on_position(t: float, v: Variant) -> void:
	if not server_side and t > 0.0:
		_pos_buf.push(t, v)


func on_rotation(t: float, v: Variant) -> void:
	if not server_side and t > 0.0:
		_rot_buf.push(t, v)


## Client: true once there is something to draw.
func can_render() -> bool:
	return not server_side and not _pos_buf.is_empty() and _clock.is_synced()


## Client: server time to draw this frame (call can_render() first).
func render_time() -> float:
	return _clock.render_time(now())


func position_at(t: float) -> Variant:
	return _pos_buf.sample(t)


## Null until the first rotation snapshot arrives.
func rotation_at(t: float) -> Variant:
	return _rot_buf.sample(t)


## Label text. Needs `player` in the tree: multiplayer is only reachable then.
func label_text(player: Node) -> String:
	if Net.is_online() and player.multiplayer.get_unique_id() == peer_id:
		return "You (P%d)" % (player_index + 1)
	if is_bot:
		return "Bot (P%d)" % (player_index + 1)
	return "P%d" % (player_index + 1)


static func now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
