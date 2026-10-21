class_name BoxPlayer3D
extends Node3D
## One player in the 3D arena. Same server/client split as BoxPlayer2D.
##
## Swap the box for a Kenney model: copy a pack into assets/kenney/ with
## tools/add_kenney_pack.sh, then set MODEL_PATH to one of its GLBs, e.g.
## "res://assets/kenney/mini-characters/Models/GLB format/character-male-a.glb".
## The model is purely visual — collision and movement stay in ArenaSim.

const MODEL_PATH: String = ""
const MODEL_SCALE: float = 1.0
const BOX_SIZE: float = 0.9

var peer_id: int = 0
## Join order (0, 1, 2...). Used for labels — peer ids are huge random ints.
var player_index: int = 0
var color: Color = Color.WHITE
var traveled: float = 0.0
var rendered_distance: float = 0.0

var net_position: Vector3 = Vector3.ZERO:
	set(v):
		net_position = v
		if not _server_side:
			_pos_buf.push(_now(), v)
## Quaternion, not Euler: slerp takes the short way round and never flips.
var net_rotation: Quaternion = Quaternion.IDENTITY:
	set(v):
		net_rotation = v
		if not _server_side:
			_rot_buf.push(_now(), v)

var _server_side: bool = false
var _state := ArenaSim.State3D.new()
var _relay: InputRelay
var _body: Node3D
var _label: Label3D
var _pos_buf := SnapshotBuffer.new()
var _rot_buf := SnapshotBuffer.new()


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
	var before: Vector3 = _state.position
	ArenaSim.step_3d(_state, _relay.move, _relay.jump, delta)
	traveled += before.distance_to(_state.position)
	net_rotation = ArenaSim.facing_from_velocity(_state.velocity, net_rotation)
	net_position = _state.position
	position = net_position


func _process(_delta: float) -> void:
	if _server_side or _pos_buf.is_empty():
		return
	var t: float = _now() - Protocol.INTERP_DELAY
	var p: Vector3 = _pos_buf.sample(t)
	rendered_distance += position.distance_to(p)
	position = p
	if not _rot_buf.is_empty():
		_body.quaternion = _rot_buf.sample(t)


func _build_visuals() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var scene: PackedScene = null
	if not MODEL_PATH.is_empty() and ResourceLoader.exists(MODEL_PATH):
		scene = load(MODEL_PATH) as PackedScene
	if scene != null:
		var model: Node3D = scene.instantiate() as Node3D
		model.name = "Model"
		model.scale = Vector3.ONE * MODEL_SCALE
		_body.add_child(model)
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * BOX_SIZE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		box.material = mat
		mesh.mesh = box
		mesh.position.y = BOX_SIZE * 0.5
		_body.add_child(mesh)
		var nose := MeshInstance3D.new()  # shows facing (+Z)
		var nose_mesh := BoxMesh.new()
		nose_mesh.size = Vector3(0.25, 0.25, 0.3)
		var nose_mat := StandardMaterial3D.new()
		nose_mat.albedo_color = color.lightened(0.5)
		nose_mesh.material = nose_mat
		nose.mesh = nose_mesh
		nose.position = Vector3(0, BOX_SIZE * 0.6, BOX_SIZE * 0.6)
		_body.add_child(nose)

	var label := Label3D.new()
	label.text = "P%d" % (player_index + 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = BOX_SIZE + 0.6
	label.font_size = 48
	label.pixel_size = 0.01
	label.outline_size = 12
	add_child(label)
	_label = label


static func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0
