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

var traveled: float = 0.0
var rendered_distance: float = 0.0

# Declared before the synced properties: their setters call it.
var _net := PlayerNet.new(false)

# Replicated state (PlayerNet.SYNCED). Setters feed PlayerNet on clients.
var net_time: float = 0.0:
	set(v):
		net_time = v
		_net.on_time(v)
var net_position: Vector3 = Vector3.ZERO:
	set(v):
		net_position = v
		_net.on_position(net_time, v)
## Quaternion, not Euler: slerp takes the short way round and never flips.
var net_rotation: Quaternion = Quaternion.IDENTITY:
	set(v):
		net_rotation = v
		_net.on_rotation(net_time, v)

var _state := ArenaSim.State3D.new()
var _body: Node3D
var _label: Label3D


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
	var before: Vector3 = _state.position
	ArenaSim.step_3d(_state, _net.relay.move, _net.relay.jump, delta)
	traveled += before.distance_to(_state.position)
	net_rotation = ArenaSim.facing_from_velocity(_state.velocity, net_rotation)
	net_time = PlayerNet.now()
	net_position = _state.position
	position = net_position


func _process(_delta: float) -> void:
	if not _net.can_render():
		return
	var t: float = _net.render_time()
	var p: Vector3 = _net.position_at(t)
	rendered_distance += position.distance_to(p)
	position = p
	var r: Variant = _net.rotation_at(t)
	if r != null:
		_body.quaternion = r


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
		mat.albedo_color = _net.color
		box.material = mat
		mesh.mesh = box
		mesh.position.y = BOX_SIZE * 0.5
		_body.add_child(mesh)
		var nose := MeshInstance3D.new()  # shows facing (+Z)
		var nose_mesh := BoxMesh.new()
		nose_mesh.size = Vector3(0.25, 0.25, 0.3)
		var nose_mat := StandardMaterial3D.new()
		nose_mat.albedo_color = _net.color.lightened(0.5)
		nose_mesh.material = nose_mat
		nose.mesh = nose_mesh
		nose.position = Vector3(0, BOX_SIZE * 0.6, BOX_SIZE * 0.6)
		_body.add_child(nose)

	var label := Label3D.new()
	label.text = "P%d" % (_net.player_index + 1)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = BOX_SIZE + 0.6
	label.font_size = 48
	label.pixel_size = 0.01
	label.outline_size = 12
	add_child(label)
	_label = label
