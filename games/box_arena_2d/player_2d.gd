class_name BoxPlayer2D
extends Node2D
## One player in the 2D arena.
##
## Server: reads input from InputRelay, runs ArenaSim, writes net_* props.
## Client: receives net_* props via Sync, buffers them, draws interpolated.
##
## Swap the box for Kenney art: set SPRITE_PATH to an imported texture, e.g.
## "res://assets/kenney/toon-characters/PNG/character_0001.png" or an
## AtlasTexture .tres made by tools/kenney_atlas.gd.

const SPRITE_PATH: String = ""
const BOX_SIZE := Vector2(40, 40)

var peer_id: int = 0
## Join order (0, 1, 2...). Used for labels — peer ids are huge random ints.
var player_index: int = 0
var color: Color = Color.WHITE
## Server: total distance simulated. Client: total distance drawn. Smoke tests read these.
var traveled: float = 0.0
var rendered_distance: float = 0.0

# Replicated state. Setters feed the interpolation buffers on clients.
var net_position: Vector2 = Vector2.ZERO:
	set(v):
		net_position = v
		if not _server_side:
			_pos_buf.push(_now(), v)
var net_rotation: float = 0.0:
	set(v):
		net_rotation = v
		if not _server_side:
			_rot_buf.push(_now(), v)

var _server_side: bool = false
var _state := ArenaSim.State2D.new()
var _relay: InputRelay
var _body: Node2D
var _label: Label
var _pos_buf := SnapshotBuffer.new()
var _rot_buf := SnapshotBuffer.new(true)


## Called by the spawn function on every peer, before the node enters the tree.
func setup(data: Dictionary, server_side: bool, use_bot: bool) -> void:
	_server_side = server_side
	peer_id = int(data["id"])
	player_index = int(data["index"])
	color = Color.from_hsv(float(data["hue"]), 0.65, 0.95)
	_state.position = data["pos"]
	net_position = _state.position
	position = _state.position

	_relay = InputRelay.new()
	_relay.name = "InputRelay"
	_relay.owner_peer = peer_id
	_relay.use_bot = use_bot
	add_child(_relay)
	add_child(Replication.make_synchronizer(PackedStringArray(["net_position", "net_rotation"])))

	if not _server_side:
		_build_visuals()


func _ready() -> void:
	# multiplayer is only reachable once in the tree, so "is this me?" waits until now.
	if _label != null and Net.is_online() and multiplayer.get_unique_id() == peer_id:
		_label.text = "You (P%d)" % (player_index + 1)


func _physics_process(delta: float) -> void:
	if not _server_side:
		return
	var before: Vector2 = _state.position
	ArenaSim.step_2d(_state, _relay.move, delta)
	traveled += before.distance_to(_state.position)
	if _state.velocity.length_squared() > 1.0:
		net_rotation = _state.velocity.angle()
	net_position = _state.position
	position = net_position


func _process(_delta: float) -> void:
	if _server_side or _pos_buf.is_empty():
		return
	var t: float = _now() - Protocol.INTERP_DELAY
	var p: Vector2 = _pos_buf.sample(t)
	rendered_distance += position.distance_to(p)
	position = p
	if not _rot_buf.is_empty():
		_body.rotation = float(_rot_buf.sample(t))


func _build_visuals() -> void:
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)

	if not SPRITE_PATH.is_empty() and ResourceLoader.exists(SPRITE_PATH):
		var sprite := Sprite2D.new()
		sprite.texture = load(SPRITE_PATH) as Texture2D
		sprite.modulate = color
		_body.add_child(sprite)
	else:
		var h: Vector2 = BOX_SIZE * 0.5
		var box := Polygon2D.new()
		box.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
		box.color = color
		_body.add_child(box)
		var nose := Polygon2D.new()  # shows facing
		nose.polygon = PackedVector2Array([Vector2(h.x, -8), Vector2(h.x + 14, 0), Vector2(h.x, 8)])
		nose.color = color.lightened(0.4)
		_body.add_child(nose)

	var label := Label.new()
	label.text = "P%d" % (player_index + 1)
	label.position = Vector2(-40, -BOX_SIZE.y - 8)
	label.custom_minimum_size = Vector2(80, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	_label = label


static func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
