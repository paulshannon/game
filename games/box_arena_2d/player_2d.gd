class_name BoxPlayer2D
extends Node2D
## One player in the 2D arena.
##
## Server: reads input from InputRelay, runs ArenaSim, writes net_* props.
## Client: receives net_* props via Sync; PlayerNet buffers them and this
## script draws them interpolated. Network plumbing lives in PlayerNet.
##
## Swap the box for Kenney art: set SPRITE_PATH to an imported texture, e.g.
## "res://assets/kenney/toon-characters/PNG/character_0001.png" or an
## AtlasTexture .tres made by tools/kenney_atlas.gd.

const SPRITE_PATH: String = ""
const BOX_SIZE := Vector2(40, 40)

## Server: total distance simulated. Client: total distance drawn. Smoke tests read these.
var traveled: float = 0.0
var rendered_distance: float = 0.0

# Declared before the synced properties: their setters call it.
var _net := PlayerNet.new(true)

# Replicated state (PlayerNet.SYNCED). Setters feed PlayerNet on clients.
var net_time: float = 0.0:
	set(v):
		net_time = v
		_net.on_time(v)
var net_position: Vector2 = Vector2.ZERO:
	set(v):
		net_position = v
		_net.on_position(net_time, v)
var net_rotation: float = 0.0:
	set(v):
		net_rotation = v
		_net.on_rotation(net_time, v)

var _state := ArenaSim.State2D.new()
var _body: Node2D
var _label: Label


## Called by the spawn function on every peer, before the node enters the tree.
func setup(data: Dictionary, server_side: bool, use_bot: bool) -> void:
	_net.setup(self, data, server_side, use_bot)
	_state.position = data["pos"]
	net_position = _state.position
	position = _state.position
	if not server_side:
		_build_visuals()


func _ready() -> void:
	if _label != null:
		_label.text = _net.label_text(self)


func _physics_process(delta: float) -> void:
	if not _net.server_side:
		return
	var before: Vector2 = _state.position
	ArenaSim.step_2d(_state, _net.relay.move, delta)
	traveled += before.distance_to(_state.position)
	if _state.velocity.length_squared() > 1.0:
		net_rotation = _state.velocity.angle()
	net_time = PlayerNet.now()
	net_position = _state.position
	position = net_position


func _process(_delta: float) -> void:
	if not _net.can_render():
		return
	var t: float = _net.render_time()
	var p: Vector2 = _net.position_at(t)
	rendered_distance += position.distance_to(p)
	position = p
	var r: Variant = _net.rotation_at(t)
	if r != null:
		_body.rotation = float(r)


func _build_visuals() -> void:
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)

	if not SPRITE_PATH.is_empty() and ResourceLoader.exists(SPRITE_PATH):
		var sprite := Sprite2D.new()
		sprite.texture = load(SPRITE_PATH) as Texture2D
		sprite.modulate = _net.color
		_body.add_child(sprite)
	else:
		var h: Vector2 = BOX_SIZE * 0.5
		var box := Polygon2D.new()
		box.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
		box.color = _net.color
		_body.add_child(box)
		var nose := Polygon2D.new()  # shows facing
		nose.polygon = PackedVector2Array([Vector2(h.x, -8), Vector2(h.x + 14, 0), Vector2(h.x, 8)])
		nose.color = _net.color.lightened(0.4)
		_body.add_child(nose)

	var label := Label.new()
	label.text = "P%d" % (_net.player_index + 1)
	label.position = Vector2(-40, -BOX_SIZE.y - 8)
	label.custom_minimum_size = Vector2(80, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	_label = label
