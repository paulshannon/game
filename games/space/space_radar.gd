class_name SpaceRadar
extends CanvasLayer
## Client: a round radar, top-centre, around your own ship. Ships are dots in
## their team's colour (allies ringed, enemies solid); ships out of range sit
## on the rim, pointing the way to them in unbounded space. Rocks in range
## are faint specks; the star is an orange sun (on the rim when far off);
## starbases are squares in their team's colour, yours solid, so the way
## back to it is always on the rim. Draws what this client draws (positions as rendered),
## and nothing while your ship isn't in the match.

const RADIUS: float = 78.0             # on screen, px
const RANGE: float = 2500.0            # world px from your ship to the rim (~2 screens at SpaceArena.ZOOM)
const TOP: float = 14.0                # gap above it

var arena: SpaceArena
## Most other ships shown at once (smoke test).
var ships_shown: int = 0

var _canvas: Control


func _ready() -> void:
	layer = 4   # with the scoreboard: over the world, under touch controls and menu
	_canvas = Control.new()
	_canvas.name = "Radar"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_radar)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


## Where world point `at` goes on the radar centred at `center`, seen from
## `from`; clamped to the rim when out of range. Second value: in range.
static func to_radar(at: Vector2, from: Vector2, center: Vector2) -> Array:
	var rel: Vector2 = (at - from) / RANGE * RADIUS
	var inside: bool = rel.length() <= RADIUS
	return [center + (rel if inside else rel.limit_length(RADIUS)), inside]


func _draw_radar() -> void:
	var own: SpaceShip = arena.local_player() as SpaceShip if arena != null else null
	if own == null:
		return
	var center := Vector2(_canvas.size.x * 0.5, TOP + RADIUS)
	var ink := Color(SpaceUi.STAR_WHITE, 0.35)
	_canvas.draw_circle(center, RADIUS, Color(0.02, 0.05, 0.12, 0.7))
	_canvas.draw_arc(center, RADIUS, 0.0, TAU, 64, ink, 2.0)
	_canvas.draw_arc(center, RADIUS * 0.5, 0.0, TAU, 48, Color(ink, 0.15), 1.0)

	for n: Node in arena.entities_root.get_children():
		var e: SpaceEntity = n as SpaceEntity
		if e == null or e.kind != SpaceEntity.Kind.ASTEROID or not e.visible:
			continue
		var r: Array = to_radar(e.position, own.position, center)
		if bool(r[1]):
			_canvas.draw_circle(r[0], 1.5, Color(0.75, 0.7, 0.65, 0.5))

	# The star: a sun in range, or a marker on the rim pointing home.
	var sun: Array = to_radar(SpaceStar.CENTER, own.position, center)
	_canvas.draw_circle(sun[0], 6.0 if bool(sun[1]) else 3.0, SpaceStarView.GLOW)

	# The starbases, where they're drawn (on the server timeline).
	if arena.clock.is_synced():
		var t: float = arena.clock.render_time(PlayerNet.now())
		for team: int in SpaceBases.COUNT:
			var b: Array = to_radar(SpaceBases.position(team, t), own.position, center)
			var box := Rect2(b[0] - Vector2(4, 4), Vector2(8, 8))
			if team == own.color_index():
				_canvas.draw_rect(box, SpaceBaseView.team_color(team))
			else:
				_canvas.draw_rect(box, Color(SpaceBaseView.team_color(team), 0.6), false, 1.5)

	var shown: int = 0
	for p: Node in arena.active_players():
		var ship: SpaceShip = p as SpaceShip
		if ship == null or ship == own or not ship.is_alive():
			continue
		shown += 1
		var color: Color = SpaceScoreboard.SHIP_COLORS.get(ship.color_name(), Color.WHITE)
		var r: Array = to_radar(ship.position, own.position, center)
		if ship.color_index() == own.color_index():
			_canvas.draw_arc(r[0], 4.0, 0.0, TAU, 16, color, 2.0)   # ally
		else:
			_canvas.draw_circle(r[0], 4.0, color)                   # enemy
	ships_shown = maxi(ships_shown, shown)

	# You: an arrow along your heading, in your team's colour.
	var heading := Vector2.from_angle(own.rendered_rotation())
	var mine: Color = SpaceScoreboard.SHIP_COLORS.get(own.color_name(), Color.WHITE)
	_canvas.draw_colored_polygon(PackedVector2Array([center + heading * 7.0,
			center + heading.rotated(2.5) * 5.0, center + heading.rotated(-2.5) * 5.0]), mine)
