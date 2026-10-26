class_name Arena3D
extends GameBase
## 3D prototype: boxes that run and jump on a flat floor. Lighting is kept
## within the Compatibility renderer's budget (one directional light, no
## SDFGI/SSR/volumetrics) so the web build matches the editor.

const CAMERA_OFFSET := Vector3(0.0, 11.0, 11.0)

var _camera: Camera3D


func _build_client_world() -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	var size: float = (ArenaSim.HALF_EXTENT_3D + 1.0) * 2.0
	plane.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.42, 0.36)
	plane.material = mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.6
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	add_child(world_env)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.position = CAMERA_OFFSET
	add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.make_current()


func _process(delta: float) -> void:
	super(delta)
	if _camera == null:
		return
	var me: Node3D = local_player() as Node3D
	var target: Vector3 = me.position if me != null else Vector3.ZERO
	# Exponential smoothing: frame-rate independent follow.
	var w: float = 1.0 - exp(-6.0 * delta)
	_camera.position = _camera.position.lerp(target + CAMERA_OFFSET, w)
	_camera.look_at(_camera.position - CAMERA_OFFSET)


func action_button() -> StringName:
	return InputSetup.JUMP


func _spawn_position(index: int, _choice: Dictionary) -> Variant:
	var a: float = index * TAU / Protocol.MAX_PLAYERS
	return Vector3(cos(a), 0.0, sin(a)) * 4.0


func _create_player(data: Dictionary) -> Node:
	var p := BoxPlayer3D.new()
	p.setup(data, config.is_server, config.bot)
	return p
