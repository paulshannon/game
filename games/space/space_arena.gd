class_name SpaceArena
extends GameBase
## Space: a 2D prototype in a star field. For now the ships are the shared
## top-down boxes (BoxPlayer2D) and movement is ArenaSim.step_2d; the game's
## own mechanics come next. Its main menu is SpaceMenu.


func _build_client_world() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.04, 0.09))
	var backdrop := CanvasLayer.new()
	backdrop.name = "Backdrop"
	backdrop.layer = -10  # screen-space, behind the world
	backdrop.add_child(Starfield.new())
	add_child(backdrop)

	var r: Rect2 = ArenaSim.BOUNDS_2D.grow(BoxPlayer2D.BOX_SIZE.x * 0.5)
	var edge := Line2D.new()
	edge.name = "Edge"
	edge.points = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	edge.closed = true
	edge.width = 3.0
	edge.default_color = Color(SpaceUi.ACCENT, 0.6)
	edge.z_index = -9
	add_child(edge)

	var cam := Camera2D.new()
	cam.name = "Camera"
	add_child(cam)
	cam.make_current()


func make_menu() -> GameMenu:
	return SpaceMenu.new()


func _spawn_position(index: int) -> Variant:
	return Vector2.from_angle(index * TAU / Protocol.MAX_PLAYERS) * 200.0


func _create_player(data: Dictionary) -> Node:
	var p := BoxPlayer2D.new()
	p.setup(data, config.is_server, config.bot)
	return p
