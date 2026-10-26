class_name Arena2D
extends GameBase
## 2D prototype: top-down boxes in a walled arena. Replace the boxes with a
## Kenney 2D pack (see BoxPlayer2D.SPRITE_PATH) once the loop feels right.


func _build_client_world() -> void:
	RenderingServer.set_default_clear_color(Color(0.07, 0.08, 0.1))
	var r: Rect2 = ArenaSim.BOUNDS_2D.grow(BoxPlayer2D.BOX_SIZE.x * 0.5)
	var floor_poly := Polygon2D.new()
	floor_poly.name = "Floor"
	floor_poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	floor_poly.color = Color(0.13, 0.15, 0.19)
	floor_poly.z_index = -10
	add_child(floor_poly)

	var wall := Line2D.new()
	wall.name = "Wall"
	wall.points = floor_poly.polygon
	wall.closed = true
	wall.width = 6.0
	wall.default_color = Color(0.45, 0.5, 0.6)
	wall.z_index = -9
	add_child(wall)

	var cam := Camera2D.new()
	cam.name = "Camera"
	add_child(cam)
	cam.make_current()


func _spawn_position(index: int, _choice: Dictionary) -> Variant:
	return Vector2.from_angle(index * TAU / Protocol.MAX_PLAYERS) * 200.0


func _create_player(data: Dictionary) -> Node:
	var p := BoxPlayer2D.new()
	p.setup(data, config.is_server, config.bot)
	return p
